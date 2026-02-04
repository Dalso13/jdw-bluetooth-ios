//
//  BleGattManager.swift
//  JdwBluetooth
//
//  Created by 장동완 on 2/4/26.
//


import Foundation
@preconcurrency import CoreBluetooth
import Combine

/// 블루투스 GATT 연결 및 통신 관리
@available(macOS 10.15, iOS 13.0, *)
final class BleGattManager: NSObject, @unchecked Sendable {
    
    private let config: BleConfig
    private let queue: DispatchQueue
    private let centralManager: CBCentralManager
    private let commandQueue = BleCommandQueue()
    
    // 상태 및 데이터 스트림
    private let connectionStateSubject = CurrentValueSubject<BleConnectionState, Never>(.disconnected)
    private let notifySubject = PassthroughSubject<(String, Data), Never>()
    
    // 외부 공개용 (Combine은 스레드 안전하므로 바로 노출 가능)
    // 단, UI에서 구독할 때는 .receive(on: DispatchQueue.main) 필수
    var connectionStatePublisher: AnyPublisher<BleConnectionState, Never> {
        connectionStateSubject.eraseToAnyPublisher()
    }
    var notifyPublisher: AnyPublisher<(String, Data), Never> {
        notifySubject.eraseToAnyPublisher()
    }
    
    private var connectedPeripheral: CBPeripheral?
    
    // Continuation (변수 보호를 위해 queue 안에서만 접근해야 함)
    private var writeContinuation: CheckedContinuation<Void, Error>?
    private var readContinuation: CheckedContinuation<Data, Error>?
    
    // 타임아웃 태스크
    private var writeTimeoutTask: Task<Void, Never>?
    private var readTimeoutTask: Task<Void, Never>?
    private var connectionTimeoutTask: Task<Void, Never>?
    
    // MARK: - Init
    init(config: BleConfig, centralManager: CBCentralManager, queue: DispatchQueue) {
        self.config = config
        self.centralManager = centralManager
        self.queue = queue // DefaultBleClient에서 만든 큐를 주입받음
        super.init()
        
        if config.isDebugMode {
            print("[GATT] GattManager initialized on background queue")
        }
    }
    
    // MARK: - Connection
    
    func connect(peripheral: CBPeripheral) {
        // 큐에 태워서 실행 (비동기)
        queue.async { [weak self] in
            guard let self = self else { return }
            
            guard self.centralManager.state == .poweredOn else {
                self.updateState(.error(type: .bluetoothDisabled, message: "Bluetooth off"))
                return
            }
            
            // 상태 체크
            if case .connecting = self.connectionStateSubject.value { return }
            if case .ready = self.connectionStateSubject.value { return }
            
            // 연결 시작
            self.connectedPeripheral = peripheral
            peripheral.delegate = self
            self.updateState(.connecting)
            
            self.startConnectionTimeout()
            self.centralManager.connect(peripheral, options: nil)
        }
    }
    
    func disconnect() {
        queue.async { [weak self] in
            guard let self = self, let peripheral = self.connectedPeripheral else { return }
            self.updateState(.disconnecting)
            self.centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    func close() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.connectionTimeoutTask?.cancel()
            self.writeTimeoutTask?.cancel()
            self.readTimeoutTask?.cancel()
            
            self.writeContinuation?.resume(throwing: BleError.connectionClosed)
            self.readContinuation?.resume(throwing: BleError.connectionClosed)
            self.writeContinuation = nil
            self.readContinuation = nil
            
            if let peripheral = self.connectedPeripheral {
                self.centralManager.cancelPeripheralConnection(peripheral)
            }
            self.connectedPeripheral = nil
            self.updateState(.disconnected)
        }
    }
    
    // MARK: - Write / Read (Async/Await)
    
    func writeCharacteristic(
        characteristicUuid: String,
        data: Data,
        serviceUuid: String?,
        writeType: CBCharacteristicWriteType
    ) async throws {
        // commandQueue로 감싸서 동시 요청 시 순차 실행 보장
        try await commandQueue.enqueue {
            try await self.writeCharacteristicInternal(
                characteristicUuid: characteristicUuid,
                data: data,
                serviceUuid: serviceUuid,
                writeType: writeType
            )
        }
    }
    
