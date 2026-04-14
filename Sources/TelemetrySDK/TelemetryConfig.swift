//
//  TelemetryConfig.swift
//  TelemetrySDK
//
//  Created by Suraj Gupta on 14/04/26.
//


import Foundation

public final class TelemetryConfig {
    
    public static var instrumentationKey: String = ""
    public static var endpoint: String = ""
    
    // Sampling (reduce Azure cost)
    public static var samplingRate: Double = 1.0
    
    public static func configure(key: String, endpoint: String) {
        self.instrumentationKey = key
        self.endpoint = endpoint
    }
}
