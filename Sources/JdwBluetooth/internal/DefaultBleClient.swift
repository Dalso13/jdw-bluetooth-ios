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
final class DefaultBleClient: BleClient {
    private let config: BleConfig
    private let bleQueue: DispatchQueue
    private let centralManager: CBCentralManager
    private let scanner: BleScanner
    private let gattManager: BleGattManager
    
    init(config: BleConfig) {
        self.config = config
        
        // Background queue for BLE operations
        self.bleQueue = DispatchQueue(
            label: "com.jdw.bluetooth.queue",
            qos: .userInitiated
        )
        
        // Create single CBCentralManager with background queue
        self.centralManager = CBCentralManager(delegate: nil, queue: bleQueue)
        
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