    private func writeCharacteristicInternal(
        characteristicUuid: String,
        data: Data,
        serviceUuid: String?,
        writeType: CBCharacteristicWriteType
    ) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: BleError.connectionClosed)
                    return
                }
                
                // Busy Check
                guard self.writeContinuation == nil else {
                    continuation.resume(throwing: BleError.busy)
                    return
                }
                
                guard let peripheral = self.connectedPeripheral else {
                    continuation.resume(throwing: BleError.notConnected)
                    return
                }
                
                // UUID 찾기
                let svcUuidStr = serviceUuid ?? self.config.serviceUuid
                guard let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: svcUuidStr) }),
                      let characteristic = service.characteristics?.first(where: { $0.uuid == CBUUID(string: characteristicUuid) }) else {
                    continuation.resume(throwing: BleError.characteristicNotFound)
                    return
                }
                
                // Continuation 저장
                self.writeContinuation = continuation
                
                // 타임아웃
                self.writeTimeoutTask = Task {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if !Task.isCancelled {
                        self.queue.async { self.handleWriteTimeout() }
                    }
                }
                
                peripheral.writeValue(data, for: characteristic, type: writeType)
                
                if writeType == .withoutResponse {
                    self.writeTimeoutTask?.cancel()
                    self.writeContinuation?.resume()
                    self.writeContinuation = nil
                }
            }
        }
    }
    
    func readCharacteristic(serviceUuid: String, characteristicUuid: String) async throws -> Data {
        // commandQueue로 감싸서 동시 요청 시 순차 실행 보장
        return try await commandQueue.enqueue {
            try await self.readCharacteristicInternal(
                serviceUuid: serviceUuid,
                characteristicUuid: characteristicUuid
            )
        }
    }
    
    private func readCharacteristicInternal(serviceUuid: String, characteristicUuid: String) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: BleError.connectionClosed)
                    return
                }
                
                guard self.readContinuation == nil else {
                    continuation.resume(throwing: BleError.busy)
                    return
                }
                
                guard let peripheral = self.connectedPeripheral else {
                    continuation.resume(throwing: BleError.notConnected)
                    return
                }
                
                guard let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: serviceUuid) }),
                      let characteristic = service.characteristics?.first(where: { $0.uuid == CBUUID(string: characteristicUuid) }) else {
                    continuation.resume(throwing: BleError.characteristicNotFound)
                    return
                }
                
                self.readContinuation = continuation
                
                self.readTimeoutTask = Task {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if !Task.isCancelled {
                        self.queue.async { self.handleReadTimeout() }
                    }
                }
                
                peripheral.readValue(for: characteristic)
            }
        }
    }
    
    // MARK: - Internal Helpers (Must run on queue)
    
    private func handleWriteTimeout() {
        writeContinuation?.resume(throwing: BleError.timeout)
        writeContinuation = nil
    }
    
    private func handleReadTimeout() {
        readContinuation?.resume(throwing: BleError.timeout)
        readContinuation = nil
    }
    
    private func startConnectionTimeout() {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(config.connectionTimeoutSeconds * 1_000_000_000))
            if !Task.isCancelled {
                self.queue.async {
                    if case .connecting = self.connectionStateSubject.value {
                        self.updateState(.error(type: .timeout, message: "Connection Timeout"))
                        self.disconnect() // 내부에서 queue.async 한번 더 호출하지만 안전함
                    }
                }
            }
        }
    }
    
    private func updateState(_ newState: BleConnectionState) {
        if config.isDebugMode { print("[GATT] State: \(newState)") }
        connectionStateSubject.send(newState)
    }
    
    // Delegate Handlers (DefaultBleClient에서 호출)
    func handleConnectSuccess(peripheral: CBPeripheral) {
        queue.async {
            self.connectionTimeoutTask?.cancel()
            self.updateState(.discovering)
            peripheral.discoverServices(nil)
        }
    }
    
    func handleConnectFail(error: Error?) {
        queue.async {
            self.connectionTimeoutTask?.cancel()
            self.updateState(.error(type: .gattError, message: error?.localizedDescription ?? "Connection Failed"))
        }
    }
    
    func handleDisconnect(error: Error?) {
        queue.async {
            self.connectionTimeoutTask?.cancel()
            let disconnectedPeripheral = self.connectedPeripheral
            self.connectedPeripheral = nil
            
            if let error = error {
                self.updateState(.error(type: .disconnectedByDevice, message: error.localizedDescription))
                
                // 자동 재연결 설정 확인
                if self.config.shouldAutoConnect, let peripheral = disconnectedPeripheral {
                    if self.config.isDebugMode {
                        print("[GATT] Auto-reconnecting...")
                    }
                    // 잠시 후 재연결 시도
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2초 대기
                        self.queue.async {
                            self.connect(peripheral: peripheral)
                        }
                    }
                }
            } else {
                self.updateState(.disconnected)
            }
        }
    }
}

// MARK: - CBPeripheralDelegate
@available(macOS 10.15, iOS 13.0, *)
extension BleGattManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if error != nil {
            updateState(.error(type: .gattError, message: "Service discovery failed"))
            disconnect() // queue 안이므로 바로 호출 가능
            return
        }
        
        peripheral.services?.forEach { service in
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if error != nil { return }
        
        // 모든 서비스 탐색 완료 확인
        let allDiscovered = peripheral.services?.allSatisfy { $0.characteristics != nil } ?? false
        
        if allDiscovered {
            // Config에서 Notification 자동 활성화 설정 확인
            if config.enableNotificationOnConnect,
               let notifyCharUuid = config.notifyCharUuid {
                
                // notifyCharUuid에 해당하는 characteristic 찾기
                for service in peripheral.services ?? [] {
                    if let characteristic = service.characteristics?.first(where: { $0.uuid == CBUUID(string: notifyCharUuid) }) {
                        peripheral.setNotifyValue(true, for: characteristic)
                        if config.isDebugMode {
                            print("[GATT] Auto-enabled notification for \(notifyCharUuid)")
                        }
                        break
                    }
                }
            }
            
            updateState(.ready)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        writeTimeoutTask?.cancel()
        if let error = error {
            writeContinuation?.resume(throwing: error)
        } else {
            writeContinuation?.resume(returning: ())
        }
        writeContinuation = nil
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            readTimeoutTask?.cancel()
            readContinuation?.resume(throwing: error)
            readContinuation = nil
            return
        }
        
        guard let data = characteristic.value else { return }
        
        // Read 응답
        if let continuation = readContinuation {
            readTimeoutTask?.cancel()
            continuation.resume(returning: data)
            readContinuation = nil
            return
        }
        
        // Notification
        notifySubject.send((characteristic.uuid.uuidString, data))
    }
}