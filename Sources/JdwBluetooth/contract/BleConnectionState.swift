//
//  BleConnectionState.swift
//  JdwBluetooth
//
//  Created by 장동완 on 2/4/26.
//

/// 블루투스 연결 상태
public enum BleConnectionState: Equatable {
    /// 초기 상태
    case disconnected
    /// 연결 시도 중 (GATT 연결)
    case connecting
    /// 연결 후 서비스 찾기 (Service Discovery)
    case discovering
    /// 진짜 통신 가능한 상태 (서비스 찾기 완료)
    case ready
    /// 연결 해제 중
    case disconnecting
    /// 에러 상태
    case error(type: BleError, message: String)
}
