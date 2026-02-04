//
//  BleScanner.swift
//  JdwBluetooth
//
//  Created by 장동완 on 2/4/26.
//

import Foundation
import CoreBluetooth
import Combine

/// 블루투스 스캔 담당 클래스
/// 백그라운드 시리얼 큐에서 실행되어 UI 성능 저하 방지
@available(macOS 10.15, iOS 13.0, *)
final class BleScanner: NSObject, @unchecked Sendable {
    
    private let config: BleConfig
    private let centralManager: CBCentralManager
    
    // ⭐ 모든 로직이 실행될 전용 큐 (DefaultBleClient로부터 주입받음)
    private let queue: DispatchQueue
    
    // 상태 관리
    private let scanStateSubject = CurrentValueSubject<BleScanState, Never>(.idle)
    var scanStatePublisher: AnyPublisher<BleScanState, Never> {
        scanStateSubject.eraseToAnyPublisher()
    }
    
    // 발견된 디바이스 저장 (중복 제거용)
    // 이 변수는 오직 queue 안에서만 접근해야 함 (Thread-Safe)
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    
    // 타임아웃 작업
    private var scanTimeoutTask: Task<Void, Never>?
    
    // MARK: - Init
    init(config: BleConfig, centralManager: CBCentralManager, queue: DispatchQueue) {
        self.config = config
        self.centralManager = centralManager
        self.queue = queue
        
        if config.isDebugMode {
            print("[Scanner] Scanner initialized on background queue")
        }
    }
    
    // MARK: - Actions
    
    func startScan() {
        // 외부에서 호출하므로 queue에 태워서 실행
        queue.async { [weak self] in
            guard let self = self else { return }
            
            guard self.centralManager.state == .poweredOn else {
                if self.config.isDebugMode {
                    print("[Scanner] Bluetooth is not powered on")
                }
                // 필요하다면 에러 상태 전송
                return
            }
            
            if self.config.isDebugMode {
                print("[Scanner] Starting scan...")
            }
            
            // 리스트 초기화
            self.discoveredPeripherals.removeAll()
            self.scanStateSubject.send(.scanning(peripherals: []))
            
            // UUID 변환 (String -> CBUUID)
            let serviceUUIDs = [CBUUID(string: self.config.serviceUuid)]
            
            // 중복 허용 옵션 (RSSI 업데이트 등을 위해 false 권장, 필요시 true)
            self.centralManager.scanForPeripherals(
                withServices: serviceUUIDs,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )

            // 타임아웃 설정
            self.startTimeout()
        }
    }
    
    func stopScan() {
        queue.async { [weak self] in
            self?.performStopScan()
        }
    }
    
    // 내부적으로 스캔 중지 수행 (queue 안에서 호출되어야 함)
    private func performStopScan() {
        if config.isDebugMode {
            print("[Scanner] Stopping scan")
        }
        
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        
        if centralManager.isScanning {
            centralManager.stopScan()
        }
        
        scanStateSubject.send(.stopped)
    }
    
    func getPeripheral(by id: UUID) -> CBPeripheral? {
        return queue.sync {
            return discoveredPeripherals[id]
        }
    }
    
    func clearDiscoveredDevices() {
        queue.async { [weak self] in
            if self?.config.isDebugMode == true {
                print("[Scanner] Clearing discovered devices")
            }
            self?.performStopScan()
            self?.discoveredPeripherals.removeAll()
        }
    }
    
    // MARK: - Internal Delegate Methods (called from DefaultBleClient)
    
    func handleBluetoothStateUpdate(_ state: CBManagerState) {
        if config.isDebugMode {
            print("[Scanner] Bluetooth state: \(state.rawValue)")
        }
        
        if state != .poweredOn {
            performStopScan()
        }
    }
    
    func handleDiscoveredPeripheral(_ peripheral: CBPeripheral, advertisementData: [String : Any], rssi: NSNumber) {
    
        // 중복 확인 및 저장
        if discoveredPeripherals[peripheral.identifier] == nil {
            discoveredPeripherals[peripheral.identifier] = peripheral
            
            if config.isDebugMode {
                let name = peripheral.name ?? "Unknown"
                print("[Scanner] Discovered: \(name) (\(peripheral.identifier))")
            }

            scanStateSubject.send(.scanning(peripherals: Array(discoveredPeripherals.values)))
        }
    }
    
    // MARK: - Private Helpers
    
    private func startTimeout() {
        guard config.scanTimeoutSeconds > 0 else { return }
        
        scanTimeoutTask?.cancel()
        let timeoutSeconds = config.scanTimeoutSeconds
        let isDebug = config.isDebugMode
        
        scanTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            
            if !Task.isCancelled {
                // 타임아웃 발생 시 다시 queue로 들어와서 멈춤
                guard let self = self else { return }
                self.queue.async {
                    self.performStopScan()
                    if isDebug {
                        print("[Scanner] Scan timeout reached")
                    }
                }
            }
        }
    }
}
