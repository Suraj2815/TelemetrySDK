import XCTest
@testable import TelemetrySDK

final class TelemetrySDKTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        
        TelemetryConfig.configure(
            key: "test-key",
            endpoint: "https://test.com/v2/track"
        )
        
        TelemetryManager.shared.clearQueue()
    }
    
    // ✅ Test config setup
    func testConfigSetup() {
        XCTAssertEqual(TelemetryConfig.instrumentationKey, "test-key")
        XCTAssertEqual(TelemetryConfig.endpoint, "https://test.com/v2/track")
    }
    
    // ✅ Test user set
    func testSetUser() {
        TelemetryManager.shared.setUser(id: "test-user")
        
        // indirectly verify via log
        TelemetryManager.shared.trackTrace("Test", severity: 1)
        
        XCTAssertEqual(TelemetryManager.shared.getQueueCount(), 1)
    }
    
    // ✅ Test trace logging
    func testTrackTraceAddsToQueue() {
        TelemetryManager.shared.trackTrace("Hello Test")
        
        XCTAssertEqual(TelemetryManager.shared.getQueueCount(), 1)
    }
    
    // ✅ Test error logging
    func testTrackErrorAddsToQueue() {
        TelemetryManager.shared.trackError(message: "Error Test")
        
        XCTAssertEqual(TelemetryManager.shared.getQueueCount(), 1)
    }
    
    // ✅ Test exception logging
    func testTrackExceptionAddsToQueue() {
        TelemetryManager.shared.trackException(message: "Crash Test")
        
        XCTAssertEqual(TelemetryManager.shared.getQueueCount(), 1)
    }
}
