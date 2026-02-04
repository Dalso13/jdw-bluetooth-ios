//
//  DefaultBleClient.swift
//  JdwBluetooth
//
//  Created by 장동완 on 2/4/26.
//

import Foundation
@preconcurrency import CoreBluetooth
import Combine

/// BleClient 구현체
/// CBCentralManager를 소유하고 Scanner와 GattManager에 주입
@available(macOS 10.15, iOS 13.0, *)
final class DefaultBleClient: NSObject, BleClient {
    private let config: BleConfig
    private let bleQueue: DispatchQueue

    private var centralManager: CBCentralManager!
    private var scanner: BleScanner!
    private var gattManager: BleGattManager!
    
    init(config: BleConfig) {
        self.config = config
        
        // Background queue for BLE operations
        self.bleQueue = DispatchQueue(
            label: "com.jdw.bluetooth.queue",
            qos: .userInitiated
        )
    
        super.init()
        
        // Create single CBCentralManager with background queue
        self.centralManager = CBCentralManager(delegate: self, queue: bleQueue)
        
        // Inject centralManager into components
        self.scanner = BleScanner(config: config, centralManager: centralManager, queue: bleQueue)
        self.gattManager = BleGattManager(config: config, centralManager: centralManager, queue: bleQueue)
        
        if config.isDebugMode {
            print("[BleClient] Initialized with background queue")
        }
    }
    
    // MARK: - BleClient Protocol Implementation
    
    public var scanStatePublisher: AnyPublisher<BleScanState, Never> {
        scanner.scanStatePublisher
    }
    
    public var connectionStatePublisher: AnyPublisher<BleConnectionState, Never> {
        gattManager.connectionStatePublisher
    }
    
    public var notifyPublisher: AnyPublisher<(String, Data), Never> {
        gattManager.notifyPublisher
    }
    
    public func startScan() {
        scanner.startScan()
    }
    
    public func stopScan() {
        scanner.stopScan()
    }
    
    public func connect(peripheralId: UUID) async throws {
        guard let peripheral = scanner.getPeripheral(by: peripheralId) else {
            throw BleError.peripheralNotFound
        }
        gattManager.connect(peripheral: peripheral)
    }
    
    public func disconnect() async {
        gattManager.disconnect()
    }
    
    public func writeCharacteristic(serviceUuid: String, characteristicUuid: String, value: Data, writeType: CBCharacteristicWriteType = .withResponse) async throws {
        try await gattManager.writeCharacteristic(
            characteristicUuid: characteristicUuid,
            data: value,
            serviceUuid: serviceUuid,
            writeType: writeType
        )
    }
    
    public func readCharacteristic(serviceUuid: String, characteristicUuid: String) async throws -> Data {
        try await gattManager.readCharacteristic(serviceUuid: serviceUuid, characteristicUuid: characteristicUuid)
    }
}

@available(macOS 10.15, iOS 13.0, *)
extension DefaultBleClient: CBCentralManagerDelegate {
    
    // 블루투스 상태 변경 -> Scanner와 GattManager에게 알림
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        scanner.handleBluetoothStateUpdate(central.state)
    }
    
    // 스캔 결과 발견 -> Scanner에게 토스
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        scanner.handleDiscoveredPeripheral(peripheral, advertisementData: advertisementData, rssi: RSSI)
    }
    
    // 연결 성공 -> GattManager에게 토스
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        gattManager.handleConnectSuccess(peripheral: peripheral)
    }
    
    // 연결 실패 -> GattManager에게 토스
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        gattManager.handleConnectFail(error: error)
    }
    
    // 연결 끊김 -> GattManager에게 토스
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        gattManager.handleDisconnect(error: error)
    }
}