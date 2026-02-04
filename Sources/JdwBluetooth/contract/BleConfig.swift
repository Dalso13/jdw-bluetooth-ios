//
//  BleConfig.swift
//  JdwBluetooth
//
//  Created by 장동완 on 2/4/26.
//

import Foundation

public protocol BleConfig {

    // 찾고자 하는 서비스 UUID
    var serviceUuid: String { get }

    // Notify 기능 활성화 여부
    var enableNotificationOnConnect: Bool { get }

    // 값을 받을(Notify) 특성 UUID
    var notifyCharUuid: String? { get }

    // 스캔을 몇 초 동안 할지 (초 단위)
    var scanTimeoutSeconds: TimeInterval { get }

    // 로그를 킬지 말지 (디버깅용)
    var isDebugMode: Bool { get }

    // 자동 연결 여부
    var shouldAutoConnect: Bool { get }

    // 연결 타임아웃 시간 (초 단위)
    var connectionTimeoutSeconds: TimeInterval { get }

    // Service Discovery 전 딜레이 (초 단위)
    var discoveryDelaySeconds: TimeInterval { get }
}

extension BleConfig {
    // 기본값 제공
    var connectionTimeoutSeconds: TimeInterval { 10.0 }  // 기본 10초
    var discoveryDelaySeconds: TimeInterval { 0.5 }  // 기본 0.5초
}
