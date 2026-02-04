//
//  BleError.swift
//  JdwBluetooth
//
//  Created by 장동완 on 2/4/26.
//

/// 블루투스 에러 타입
public enum BleError: Error, Equatable {
    /// 연결 시간 초과
    case timeout
    /// 133번 에러 등 GATT 내부 에러
    case gattError
    /// 권한 없음
    case permissionDenied
    /// 상대가 끊음
    case disconnectedByDevice
    /// 블루투스 안켜져있음
    case bluetoothDisabled
    /// 스캔 실패함
    case scanFailed    /// Peripheral을 찾을 수 없음
    case peripheralNotFound
    /// 연결이 닫혀있음
    case notConnected
    /// Service를 찾을 수 없음
    case serviceNotFound
    /// Characteristic을 찾을 수 없음
    case characteristicNotFound
    /// 연결이 닫혔음
    case connectionClosed
    /// 이미 다른 작업 수행 중
    case busy}
