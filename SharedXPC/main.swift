//
//  main.swift
//  LNProvider
//
//  Created by John Holdsworth on 02/04/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//

import Foundation

class ServiceDelegate: NSObject, NSXPCListenerDelegate {

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        return implementationFactory.init(connection: newConnection) != nil
    }

}

// Create the delegate for the service.
let delegate = ServiceDelegate()

// can't get this to work :(
// let globalListener = NSXPCListener(machServiceName: Bundle.main.bundleIdentifier!)
// globalListener.delegate = delegate
// globalListener.resume()

// Set up the one NSXPCListener for this service. It will handle all incoming connections.
let listener = NSXPCListener.service()
listener.delegate = delegate

// Resuming the serviceListener starts this service. This method does not return.
listener.resume()
