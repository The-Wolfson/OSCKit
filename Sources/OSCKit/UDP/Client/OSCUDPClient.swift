//
//  OSCUDPClient.swift
//  OSCKit • https://github.com/orchetect/OSCKit
//  © 2020-2026 Steffan Andrews • Licensed under MIT License
//

#if !os(watchOS)

import Foundation
import Network

/// Sends OSC packets over the network using the UDP network protocol.
///
/// A single global OSC client instance created once at app startup is often all that is needed. It
/// can be used to send OSC messages to one or more receivers on the network.
public final class OSCUDPClient {
    var queue: DispatchQueue = DispatchQueue(label: "com.orchetect.OSCKit.OSCUDPClient.queue")
    
    /// Local UDP port used by the client from which to send OSC packets. (This is not the remote port
    /// which is specified each time a call to ``send(_:to:port:)-(OSCPacket,_,_)`` is made.)
    /// This may only be set at the time of initialization.
    ///
    /// > Note:
    /// >
    /// > If `localPort` was not specified at the time of initialization, reading this
    /// > property may return a value of `0` until the first successful call to ``send(_:to:port:)-(OSCPacket,_,_)``
    /// > is made.
    public var localPort: UInt16 {
        _localPort ?? 0
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
    public var isPortReuseEnabled: Bool = false
    
    /// Returns a boolean indicating whether the OSC client has been started.
    public private(set) var isStarted: Bool = false
    
    /// Initialize an OSC client to send messages using the UDP network protocol.
    ///
    /// A random available port in the system will be chosen.
    ///
    /// Using this initializer does not require calling ``start()``.
    public init() {
        //start()
    }
    
    /// Initialize an OSC client to send messages using the UDP network protocol using a specific local port.
    ///
    /// > Note:
    /// >
    /// > Ensure ``start()`` is called once after initialization in order to begin sending messages.
    ///
    /// > Note:
    /// >
    /// > It is not typically necessary to bind to a static local port unless there is a particular need to have
    /// > control over which local port OSC messages originate from. In most cases, a randomly assigned port is
    /// > sufficient and prevents local port usage collisions.
    /// >
    /// > This may, however, be necessary in some cases where certain hardware devices expect to receive OSC from a
    /// > prescribed remote sender port number. In this case it is often more advantageous to use the combined
    /// > client/server ``OSCUDPSocket`` object instead, which is designed to make working with these kind round-trip
    /// > requirements more streamlined.
    /// >
    /// > To allow the system to assign a random available local port, use the ``init()`` initializer
    /// > instead.
    ///
    /// - Parameters:
    ///   - localPort: Local UDP port used by the client from which to send OSC packets.
    ///     If `nil` or `0`, a random available port in the system will be chosen.
    ///   - interface: Optionally specify a network interface for which to constrain communication.
    ///   - isPortReuseEnabled: Enable local UDP port reuse by other processes.
    ///   - queue: Optionally supply a custom dispatch queue for receiving OSC packets and dispatching the
    ///     handler callback closure. If `nil`, a dedicated internal background queue will be used.
    public convenience init(
        localPort: UInt16?,
        interface: String? = nil,
        isPortReuseEnabled: Bool = false,
        queue: DispatchQueue? = nil
    ) {
        self.init()
        
        _localPort = (localPort == nil || localPort == 0) ? nil : localPort
        self.interface = interface
        self.isPortReuseEnabled = isPortReuseEnabled
        if let queue {
            self.queue = queue
        }
    }
    
    deinit {
        stop()
    }
}

extension OSCUDPClient: @unchecked Sendable { }

// MARK: - Lifecycle

extension OSCUDPClient {
    /// Bind the local UDP port.
    /// This call is only necessary if a local port was specified at the time of class
    /// initialization or if class properties were modified after initialization.
    public func start() throws {
        guard !isStarted else { return }
        
        isStarted = true
    }
    
    /// Closes the OSC port.
    public func stop() {
        isStarted = false
    }
}

// MARK: - Communication

extension OSCUDPClient {
    private func _send(_ data: Data, host: String, port: UInt16) {
        let parameters = _parameters
        let networkPort = NWEndpoint.Port(rawValue: port) ?? .any
        let connection = NWConnection(host: NWEndpoint.Host(host), port: networkPort, using: parameters)
        connection.start(queue: queue)
        connection.send(content: data, completion: .contentProcessed { error in
            connection.cancel()
        })
    }
    
    /// Send an OSC bundle or message ad-hoc to a recipient on the network.
    ///
    /// The default port for OSC communication is 8000 but may change depending on device/software
    /// manufacturer.
    public func send(
        _ oscPacket: OSCPacket,
        to host: String,
        port: UInt16 = 8000
    ) throws {
        let data = try oscPacket.rawData()
        
        _send(data, host: host, port: port)
    }
    
    /// Send an OSC bundle ad-hoc to a recipient on the network.
    ///
    /// The default port for OSC communication is 8000 but may change depending on device/software
    /// manufacturer.
    public func send(
        _ oscBundle: OSCBundle,
        to host: String,
        port: UInt16 = 8000
    ) throws {
        let data = try oscBundle.rawData()
        
        _send(data, host: host, port: port)
    }
    
    /// Send an OSC message ad-hoc to a recipient on the network.
    ///
    /// The default port for OSC communication is 8000 but may change depending on device/software
    /// manufacturer.
    public func send(
        _ oscMessage: OSCMessage,
        to host: String,
        port: UInt16 = 8000
    ) throws {
        let data = try oscMessage.rawData()
        
        _send(data, host: host, port: port)
    }
}

extension OSCUDPClient {
    private var _parameters: NWParameters {
        let parameters = NWParameters.udp
        
        let host = interface.flatMap { NWEndpoint.Host($0) } ?? .ipv4(.any)
        let port = _localPort.flatMap { NWEndpoint.Port(rawValue: $0) } ?? .any
        
        parameters.requiredLocalEndpoint = .hostPort(host: host, port: port)
        
        if isPortReuseEnabled {
            parameters.allowLocalEndpointReuse = true
        }
        
        return parameters
    }
}

#endif
