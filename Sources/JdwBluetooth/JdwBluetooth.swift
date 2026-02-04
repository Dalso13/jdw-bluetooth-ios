// The Swift Programming Language
// https://docs.swift.org/swift-book

public struct JdwBluetooth {
    
    public init() {}
    

    /**
     * BleClient 인스턴스를 생성하는 유일한 진입점
     */
    public func createClient(
        config: BleConfig,
    ) -> BleClient {
        return DefaultBleClient(config: config)
    }
}
