# JdwBluetooth

iOS용 CoreBluetooth 기반 BLE(Bluetooth Low Energy) 통신 라이브러리

## 특징

- ✅ **Modern Swift Concurrency** - async/await 기반 API
- ✅ **Reactive State Management** - Combine Publisher로 상태 관리
- ✅ **Thread-Safe** - 백그라운드 Serial Queue + Actor 활용
- ✅ **자동 Notification 구독** - Config 기반 자동 활성화
- ✅ **자동 재연결** - 연결 끊김 시 자동 재연결 지원
- ✅ **순차 실행 보장** - BleCommandQueue로 동시 요청 처리

## 요구사항

- iOS 13.0+ / macOS 10.15+
- Swift 5.9+
- Xcode 15.0+

## 설치

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Dalso13/jdw-bluetooth-ios.git", from: "0.0.4")
]
```

## 사용법

### 1. Config 설정

```swift
import JdwBluetooth

struct MyBleConfig: BleConfig {
    var serviceUuid: String = "0000180D-0000-1000-8000-00805F9B34FB"
    var enableNotificationOnConnect: Bool = true
    var notifyCharUuid: String? = "00002A37-0000-1000-8000-00805F9B34FB"
    var scanTimeoutSeconds: TimeInterval = 10.0
    var isDebugMode: Bool = true
    var shouldAutoConnect: Bool = true
    var connectionTimeoutSeconds: TimeInterval = 10.0
    var discoveryDelaySeconds: TimeInterval = 0.5
}
```

### 2. Client 생성

```swift
let config = MyBleConfig()
let bleClient = JdwBluetooth().createClient(config: config)
```

### 3. 스캔 상태 구독

```swift
import Combine

var cancellables = Set<AnyCancellable>()

bleClient.scanStatePublisher
    .receive(on: DispatchQueue.main)
    .sink { state in
        switch state {
        case .idle:
            print("스캔 대기 중")
        case .scanning(let peripherals):
            print("스캔 중... 발견된 기기: \(peripherals.count)개")
        }
    }
    .store(in: &cancellables)
```

### 4. 연결 상태 구독

```swift
bleClient.connectionStatePublisher
    .receive(on: DispatchQueue.main)
    .sink { state in
        switch state {
        case .disconnected:
            print("연결 끊김")
        case .connecting:
            print("연결 중...")
        case .discovering:
            print("서비스 탐색 중...")
        case .ready:
            print("연결 완료! 사용 가능")
        case .disconnecting:
            print("연결 해제 중...")
        case .error(let type, let message):
            print("에러: \(type) - \(message)")
        }
    }
    .store(in: &cancellables)
```

### 5. Notification 데이터 수신

```swift
bleClient.notifyPublisher
    .receive(on: DispatchQueue.main)
    .sink { (characteristicUuid, data) in
        print("Notification 수신: \(characteristicUuid)")
        print("데이터: \(data.map { String(format: "%02x", $0) }.joined())")
    }
    .store(in: &cancellables)
```

### 6. 스캔 시작/중지

```swift
// 스캔 시작
bleClient.startScan()

// 스캔 중지
bleClient.stopScan()
```

### 7. 디바이스 연결

```swift
Task {
    do {
        // peripheralId는 scanStatePublisher에서 얻은 UUID
        try await bleClient.connect(peripheralId: deviceUUID)
        print("연결 성공!")
    } catch {
        print("연결 실패: \(error)")
    }
}
```

### 8. 데이터 쓰기

```swift
Task {
    do {
        let data = Data([0x01, 0x02, 0x03])
        
        // 응답 대기 (안전)
        try await bleClient.writeCharacteristic(
            serviceUuid: "180D",
            characteristicUuid: "2A39",
            value: data,
            writeType: .withResponse
        )
        
        // 응답 무시 (빠름)
        try await bleClient.writeCharacteristic(
            serviceUuid: "180D",
            characteristicUuid: "2A39",
            value: data,
            writeType: .withoutResponse
        )
        
        print("쓰기 완료!")
    } catch {
        print("쓰기 실패: \(error)")
    }
}
```

### 9. 데이터 읽기

```swift
Task {
    do {
        let data = try await bleClient.readCharacteristic(
            serviceUuid: "180D",
            characteristicUuid: "2A39"
        )
        print("읽기 완료: \(data)")
    } catch {
        print("읽기 실패: \(error)")
    }
}
```

### 10. 연결 해제

```swift
Task {
    await bleClient.disconnect()
    print("연결 해제 완료")
}
```

## 전체 예제

```swift
import JdwBluetooth
import Combine

