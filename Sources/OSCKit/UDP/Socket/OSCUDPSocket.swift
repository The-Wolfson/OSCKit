//
//  OSCUDPSocket.swift
//  OSCKit • https://github.com/orchetect/OSCKit
//  © 2020-2026 Steffan Andrews • Licensed under MIT License
//

#if !os(watchOS)

import Foundation
import Network

/// Sends and receives OSC packets over the network by binding a single local UDP port to both send
/// OSC packets from and listen for incoming packets.
///
/// The `OSCUDPSocket` object internally combines both an OSC server and client sharing the same local
/// UDP port number. What sets it apart from ``OSCUDPServer`` and ``OSCUDPClient`` is that it does not
/// require enabling port reuse to accomplish this. It also can conceptually make communicating
/// bidirectionally with a single remote host more intuitive.
///
/// This also fulfils a niche requirement for communicating with OSC devices such as the Behringer
/// X32 & M32 which respond back using the UDP port that they receive OSC messages from. For
/// example: if an OSC message was sent from port 8000 to the X32's port 10023, the X32 will respond
/// by sending OSC messages back to you on port 8000.
public final class OSCUDPSocket {
    var udpListener: NWListener?
    var udpConnection: NWConnection?
    let queue: DispatchQueue
    var receiveHandler: OSCHandlerBlock?
    
    /// Time tag mode. Determines how OSC bundle time tags are handled.
    public var timeTagMode: OSCTimeTagMode
    
    /// Remote network hostname.
    /// If non-nil, this host will be used in calls to ``send(_:to:port:)-(OSCPacket,_,_)``. The host may still be
    /// overridden using the `host` parameter in the call to ``send(_:to:port:)-(OSCPacket,_,_)``..
    public var remoteHost: String?
    
    /// Local UDP port used to both send OSC packets from and listen for incoming packets.
    /// This may only be set at the time of initialization.
    ///
    /// The default port for OSC communication is 8000 but may change depending on device/software
    /// manufacturer.
    ///
    /// > Note:
    /// >
    /// > If `localPort` was not specified at the time of initialization, reading this
    /// > property may return a value of `0` until the first successful call to ``send(_:to:port:)-(OSCPacket,_,_)``
    /// > is made.
    public var localPort: UInt16 {
        udpListener?.port?.rawValue ?? 0
    }

    private var _localPort: UInt16?
    
    /// UDP port used by to send OSC packets. This may be set at any time.
    /// This port will be used in calls to ``send(_:to:port:)-(OSCPacket,_,_)``. The port may still be overridden
    /// using the `port` parameter in the call to ``send(_:to:port:)-(OSCPacket,_,_)``.
    ///
    /// The default port for OSC communication is 8000 but may change depending on device/software
    /// manufacturer.
    public var remotePort: UInt16 {
        get { _remotePort ?? localPort }
        set { _remotePort = (newValue == 0) ? nil : newValue }
    }

    private var _remotePort: UInt16?
    
    /// Network interface to restrict connections to.
    public private(set) var interface: String?
    
    /// Returns a boolean indicating whether the OSC socket has been started.
    public var isStarted: Bool {
        udpListener?.state == .ready
    }
    
    /// Initialize with a remote hostname and UDP port.
    ///
    /// > Note:
    /// >
    /// > Ensure ``start()`` is called once after initialization in order to begin sending and receiving messages.
    ///
    /// - Parameters:
    ///   - localPort: Local port to listen on for inbound OSC packets.
    ///     If `nil` or `0`, a random available port in the system will be chosen.
    ///   - remoteHost: Remote hostname or IP address.
    ///   - remotePort: Remote port on the remote host machine to send outbound OSC packets to.
    ///     If `nil` or `0`, the `localPort` value will be used.
    ///   - interface: Optionally specify a network interface for which to constrain communication.
    ///   - timeTagMode: OSC time-tag mode. The default is recommended.
    ///   - queue: Optionally supply a custom dispatch queue for receiving OSC packets and dispatching the
    ///     handler callback closure. If `nil`, a dedicated internal background queue will be used.
    ///   - receiveHandler: Handler to call when OSC bundles or messages are received.
    public init(
        localPort: UInt16? = nil,
        remoteHost: String? = nil,
        remotePort: UInt16? = nil,
        interface: String? = nil,
        timeTagMode: OSCTimeTagMode = .ignore,
        queue: DispatchQueue? = nil,
        receiveHandler: OSCHandlerBlock? = nil
    ) {
        self.remoteHost = remoteHost
        _localPort = (localPort == nil || localPort == 0) ? nil : localPort
        _remotePort = (remotePort == nil || remotePort == 0) ? nil : remotePort
        self.interface = interface
        self.timeTagMode = timeTagMode
        let queue = queue ?? DispatchQueue(label: "com.orchetect.OSCKit.OSCUDPSocket.queue")
        self.queue = queue
        self.receiveHandler = receiveHandler
    }
}

extension OSCUDPSocket: @unchecked Sendable { }

// MARK: - Lifecycle

