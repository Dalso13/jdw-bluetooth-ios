//
//  BleScanState.swift
//  JdwBluetooth
//
//  Created by 장동완 on 2/4/26.
//

@preconcurrency import CoreBluetooth

/// 블루투스 스캔 상태
public enum BleScanState: Equatable {
    /// 초기 상태
    case idle
    /// 스캔 중지됨 (타임아웃 또는 사용자 요청)
    case stopped
    /// 스캔 중
    case scanning(peripherals: [CBPeripheral])
    /// 에러 처리
    case error(type: BleError, message: String?)
    
    public static func == (lhs: BleScanState, rhs: BleScanState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.stopped, .stopped):
             return true
        case let (.scanning(lPeripherals), .scanning(rPeripherals)):
            return lPeripherals.map { $0.identifier } == rPeripherals.map { $0.identifier }
        case let (.error(lType, lMessage), .error(rType, rMessage)):
            return lType == rType && lMessage == rMessage
        default:
            return false
        }
    }
}
