//
//  File.swift
//  OSCKit
//
//  Created by Joshua Wolfson on 5/4/2026.
//

import CocoaAsyncSocket
import Foundation

public enum OSCNetworkError: Error {
    case other(_ details: String)
    case clientNotFound(id: OSCTCPClientSessionID)
    case noRemoteHost //OSC TCP client socket is not connected to a remote host.
}
