//
//  OSCTCPServer.swift
//  OSCKit • https://github.com/orchetect/OSCKit
//  © 2020-2026 Steffan Andrews • Licensed under MIT License
//

import Foundation
import Network
import OSCKitCore

/// Listens on a local port for TCP connections in order to send and receive OSC packets over the network.
///
/// Use this class when you are taking the role of the host and one or more remote clients will want to connect via
/// bidirectional TCP connection.
///
/// A TCP connection is also generally more reliable than using the UDP protocol.
///
/// Since TCP is inherently a bidirectional network connection, both ``OSCTCPClient`` and ``OSCTCPServer`` can send and
/// receive once a connection is made. Messages sent by the server are only received by the client, and vice-versa.
///
/// What differentiates this server class from the client class is that the server is designed to listen for inbound
/// connections. (Whereas, the client class is designed to connect to a remote TCP server.)
public final class OSCTCPServer {
    private var tcpListener: NWListener?
    private var _clients: [OSCTCPClientSessionID: ClientConnection] = [:]
    private let clientsLock = NSLock()
    let queue: DispatchQueue
    var receiveHandler: OSCHandlerBlock?
    var notificationHandler: NotificationHandlerBlock?
    
    /// Notification handler closure.
    public typealias NotificationHandlerBlock = @Sendable (_ notification: Notification) -> Void
    
    /// Time tag mode. Determines how OSC bundle time tags are handled.
    public var timeTagMode: OSCTimeTagMode
    
    /// Local network port.
    public var localPort: UInt16 {
        tcpListener?.port?.rawValue ?? _localPort ?? 0
    }

    private var _localPort: UInt16?
    
    /// Network interface to restrict connections to.
    public let interface: String?
    
    /// Returns a boolean indicating whether the OSC server has been started.
    public private(set) var isStarted: Bool = false
    
    /// TCP packet framing mode.
    public let framingMode: OSCTCPFramingMode

    /// Initialize with a remote hostname and UDP port.
    ///
    /// > Note:
    /// >
    /// > Call ``start()`` to begin listening for connections.
    /// > The connections may be closed at any time by calling ``stop()`` and then restarted again as needed.
    ///
    /// - Parameters:
    ///   - port: Local network port to listen for inbound connections.
    ///     If `nil` or `0`, a random available port in the system will be chosen.
    ///   - interface: Optionally specify a network interface for which to constrain connections.
    ///   - timeTagMode: OSC TimeTag mode. Default is recommended.
    ///   - framingMode: TCP framing mode. Both server and client must use the same framing mode. (Default is recommended.)
    ///   - queue: Optionally supply a custom dispatch queue for receiving OSC packets and dispatching the
    ///     handler callback closure. If `nil`, a dedicated internal background queue will be used.
    ///   - receiveHandler: Handler to call when OSC bundles or messages are received.
    public init(
        port: UInt16?,
        interface: String? = nil,
        timeTagMode: OSCTimeTagMode = .ignore,
        framingMode: OSCTCPFramingMode = .osc1_1,
        queue: DispatchQueue? = nil,
        receiveHandler: OSCHandlerBlock? = nil
    ) {
        _localPort = (port == nil || port == 0) ? nil : port
        self.interface = interface
        self.timeTagMode = timeTagMode
        self.framingMode = framingMode
        let queue = queue ?? DispatchQueue(label: "com.orchetect.OSCKit.OSCTCPServer.queue")
        self.queue = queue
        self.receiveHandler = receiveHandler
    }
    
    deinit {
        stop()
    }
}

extension OSCTCPServer: @unchecked Sendable { }

// MARK: - Lifecycle

extension OSCTCPServer {
    /// Starts listening for inbound connections.
    public func start() throws {
        guard !isStarted else { return }
        
        let port: NWEndpoint.Port = _localPort.flatMap { NWEndpoint.Port(rawValue: $0) } ?? .any
        let listener = try NWListener(using: .tcp, on: port)
        
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self._acceptNewConnection(connection)
        }
        
        self.tcpListener = listener
        listener.start(queue: queue)
        
        isStarted = true
    }
    
    /// Closes any open client connections and stops listening for inbound connection requests.
    public func stop() {
        _closeAllClients()
        
        tcpListener?.cancel()
        tcpListener = nil
        
        isStarted = false
    }
    
    private func _acceptNewConnection(_ connection: NWConnection) {
        let clientID = _newClientID()
        let (remoteHost, remotePort) = Self._remoteHostPort(from: connection)
        
        let clientConn = ClientConnection(
            nwConnection: connection,
            clientID: clientID,
            remoteHost: remoteHost,
            remotePort: remotePort,
            framingMode: framingMode,
            queue: queue,
            server: self
        )
        
        clientsLock.withLock {
            _clients[clientID] = clientConn
        }
        
        connection.start(queue: queue)
        clientConn.startReceiving()
        
        _generateConnectedNotification(remoteHost: remoteHost, remotePort: remotePort, clientID: clientID)
    }
    
    /// Removes a client connection from the internal dictionary without closing its socket.
    /// This is called from the client's own disconnect handler after the connection has already
    /// been terminated by the Network framework.
    func _removeClient(clientID: OSCTCPClientSessionID) {
        clientsLock.withLock {
            _clients[clientID] = nil
        }
    }
    
    private func _closeAllClients() {
        let allClients = clientsLock.withLock { Array(_clients.values) }
        for client in allClients {
            client.close()
        }
        clientsLock.withLock {
            _clients.removeAll()
        }
    }
    
    /// Extract a host string and port from an NWConnection's remote endpoint.
    static func _remoteHostPort(from connection: NWConnection) -> (host: String, port: UInt16) {
        if case .hostPort(let host, let port) = connection.endpoint {
            return (String(describing: host), port.rawValue)
        }
        return ("", 0)
    }
    
    private func _newClientID() -> OSCTCPClientSessionID {
        let currentIDs = clientsLock.withLock { Set(_clients.keys) }
        var clientID: Int = 0
        while clientID == 0 || currentIDs.contains(clientID) {
            clientID = Int.random(in: 1 ... Int.max)
        }
        assert(clientID > 0)
        return clientID
    }
}

