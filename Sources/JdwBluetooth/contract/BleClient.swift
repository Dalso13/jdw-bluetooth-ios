//
//  BleClient.swift
//  JdwBluetooth
//
//  Created by 장동완 on 2/4/26.
//

import Combine
@preconcurrency import CoreBluetooth

/// 블루투스 클라이언트 프로토콜
@available(macOS 10.15, iOS 13.0, *)
public protocol BleClient: AnyObject {
    
    // 현재 스캔 상태
    var scanStatePublisher: AnyPublisher<BleScanState, Never> { get }
    
    // 현재 연결 상태
    var connectionStatePublisher: AnyPublisher<BleConnectionState, Never> { get }
    
    // 데이터 수신 스트림 (Notification)
    // Pair 대신 Tuple (String, Data) 사용
    var notifyPublisher: AnyPublisher<(String, Data), Never> { get }
    
    // -------------------------------------------------------------
    
    // 스캔 시작
    func startScan()
    
    // 스캔 중지
    func stopScan()
    
    // 연결 시작 (peripheralId로 연결)
    func connect(peripheralId: UUID) async throws
    
    // 데이터 쓰기 (serviceUuid와 characteristicUuid 모두 필수)
    func writeCharacteristic(
        serviceUuid: String,
        characteristicUuid: String,
        value: Data,
        writeType: CBCharacteristicWriteType
    ) async throws
    
    // 데이터 읽기 (serviceUuid와 characteristicUuid 모두 필수)
    func readCharacteristic(
        serviceUuid: String,
        characteristicUuid: String
    ) async throws -> Data
    
    // 연결 해제
    func disconnect() async
}
