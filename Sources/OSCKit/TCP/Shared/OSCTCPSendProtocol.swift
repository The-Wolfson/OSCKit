//
//  OSCTCPSendProtocol.swift
//  OSCKit • https://github.com/orchetect/OSCKit
//  © 2020-2026 Steffan Andrews • Licensed under MIT License
//

import Foundation
import Network
import OSCKitCore

/// Internal protocol that TCP-based OSC classes adopt in order to send OSC packets.
protocol _OSCTCPSendProtocol: AnyObject where Self: Sendable {
    var _tcpSendConnection: NWConnection? { get }
    var framingMode: OSCTCPFramingMode { get }
}

extension _OSCTCPSendProtocol {
    /// Send an OSC packet.
    func _send(_ oscPacket: OSCPacket) throws {
        try _send(oscPacket.rawData())
    }
    
    /// Send an OSC bundle.
    func _send(_ oscBundle: OSCBundle) throws {
        try _send(oscBundle.rawData())
    }
    
    /// Send an OSC message.
    func _send(_ oscMessage: OSCMessage) throws {
        try _send(oscMessage.rawData())
    }
    
    /// Send raw OSC bytes, applying TCP framing.
    private func _send(_ oscData: Data) {
        guard let connection = _tcpSendConnection else { return }
        
        // frame data
        let data: Data = switch framingMode {
        case .osc1_0:
            // OSC packet framed using a packet-length header
            // 4-byte int for size
            oscData.packetLengthHeaderEncoded(endianness: .bigEndian)
            
        case .osc1_1:
            // OSC packet framed using SLIP (double END) protocol: http://www.rfc-editor.org/rfc/rfc1055.txt
            oscData.slipEncoded()
            
        case .none:
            // no framing, send OSC bytes as-is
            oscData
        }
        
        // send packet
        connection.send(content: data, completion: .idempotent)
    }
}