extension OSCUDPSocket {
    /// Bind the local UDP port and begin listening for OSC packets.
    public func start() throws {
        guard !isStarted else { return }
        
        let port = _localPort.flatMap { NWEndpoint.Port(rawValue: $0) } ?? .any
        let listener = try NWListener(using: _parameters, on: port)
        
        listener.newConnectionHandler = { [weak self] connection in
             guard let self else { return }
            print("OSCUDPSocket", "-", "New Connection From:", connection.endpoint)
             connection.start(queue: self.queue)
             self._receiveNext(on: connection)
        }
        
        listener.stateUpdateHandler = { state in
            print("OSCUDPSocket", "-", "Listener State:", state)
        }
        udpListener = listener
        listener.start(queue: queue)
    }
    
    /// Stops listening for data and closes the OSC port.
    public func stop() {
        udpListener?.cancel()
        udpListener = nil
    }
}

// MARK: - Communication

extension OSCUDPSocket {
    private func _receiveNext(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65535) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                guard case .hostPort(let host, let port) = connection.endpoint else { return }
                self._handle(data: data, remoteHost: host.debugDescription, remotePort: port.rawValue)
            }
            
            if error == nil {
                self._receiveNext(on: connection)
            }
        }
    }
    
    private func _handle(data: Data, remoteHost: String, remotePort: UInt16) {
        do {
            guard let packet = try OSCPacket(from: data) else { return }
            _handle(packet: packet, remoteHost: remoteHost, remotePort: remotePort)
        } catch {
            #if DEBUG
            print("OSC parse error: \(error.localizedDescription)")
            #endif
        }
    }
}

extension OSCUDPSocket {
    /// Send an OSC bundle or message to the remote host.
    /// The ``remoteHost`` and ``remotePort`` properties are used unless one or both are
    /// overridden in this call.
    ///
    /// The default port for OSC communication is 8000 but may change depending on device/software
    /// manufacturer.
    public func send(
        _ oscPacket: OSCPacket,
        to host: String? = nil,
        port: UInt16? = nil
    ) throws {
        guard isStarted else {
            throw OSCNetworkError.notStarted
        }
        
        guard let toHost = host ?? remoteHost else {
            //Remote host is not specified in OSCUDPSocket.remoteHost property or in host parameter in call to send().
            throw OSCNetworkError.noRemoteHost
        }
        
        let data = try oscPacket.rawData()
        
        let udpHost = NWEndpoint.Host(toHost)
        let udpPort = NWEndpoint.Port(rawValue: port ?? remotePort) ?? .any
        let endpoint = NWEndpoint.hostPort(host: udpHost, port: udpPort)
        
        if udpConnection == nil, udpConnection?.endpoint != endpoint {
            udpConnection?.cancel()
            
            let connection = NWConnection(to: endpoint, using: _parameters)
            connection.start(queue: queue)
            udpConnection = connection
        }
        
        udpConnection?.send(content: data, completion: .contentProcessed({ _ in }))
    }
    
    /// Send an OSC bundle to the remote host.
    /// The ``remoteHost`` and ``remotePort`` properties are used unless one or both are
    /// overridden in this call.
    ///
    /// The default port for OSC communication is 8000 but may change depending on device/software
    /// manufacturer.
    public func send(
        _ oscBundle: OSCBundle,
        to host: String? = nil,
        port: UInt16? = nil
    ) throws {
        try send(.bundle(oscBundle), to: host, port: port)
    }
    
    /// Send an OSC message to the remote host.
    /// The ``remoteHost`` and ``remotePort`` properties are used unless one or both are
    /// overridden in this call.
    ///
    /// The default port for OSC communication is 8000 but may change depending on device/software
    /// manufacturer.
    public func send(
        _ oscMessage: OSCMessage,
        to host: String? = nil,
        port: UInt16? = nil
    ) throws {
        try send(.message(oscMessage), to: host, port: port)
    }
}

extension OSCUDPSocket: _OSCHandlerProtocol { }

// MARK: - Properties

extension OSCUDPSocket {
    /// Set the receive handler closure.
    /// This closure will be called when OSC bundles or messages are received.
    public func setReceiveHandler(
        _ handler: OSCHandlerBlock?
    ) {
        queue.async {
            self.receiveHandler = handler
        }
    }
}

//Helper properties for NWConnection
extension OSCUDPSocket {
    private var _remoteEndpoint: NWEndpoint {
        let host = remoteHost.flatMap { NWEndpoint.Host($0) } ?? .ipv4(.any)
        let port = NWEndpoint.Port(rawValue: remotePort) ?? .any
        
        let endpoint = NWEndpoint.hostPort(host: host, port: port)
        
        return endpoint
    }

    private var _parameters: NWParameters {
        let parameters = NWParameters.udp
        
        let host = interface.flatMap { NWEndpoint.Host($0) } ?? .ipv4(.any)
        let port = _localPort.flatMap { NWEndpoint.Port(rawValue: $0) } ?? .any
        
        parameters.requiredLocalEndpoint = .hostPort(host: host, port: port)
        
        // Allow port reuse so the listener and outgoing connections can share the same local port.
        parameters.allowLocalEndpointReuse = true
        
        return parameters
    }
}

#endif
