//
//  File.swift
//  OSCKit
//
//  Created by Joshua Wolfson on 5/4/2026.
//

import CocoaAsyncSocket
import Foundation

public enum NetworkError: Error {
    case badConfig
    case badParam
    case connectTimeout
    case readTimeout
    case writeTimeout
    case readMaxedOut
    case closed
    case other

    ///Returns `NetworkError` from `GCDAsyncSocketError`
    init(_ error: GCDAsyncSocketError?) {
        switch error?.code {
        case .badConfigError:
            self = .badConfig
        case .badParamError:
            self = .badParam
        case .connectTimeoutError:
            self = .connectTimeout
        case .readTimeoutError:
            self = .readTimeout
        case .writeTimeoutError:
            self = .writeTimeout
        case .readMaxedOutError:
            self = .readMaxedOut
        case .closedError:
            self = .closed
        default:
            self = .other
        }
    }
}
