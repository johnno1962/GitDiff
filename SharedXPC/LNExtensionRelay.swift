//
//  LNExtensionRelay.swift
//  LNProvider
//
//  Created by John Holdsworth on 31/03/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//

import Foundation

let implementationFactory = LNExtensionRelay.self

open class LNExtensionRelay: LNExtensionBase, LNExtensionService, LNExtensionPlugin {

    private let implXPCService: NSXPCConnection = {
        let connection = NSXPCConnection(serviceName: EXTENSION_IMPL_SERVICE)
        connection.remoteObjectInterface = NSXPCInterface(with: LNExtensionService.self)
        connection.exportedInterface = NSXPCInterface(with: LNExtensionPlugin.self)
        connection.exportedObject = self
        connection.resume()
        return connection
    }()

    open var impl: LNExtensionService? {
        return implXPCService.remoteObjectProxy as? LNExtensionService
    }

    open override func getConfig(_ callback: @escaping LNConfigCallback) {
        impl?.getConfig({
            callback($0)
        })
    }

    public func updateConfig(_ config: [String: String]?, forService serviceName: String) {
        owner.updateConfig(config, forService: serviceName)
    }

    open func requestHighlights(forFile filepath: String, callback: @escaping LNHighlightCallback) {
        guard let impl = implXPCService.remoteObjectProxy as? LNExtensionService else { return }
        impl.requestHighlights(forFile: filepath, callback: {
            callback($0, $1)
        })
    }

    open func updateHighlights(_ json: Data?, error: Error?, forFile filepath: String) {
        owner.updateHighlights(json, error: error, forFile: filepath)
    }

    open override func ping(_ test: Int32, callback: @escaping (Int32) -> Void) {
        impl?.ping(test, callback: {
            callback($0 + 1_000_000)
        })
    }

}
