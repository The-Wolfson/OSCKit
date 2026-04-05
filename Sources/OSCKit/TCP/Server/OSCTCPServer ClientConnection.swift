//
//  OSCTCPServer ClientConnection.swift
//  OSCKit • https://github.com/orchetect/OSCKit
//  © 2020-2026 Steffan Andrews • Licensed under MIT License
//

import Foundation
import Network
import OSCKitCore

extension OSCTCPServer {
    /// Internal class encapsulating a remote client connection session accepted by a local ``OSCTCPServer``.
    final class ClientConnection {
        private let nwConnection: NWConnection
        let remoteHost: String // cached, since NWConnection resets its endpoint upon disconnection
        let remotePort: UInt16 // cached, since NWConnection resets its endpoint upon disconnection
        let clientID: OSCTCPClientSessionID
        let framingMode: OSCTCPFramingMode
        let queue: DispatchQueue
        weak var server: OSCTCPServer?
        
        init(
            nwConnection: NWConnection,
            clientID: OSCTCPClientSessionID,
            remoteHost: String,
            remotePort: UInt16,
            framingMode: OSCTCPFramingMode,
            queue: DispatchQueue,
            server: OSCTCPServer?
        ) {
            self.nwConnection = nwConnection
            self.clientID = clientID
            self.remoteHost = remoteHost
            self.remotePort = remotePort
            self.framingMode = framingMode
            self.queue = queue
            self.server = server
            
            nwConnection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .failed(let error):
                    self._handleDisconnect(error: error)
                case .cancelled:
                    self._handleDisconnect(error: nil)
                default:
                    break
                }
            }
        }
        
        deinit {
            close()
        }
    }
}

extension OSCTCPServer.ClientConnection: @unchecked Sendable { }

// MARK: - Lifecycle

extension OSCTCPServer.ClientConnection {
    func startReceiving() {
        _receiveNext()
    }
    
    func close() {
        nwConnection.cancel()
    }
    
    private func _receiveNext() {
        nwConnection.receive(minimumIncompleteLength: 1, maximumLength: 65535) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            
            if let data, !data.isEmpty {
                self._handle(receivedData: data, remoteHost: self.remoteHost, remotePort: self.remotePort)
            }
            
            if error == nil && !isComplete {
                self._receiveNext()
            } else if let nwError = error as? NWError {
                self._handleDisconnect(error: nwError)
            } else if error != nil || isComplete {
                self._handleDisconnect(error: nil)
            }
        }
    }
    
    private func _handleDisconnect(error: NWError?) {
        guard let server else { return }
        server._removeClient(clientID: clientID)
        server._generateDisconnectedNotification(
            remoteHost: remoteHost,
            remotePort: remotePort,
            clientID: clientID,
            error: error
        )
        self.server = nil
    }
}

// MARK: - Communication

extension OSCTCPServer.ClientConnection: _OSCTCPSendProtocol {
    var _tcpSendConnection: NWConnection? { nwConnection }
    
    func send(_ oscPacket: OSCPacket) throws {
        try _send(oscPacket)
    }
    
    func send(_ oscBundle: OSCBundle) throws {
        try _send(oscBundle)
    }
    
    func send(_ oscMessage: OSCMessage) throws {
        try _send(oscMessage)
    }
}

extension OSCTCPServer.ClientConnection: _OSCTCPHandlerProtocol {
    var timeTagMode: OSCTimeTagMode {
        server?.timeTagMode ?? .ignore
    }
    
    var receiveHandler: OSCHandlerBlock? {
        server?.receiveHandler
    }
}
