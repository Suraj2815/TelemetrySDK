//
//  URLSession+Swizzling.swift
//  TelemetrySDK
//
//  Created by Suraj Gupta on 14/04/26.
//

import Foundation

extension URLSession {
    
    static func enableSwizzling() {
        _ = swizzle
    }
    
    private static let swizzle: Void = {
        
        let original = class_getInstanceMethod(URLSession.self, #selector(URLSession.swizzled_dataTask(with:completionHandler:)))
        let swizzled = class_getInstanceMethod(URLSession.self, #selector(swizzled_dataTask(with:completionHandler:)))
        
        if let original = original, let swizzled = swizzled {
            method_exchangeImplementations(original, swizzled)
        }
    }()
    
    @objc private func swizzled_dataTask(with request: URLRequest,
                                         completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        
        let start = Date()
        
        return swizzled_dataTask(with: request) { data, response, error in
            
            let duration = Date().timeIntervalSince(start) * 1000
            let success = error == nil
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            
            TelemetryManager.shared.trackDependency(
                name: request.url?.lastPathComponent ?? "API",
                url: request.url?.absoluteString ?? "",
                duration: duration,
                type: "HTTP",
                success: success,
                responseCode: "\(code)"
            )
            
            completionHandler(data, response, error)
        }
    }
}
