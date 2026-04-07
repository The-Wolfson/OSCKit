//
//  File.swift
//  OSCKit
//
//  Created by Joshua Wolfson on 6/4/2026.
//

#if !os(watchOS)

import Foundation

extension OSCUDPClient {
    @_documentation(visibility: internal)
    @available(*, deprecated, renamed: "init(localPort:interface:isPortReuseEnabled:queue:)")
    @_disfavoredOverload
    public convenience init(
        localPort: UInt16?,
        interface: String? = nil,
        isPortReuseEnabled: Bool = false,
        isIPv4BroadcastEnabled: Bool = false
    ) {
        self.init(localPort: localPort, interface: interface, isPortReuseEnabled: isPortReuseEnabled, queue: nil)
    }
    
    /// Enable sending IPv4 broadcast messages from the socket.
    /// This may be set at any time.
    ///
    /// By default, the socket will not allow you to send broadcast messages as a network safeguard
    /// and it is an opt-in feature.
    ///
    /// A broadcast UDP message can be sent to a correctly formatted broadcast address. A broadcast
    /// address is the highest IP address for a subnet or a network.
    ///
    /// For example, a class C network with first octet `192`, one subnet, and subnet mask of
    /// `255.255.255.0` would have a broadcast address of `192.168.0.255` and would effectively send
    /// to `192.168.0.*` (where `*` is the range `1 ... 254`).
    ///
    /// 255.255.255.255 is a special broadcast address which targets all hosts on a local network.
    ///
    /// For more information on IPv4 broadcast addresses, see
    /// [Broadcast Address (Wikipedia)](https://en.wikipedia.org/wiki/Broadcast_address) and [Subnet
    /// Calculator](https://www.subnet-calculator.com).
    ///
    /// Internet Protocol version 6 (IPv6) does not implement this method of broadcast, and
    /// therefore does not define broadcast addresses. Instead, IPv6 uses multicast addressing.
    @_documentation(visibility: internal)
    @available(*, deprecated, message: "Network does not support UDP Broadcast, it is suggested to implement Bonjour discovery instead: https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api#UDP")
    public var isIPv4BroadcastEnabled: Bool { false }
}

extension OSCUDPSocket {
    /// Enable sending IPv4 broadcast messages from the socket.
    ///
    /// By default, the socket will not allow you to send broadcast messages as a network safeguard
    /// and it is an opt-in feature.
    ///
    /// A broadcast UDP message can be sent to a correctly formatted broadcast address. A broadcast
    /// address is the highest IP address for a subnet or a network.
    ///
    /// For example, a class C network with first octet `192`, one subnet, and subnet mask of
    /// `255.255.255.0` would have a broadcast address of `192.168.0.255` and would effectively send
    /// to `192.168.0.*` (where `*` is the range `1 ... 254`).
    ///
    /// 255.255.255.255 is a special broadcast address which targets all hosts on a local network.
    ///
    /// For more information on IPv4 broadcast addresses, see
    /// [Broadcast Address (Wikipedia)](https://en.wikipedia.org/wiki/Broadcast_address) and [Subnet
    /// Calculator](https://www.subnet-calculator.com).
    ///
    /// Internet Protocol version 6 (IPv6) does not implement this method of broadcast, and
    /// therefore does not define broadcast addresses. Instead, IPv6 uses multicast addressing.
    @_documentation(visibility: internal)
    @available(*, deprecated, message: "Network does not support UDP Broadcast, it is suggested to implement Bonjour discovery instead: https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api#UDP")
    public var isIPv4BroadcastEnabled: Bool { false }
    
    @_documentation(visibility: internal)
    @available(*, deprecated, renamed: "init(localPort:remoteHost:remotePort:interface:timeTagMode:queue:receiveHandler:)")
    @_disfavoredOverload
    public convenience init(
        localPort: UInt16? = nil,
        remoteHost: String? = nil,
        remotePort: UInt16? = nil,
        interface: String? = nil,
        timeTagMode: OSCTimeTagMode = .ignore,
        isIPv4BroadcastEnabled: Bool = false,
        queue: DispatchQueue? = nil,
        receiveHandler: OSCHandlerBlock? = nil
    ) {
        self.init(localPort: localPort, remoteHost: remoteHost, remotePort: remotePort, interface: interface, timeTagMode: timeTagMode, queue: queue, receiveHandler: receiveHandler)
    }
}

#endif
