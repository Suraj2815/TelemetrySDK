//
//  URLSession+Swizzling.swift
//  TelemetrySDK
//
//  Created by Suraj Gupta on 14/04/26.
//

import Foundation
import UIKit
import Network

@objcMembers
public final class TelemetryManager: NSObject {
    
    public static let shared = TelemetryManager()
    
    private var instrumentationKey: String {
        TelemetryConfig.instrumentationKey
    }
    
    private var endpoint: String {
        TelemetryConfig.endpoint
    }
    
    private let maxBatchSize = 25
    private let maxQueueSize = 1000
    private let flushInterval: TimeInterval = 15
    
    private var queue: [[String: Any]] = []
    private let serialQueue = DispatchQueue(label: "telemetry.serial.queue")
    private let queueFileName = "telemetry_queue.json"
    
    private let monitor = NWPathMonitor()
    private var isConnected = false
    
    private var sessionId = UUID().uuidString
    private var userId = "unknown"
    
    private var timer: Timer?
    
    private override init() {
        super.init()
        loadQueueFromDisk()
        startNetworkMonitor()
        startFlushTimer()
        setupCrashHandler()
        URLSession.enableSwizzling() // 🔥 auto API tracking
        flush()
    }
    // MARK: - Testing Helpers
    #if DEBUG
    func getQueueCount() -> Int {
        return queue.count
    }

    func clearQueue() {
        queue.removeAll()
    }
    #endif
    
    // MARK: - Sampling
    private func shouldSend(isCritical: Bool = false) -> Bool {
        if isCritical { return true }
        return Double.random(in: 0...1) <= TelemetryConfig.samplingRate
    }
    
    // MARK: - Public API
    @objc public func setUser(id: String) {
        userId = id
    }
    
    @objc public func trackTrace(_ message: String, severity: Int = 1) {
        enqueue(baseEnvelope(baseType: "MessageData", baseData: [
            "message": message,
            "severityLevel": severity,
            "properties": enrich([:])
        ]))
    }
    
    @objc public func trackError(message: String) {
        trackTrace(message, severity: 3)
    }
    
    @objc public func trackException(message: String, stack: String? = nil) {
        
        let exception: [String: Any] = [
            "typeName": "iOSException",
            "message": message,
            "hasFullStack": true,
            "stack": stack ?? Thread.callStackSymbols.joined(separator: "\n")
        ]
        
        let crashGroup = String(message.prefix(50))
        
        enqueue(baseEnvelope(baseType: "ExceptionData", baseData: [
            "exceptions": [exception],
            "severityLevel": 3,
            "properties": enrich([
                "crashGroup": crashGroup
            ])
        ]), isCritical: true)
    }
    
    @objc public func trackDependency(name: String, url: String, duration: Double, type: String, success: Bool, responseCode: String) {
        enqueue(baseEnvelope(baseType: "RemoteDependencyData", baseData: [
            "name": name,
            "data": url,
            "target": url,
            "duration": formatDuration(duration),
            "resultCode": responseCode,
            "success": success,
            "type": type,
            "properties": enrich([:])
        ]))
    }
    
    public func startAPITimer() -> Date {
        Date()
    }
    
    public func stopAPITimer(name: String, startTime: Date, success: Bool) {
        let duration = Date().timeIntervalSince(startTime) * 1000
        
        enqueue(baseEnvelope(baseType: "MetricData", baseData: [
            "metrics": [
                ["name": name, "value": duration]
            ],
            "properties": enrich(["success": "\(success)"])
        ]))
    }
    
    @objc public func flush() {
        serialQueue.async {
            guard !self.queue.isEmpty else { return }
            
            let batch = Array(self.queue.prefix(self.maxBatchSize))
            self.queue.removeFirst(batch.count)
            self.saveQueueToDisk()
            
            self.sendBatch(batch)
        }
    }
    
