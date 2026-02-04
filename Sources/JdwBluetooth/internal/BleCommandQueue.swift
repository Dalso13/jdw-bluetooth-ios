//
//  BleCommandQueue.swift
//  JdwBluetooth
//
//  Created by 장동완 on 2/4/26.
//

import Foundation

/// 블루투스 명령 순차 실행을 보장하는 Queue
/// Swift Actor를 사용하여 thread-safe하게 구현
@available(macOS 10.15, iOS 13.0, *)
actor BleCommandQueue {
    private var commandCount = 0
    
    /// 명령을 큐에 추가하고 순차적으로 실행
    /// - Parameter action: 실행할 비동기 클로저 (Sendable 타입 반환)
    func enqueue<T: Sendable>(_ action: @Sendable () async throws -> T) async throws -> T {
        commandCount += 1
        let currentCommand = commandCount
        
        print("[Queue] Command #\(currentCommand) enqueued (waiting...)")
        
        do {
            print("[Queue] Command #\(currentCommand) executing")
            let result = try await action()
            print("[Queue] Command #\(currentCommand) completed successfully")
            return result
        } catch {
            print("[Queue] Command #\(currentCommand) failed: \(error.localizedDescription)")
            throw error
        }
    }
}
