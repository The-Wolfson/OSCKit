//
//  OSCTCPServer ClientConnection.swift
//  OSCKit • https://github.com/orchetect/OSCKit
//  © 2020-2026 Steffan Andrews • Licensed under MIT License
//

#if !os(watchOS)

import Foundation
import OSCKitCore
import Network

extension OSCTCPServer {
    /// Internal class encapsulating a remote client connection session accepted by a local ``OSCTCPServer``.
    final class ClientConnection {
        let tcpConnection: NWConnection
        let remoteHost: String // cached, since NWConnection resets it upon disconnection
        let remotePort: UInt16 // cached, since NWConnection resets it upon disconnection
        let clientId: OSCTCPClientSessionID
        let framingMode: OSCTCPFramingMode
        let queue: DispatchQueue
        weak var tcpServer: OSCTCPServer?
        
        init(
            networkConnection: NWConnection,
            clientId: OSCTCPClientSessionID,
            framingMode: OSCTCPFramingMode,
            queue: DispatchQueue,
            server: OSCTCPServer?
        ) {
            self.tcpConnection = networkConnection
            self.clientId = clientId
            
            switch networkConnection.endpoint {
                case .hostPort(let host, let port):
                    self.remoteHost = host.debugDescription
                    self.remotePort = port.rawValue
                default:
                    self.remoteHost = ""
                    self.remotePort = 0
            }
            
            self.framingMode = framingMode
            self.queue = queue
            self.tcpServer = server
                        
            networkConnection.stateUpdateHandler = { state in
                switch state {
                case .cancelled:
                    server?.disconnectClient(clientID: clientId)
                    self._generateDisconnectedNotification(error: nil)
                case .failed(let error):
                    server?.disconnectClient(clientID: clientId)
                    self._generateDisconnectedNotification(error: error)
                default: return
                }
            }
            
            networkConnection.start(queue: queue)
            
            _startReceiving(on: networkConnection)
        }
        
        deinit {
            close()
        }
    }
}

extension OSCTCPServer.ClientConnection: @unchecked Sendable { } // TODO: unchecked

// MARK: - Lifecycle

extension OSCTCPServer.ClientConnection {
    func close() {
        tcpConnection.cancel()
        tcpServer = nil
    }
}

// MARK: - Communication

extension OSCTCPServer.ClientConnection: _OSCTCPSendProtocol {
    var _tcpConnection: NWConnection? { tcpConnection }
    
    func send(_ oscPacket: OSCPacket) throws {
        try _send(oscPacket)
    }
    
    func send(_ oscBundle: OSCBundle) throws {
        try _send(oscBundle)
    }
    
    func send(_ oscMessage: OSCMessage) throws {
        try _send(oscMessage)
    }
    
    //Network does not register remote changes to state with the local NWConnection, so a rolling check of data is needed to see if the connection is terminated.
    func _startReceiving(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, context, isComplete, error in
            if isComplete {
                self.close()
            } else {
                if let data, !data.isEmpty {
                    self.tcpServer?._handle(receivedData: data, remoteHost: self.remoteHost, remotePort: self.remotePort)
                }
                self._startReceiving(on: connection)
            }
        }
    }
}

extension OSCTCPServer.ClientConnection: _OSCTCPHandlerProtocol {
    var timeTagMode: OSCTimeTagMode {
        tcpServer?.timeTagMode ?? .ignore
    }
    
    var receiveHandler: OSCHandlerBlock? {
        tcpServer?.receiveHandler
    }
}

extension OSCTCPServer.ClientConnection: _OSCTCPGeneratesClientNotificationsProtocol {
    // note that this is never called because when a remote connection closes, its socket does not fire
    // `socketDidDisconnect(...)` in GCDAsyncSocketDelegate, but we have to implement this due to
    // other protocol requirements
    func _generateConnectedNotification() {
        tcpServer?._generateConnectedNotification(
            remoteHost: remoteHost,
            remotePort: remotePort,
            clientID: clientId
        )
    }
    
    // note that this is never called because when a remote connection closes, its socket does not fire
    // `socketDidDisconnect(...)` in GCDAsyncSocketDelegate, but we have to implement this due to
    // other protocol requirements
    func _generateDisconnectedNotification(error: NWError?) {
        tcpServer?._generateDisconnectedNotification(
            remoteHost: remoteHost,
            remotePort: remotePort,
            clientID: clientId,
            error: error
        )
    }
}

#endif
