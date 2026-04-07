//
//  File.swift
//  OSCKit
//
//  Created by Joshua Wolfson on 5/4/2026.
//

import Network
import Foundation

public enum OSCNetworkError: LocalizedError {
    case other(_ details: String)
    case clientNotFound(id: OSCTCPClientSessionID)
    ///OSC socket is not connected to a remote host.
    case noRemoteHost
    ///OSC socket has not been started yet.
    case notStarted
}
