//
//  OSCUDPServer.swift
//  OSCKit • https://github.com/orchetect/OSCKit
//  © 2020-2026 Steffan Andrews • Licensed under MIT License
//

#if !os(watchOS)

import Foundation
import Network
import OSCKitCore

/// Receives OSC packets from the network on a specific UDP listen port.
///
/// A single global OSC server instance is often created once at app startup to receive OSC messages
/// on a specific local port. The default OSC port is 8000 but it may be set to any open port if
/// desired.
public final class OSCUDPServer {
    var udpConnection: NWConnection?
    var udpListener: NWListener?
    let queue: DispatchQueue
    var receiveHandler: OSCHandlerBlock?
    
    /// Time tag mode. Determines how OSC bundle time tags are handled.
    public var timeTagMode: OSCTimeTagMode
    
    /// UDP port used by the OSC server to listen for inbound OSC packets.
    /// This may only be set at the time of initialization.
    public var localPort: UInt16 {
        udpListener?.port?.rawValue ?? 0
    }

    private var _localPort: UInt16?
    
    /// Network interface to restrict connections to.
    public private(set) var interface: String?
    
    /// Enable local UDP port reuse by other processes.
    /// This property must be set prior to calling ``start()`` in order to take effect.
    ///
    /// By default, only one socket can be bound to a given IP address & port combination at a time. To enable
    /// multiple processes to simultaneously bind to the same address & port, you need to enable
    /// this functionality in the socket. All processes that wish to use the address & port
    /// simultaneously must all enable reuse port on the socket bound to that port.
    ///
    /// Due to limitations of `SO_REUSEPORT` on Apple platforms, enabling this only permits receipt of broadcast
    /// or multicast messages for any additional sockets which bind to the same address and port. Unicast
    /// messages are only received by the first socket to bind.
    public var isPortReuseEnabled: Bool = false
    
    /// Returns a boolean indicating whether the OSC server has been started.
    public var isStarted: Bool {
        udpListener?.state == .ready
    }
    
    /// Initialize an OSC server.
    ///
    /// The default port for OSC communication is 8000 but may change depending on device/software
    /// manufacturer.
    ///
    /// > Note:
    /// >
    /// > Ensure ``start()`` is called once after initialization in order to begin receiving messages.
    ///
    /// - Parameters:
    ///   - port: Local port to listen on for inbound OSC packets.
    ///     If `nil` or `0`, a random available port in the system will be chosen.
    ///   - interface: Optionally specify a network interface for which to constrain communication.
    ///   - isPortReuseEnabled: Enable local UDP port reuse by other processes to receive broadcast packets.
    ///   - timeTagMode: OSC TimeTag mode. (Default is recommended.)
    ///   - queue: Optionally supply a custom dispatch queue for receiving OSC packets and dispatching the
    ///     handler callback closure. If `nil`, a dedicated internal background queue will be used.
    ///   - receiveHandler: Handler to call when OSC bundles or messages are received.
    public init(
        port: UInt16? = 8000,
        interface: String? = nil,
        isPortReuseEnabled: Bool = false,
        timeTagMode: OSCTimeTagMode = .ignore,
        queue: DispatchQueue? = nil,
        receiveHandler: OSCHandlerBlock? = nil
    ) {
        _localPort = (port == nil || port == 0) ? nil : port
        self.interface = interface
        self.isPortReuseEnabled = isPortReuseEnabled
        self.timeTagMode = timeTagMode
        let queue = queue ?? DispatchQueue(label: "com.orchetect.OSCKit.OSCUDPServer.queue")
        self.queue = queue
        self.receiveHandler = receiveHandler
    }
}

extension OSCUDPServer: @unchecked Sendable { }

// MARK: - Lifecycle

extension OSCUDPServer {
    /// Bind the local UDP port and begin listening for OSC packets.
    public func start() throws {
        guard !isStarted else { return }
        
        stop()
        
        let port = _localPort.flatMap { NWEndpoint.Port(rawValue: $0) } ?? .any

        udpListener = try NWListener(using: _parameters, on: port)
        
        udpListener?.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            self._receiveNext(on: connection)
        }
        
        
        udpListener?.start(queue: queue)
    }
    
    /// Stops listening for data and closes the OSC server port.
    public func stop() {
        udpListener?.cancel()
        udpListener = nil
    }
}

// MARK: - Communication

extension OSCUDPServer {
    private func _receiveNext(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65535) { [weak self] data, _, _, error in
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

extension OSCUDPServer: _OSCHandlerProtocol {
    // provides implementation for dispatching incoming OSC data
}

// MARK: - Properties

extension OSCUDPServer {
    /// Set the receive handler closure.
    /// This closure will be called when OSC bundles or messages are received.
    public func setReceiveHandler(
        _ handler: OSCHandlerBlock?
    ) {
        queue.async {
            self.receiveHandler = handler
        }
    }
    
    private var _parameters: NWParameters {
        let parameters = NWParameters.udp
        
        let host = interface.flatMap { NWEndpoint.Host($0) } ?? .ipv4(.any)
        let port = _localPort.flatMap { NWEndpoint.Port(rawValue: $0) } ?? .any
        //bind to port
        parameters.requiredLocalEndpoint = .hostPort(host: host, port: port)
        
        parameters.allowLocalEndpointReuse = isPortReuseEnabled
        
        return parameters
    }
}

#endif