    // MARK: - Queue
    private func enqueue(_ item: [String: Any], isCritical: Bool = false) {
        
        guard shouldSend(isCritical: isCritical) else { return }
        
        serialQueue.async {
            self.queue.append(item)
            
            if self.queue.count > self.maxQueueSize {
                self.queue.removeFirst(self.queue.count - self.maxQueueSize)
            }
            
            self.saveQueueToDisk()
            
            if self.queue.count >= self.maxBatchSize {
                self.flush()
            }
        }
    }
    
    // MARK: - Network
    private func sendBatch(_ batch: [[String: Any]]) {
        
        guard isConnected else { return }
        guard let url = URL(string: endpoint) else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: batch) else {
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let task = URLSession.shared.uploadTask(with: request, from: data) { data, response, error in
            
            if let error = error {
                print("❌ Telemetry upload failed:", error.localizedDescription)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Status Code:", httpResponse.statusCode)
                
                if (200...299).contains(httpResponse.statusCode) {
                    print("✅ Telemetry upload success")
                } else {
                    print("❌ Server error:", httpResponse.statusCode)
                }
            }
            
            if let data = data,
               let responseString = String(data: data, encoding: .utf8) {
                print("📥 Response:", responseString)
            }
        }
        
        task.resume()
    }
    
    // MARK: - Timer
    private func startFlushTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { _ in
            self.flush()
        }
    }
    
    // MARK: - Network Monitor
    private func startNetworkMonitor() {
        monitor.pathUpdateHandler = { path in
            self.isConnected = path.status == .satisfied
            if self.isConnected { self.flush() }
        }
        monitor.start(queue: DispatchQueue.global())
    }
    
    // MARK: - Crash Handler

    private func setupCrashHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let crashMessage = """
                CRASH:
                Name: \(exception.name.rawValue)
                Reason: \(exception.reason ?? "")
                Stack: \(exception.callStackSymbols.joined(separator: "\n"))
    """
            TelemetryManager.shared.trackException(message: crashMessage)
            TelemetryManager.shared.saveQueueToDisk() // saving immediately
        }
        let signals: [Int32] = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGPIPE]
        for sig in signals {
            signal(sig) { signal in
                let stack = Thread.callStackSymbols.joined(separator: "\n")
                TelemetryManager.shared.trackException(
                    message: "Signal crash: \(signal)",
                    stack: stack
                )
                TelemetryManager.shared.saveQueueToDisk()
                exit(signal) // terminate app safely
            }
        }
    }
    // MARK: - Helpers
    private func formatDuration(_ ms: Double) -> String {
        let seconds = Int(ms / 1000)
        let millis = Int(ms.truncatingRemainder(dividingBy: 1000))
        return String(format: "00:00:%02d.%03d", seconds, millis)
    }
    
    private func baseEnvelope(baseType: String, baseData: [String: Any]) -> [String: Any] {
        return [
            "name": "Microsoft.ApplicationInsights.\(baseType)",
            "time": ISO8601DateFormatter().string(from: Date()),
            "iKey": instrumentationKey,
            "tags": contextTags(),
            "data": [
                "baseType": baseType,
                "baseData": baseData
            ]
        ]
    }
    
    private func contextTags() -> [String: String] {
        let device = UIDevice.current
        
        return [
            "ai.session.id": sessionId,
            "ai.user.id": userId,
            "ai.device.os": device.systemName,
            "ai.device.osVersion": device.systemVersion,
            "ai.device.model": device.model
        ]
    }
    
    private func enrich(_ props: [String: String]) -> [String: String] {
        var properties = props
        properties["sessionId"] = sessionId
        properties["userId"] = userId
        return properties
    }
    
    private var queueFileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(queueFileName)
    }
    
    private func saveQueueToDisk() {
        guard let url = queueFileURL,
              let data = try? JSONSerialization.data(withJSONObject: queue) else { return }
        try? data.write(to: url)
    }
    
    private func loadQueueFromDisk() {
        guard let url = queueFileURL else { return }
        if let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            queue = json
        }
    }
}