class BluetoothManager: ObservableObject {
    private let bleClient: BleClient
    private var cancellables = Set<AnyCancellable>()
    
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var discoveredDevices: [UUID] = []
    
    init() {
        let config = MyBleConfig()
        self.bleClient = JdwBluetooth().createClient(config: config)
        
        setupSubscriptions()
    }
    
    private func setupSubscriptions() {
        // 스캔 상태
        bleClient.scanStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .idle:
                    self?.isScanning = false
                case .scanning(let peripherals):
                    self?.isScanning = true
                    self?.discoveredDevices = Array(peripherals.keys)
                }
            }
            .store(in: &cancellables)
        
        // 연결 상태
        bleClient.connectionStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.isConnected = (state == .ready)
            }
            .store(in: &cancellables)
        
        // Notification 수신
        bleClient.notifyPublisher
            .receive(on: DispatchQueue.main)
            .sink { (uuid, data) in
                print("수신: \(data)")
            }
            .store(in: &cancellables)
    }
    
    func startScanning() {
        bleClient.startScan()
    }
    
    func connect(to deviceId: UUID) async throws {
        try await bleClient.connect(peripheralId: deviceId)
    }
    
    func sendData(_ data: Data) async throws {
        try await bleClient.writeCharacteristic(
            serviceUuid: "180D",
            characteristicUuid: "2A39",
            value: data,
            writeType: .withResponse
        )
    }
}
```

## 에러 처리

```swift
do {
    try await bleClient.connect(peripheralId: deviceId)
} catch BleError.timeout {
    print("연결 타임아웃")
} catch BleError.peripheralNotFound {
    print("디바이스를 찾을 수 없음")
} catch BleError.bluetoothDisabled {
    print("블루투스가 꺼져있음")
} catch BleError.characteristicNotFound {
    print("Characteristic을 찾을 수 없음")
} catch {
    print("알 수 없는 에러: \(error)")
}
```

## 주요 에러 타입

| 에러 | 설명 |
|------|------|
| `.timeout` | 연결 시간 초과 |
| `.gattError` | GATT 내부 에러 (133번 에러 등) |
| `.permissionDenied` | 블루투스 권한 없음 |
| `.disconnectedByDevice` | 상대 디바이스가 연결 해제 |
| `.bluetoothDisabled` | 블루투스가 꺼져있음 |
| `.peripheralNotFound` | Peripheral을 찾을 수 없음 |
| `.notConnected` | 연결되지 않은 상태 |
| `.characteristicNotFound` | Characteristic을 찾을 수 없음 |
| `.busy` | 이미 다른 작업 수행 중 |

## 고급 기능

### 자동 재연결

```swift
struct MyBleConfig: BleConfig {
    var shouldAutoConnect: Bool = true  // ✅ 자동 재연결 활성화
    // ...
}
```

연결이 끊기면 2초 후 자동으로 재연결을 시도합니다.

### 자동 Notification 활성화

```swift
struct MyBleConfig: BleConfig {
    var enableNotificationOnConnect: Bool = true
    var notifyCharUuid: String? = "00002A37-0000-1000-8000-00805F9B34FB"
    // ...
}
```

연결 성공 시 지정된 Characteristic의 Notification이 자동으로 활성화됩니다.

### Connection Timeout 설정

```swift
struct MyBleConfig: BleConfig {
    var connectionTimeoutSeconds: TimeInterval = 15.0  // 15초로 변경
    // ...
}
```

## 아키텍처

```
┌─────────────────────────────────────┐
│         사용자 코드 (App)            │
└─────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────┐
│      BleClient (Protocol)           │  ← Public API
└─────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────┐
│       DefaultBleClient              │
│  ┌─────────────┬─────────────────┐  │
│  │ BleScanner  │ BleGattManager  │  │  ← Internal
│  └─────────────┴─────────────────┘  │
└─────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────┐
│   CBCentralManager (CoreBluetooth)  │
└─────────────────────────────────────┘
```

## Thread Safety

- 모든 BLE 작업은 단일 Serial `DispatchQueue`에서 실행
- `BleCommandQueue` (Actor)로 순차 실행 보장
- Combine Publisher는 thread-safe
- UI 업데이트는 `.receive(on: DispatchQueue.main)` 필수

## License

MIT License

## Author

장동완
