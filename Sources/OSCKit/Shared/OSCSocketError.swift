//
//  OSCSocketError.swift
//  OSCKit • https://github.com/orchetect/OSCKit
//  © 2020-2026 Steffan Andrews • Licensed under MIT License
//

import Foundation

/// Error cases thrown by OSCKit socket operations.
public enum OSCSocketError: LocalizedError, Equatable, Hashable, Sendable {
    /// The socket or server has not been started yet.
    case notStarted
    
    /// No remote host was specified for sending.
    case noRemoteHost
    
    /// The TCP client with the given session ID was not found (not connected).
    case clientNotFound(id: Int)
    
    public var errorDescription: String? {
        switch self {
        case .notStarted:
            "OSC socket has not been started yet."
        case .noRemoteHost:
            "Remote host is not specified in the remoteHost property or in the host parameter of send()."
        case .clientNotFound(let id):
            "OSC TCP client socket with ID \(id) not found (not connected)."
        }
    }
}