// MARK: - Communication

extension OSCTCPServer: _OSCTCPSendProtocol {
    var _tcpSendConnection: NWConnection? { nil } // not used directly; each client has its own connection
    
    /// Send an OSC bundle or message to all connected clients.
    public func send(_ oscPacket: OSCPacket) throws {
        let clientIDs = clientsLock.withLock { Array(_clients.keys) }
        try send(oscPacket, toClientIDs: clientIDs)
    }
    
    /// Send an OSC bundle to all connected clients.
    public func send(_ oscBundle: OSCBundle) throws {
        try send(.bundle(oscBundle))
    }
    
    /// Send an OSC message to all connected clients.
    public func send(_ oscMessage: OSCMessage) throws {
        try send(.message(oscMessage))
    }
    
    /// Send an OSC bundle or message to one or more connected clients.
    public func send(_ oscPacket: OSCPacket, toClientIDs clientIDs: [Int]) throws {
        for clientID in clientIDs {
            try _send(oscPacket, toClientID: clientID)
        }
    }
    
    /// Send an OSC bundle to one or more connected clients.
    public func send(_ oscBundle: OSCBundle, toClientIDs clientIDs: [Int]) throws {
        try send(.bundle(oscBundle), toClientIDs: clientIDs)
    }
    
    /// Send an OSC message to one or more connected clients.
    public func send(_ oscMessage: OSCMessage, toClientIDs clientIDs: [Int]) throws {
        try send(.message(oscMessage), toClientIDs: clientIDs)
    }
    
    /// Send an OSC bundle or message to an individual connected client.
    func _send(_ oscPacket: OSCPacket, toClientID clientID: Int) throws {
        let connection = clientsLock.withLock { _clients[clientID] }
        guard let connection else {
            throw OSCSocketError.clientNotFound(id: clientID)
        }
        try connection.send(oscPacket)
    }
    
    /// Send an OSC bundle to an individual connected client.
    func _send(_ oscBundle: OSCBundle, toClientID clientID: Int) throws {
        try _send(.bundle(oscBundle), toClientID: clientID)
    }
    
    /// Send an OSC message to an individual connected client.
    func _send(_ oscMessage: OSCMessage, toClientID clientID: Int) throws {
        try _send(.message(oscMessage), toClientID: clientID)
    }
}

extension OSCTCPServer: _OSCTCPHandlerProtocol {
    // provides implementation for dispatching incoming OSC data
}

extension OSCTCPServer: _OSCTCPGeneratesServerNotificationsProtocol {
    func _generateConnectedNotification(remoteHost: String, remotePort: UInt16, clientID: OSCTCPClientSessionID) {
        let notif: Notification = .connected(remoteHost: remoteHost, remotePort: remotePort, clientID: clientID)
        notificationHandler?(notif)
    }
    
    func _generateDisconnectedNotification(
        remoteHost: String,
        remotePort: UInt16,
        clientID: OSCTCPClientSessionID,
        error: NWError?
    ) {
        let notif: Notification = .disconnected(remoteHost: remoteHost, remotePort: remotePort, clientID: clientID, error: error)
        notificationHandler?(notif)
    }
}

// MARK: - Properties

extension OSCTCPServer {
    /// Set the receive handler closure.
    /// This closure will be called when OSC bundles or messages are received.
    public func setReceiveHandler(
        _ handler: OSCHandlerBlock?
    ) {
        queue.async {
            self.receiveHandler = handler
        }
    }
    
    /// Set the notification handler closure.
    /// This closure will be called when a notification is generated, such as connection and disconnection events.
    public func setNotificationHandler(
        _ handler: NotificationHandlerBlock?
    ) {
        queue.async {
            self.notificationHandler = handler
        }
    }
    
    /// Returns a dictionary of currently connected clients keyed by client session ID.
    ///
    /// > Note:
    /// >
    /// > A client ID is transient and only valid for the lifecycle of the connection. Client IDs are randomly-assigned
    /// > upon each newly-made connection. For this reason, these IDs should not be stored persistently, but instead
    /// > queried from the OSC TCP server when a client connects or analyzing currently-connected clients.
    public var clients: [OSCTCPClientSessionID: (host: String, port: UInt16)] {
        clientsLock.withLock { _clients }
            .reduce(into: [:] as [OSCTCPClientSessionID: (host: String, port: UInt16)]) { base, element in
                base[element.key] = (
                    host: element.value.remoteHost,
                    port: element.value.remotePort
                )
            }
    }
    
    /// Disconnect a connected client from the server.
    public func disconnectClient(clientID: OSCTCPClientSessionID) {
        let connection = clientsLock.withLock { _clients[clientID] }
        connection?.close()
        clientsLock.withLock {
            _clients[clientID] = nil
        }
    }
}
