//
//  LNExtensionBase.swift
//  LNProvider
//
//  Created by John Holdsworth on 31/03/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//

import Cocoa

open class LNExtensionBase: NSObject {

    var owner: LNExtensionPlugin!

    open func getConfig(_ callback: @escaping LNConfigCallback) {
        callback(["config": "here"])
    }

    open func ping(_ test: Int32, callback: @escaping (Int32) -> Void) {
        callback(test + 1000)
    }

    open func error(description: String) -> NSError {
        return NSError(domain: "Line Number Extension", code: -1000, userInfo: [
            NSLocalizedDescriptionKey: description,
        ])
    }

    public required init?(connection: NSXPCConnection?) {
        if connection != nil {
            connection!.remoteObjectInterface = NSXPCInterface(with: LNExtensionPlugin.self)
            owner = connection!.remoteObjectProxy as! LNExtensionPlugin
        }

        super.init()

        connection?.exportedInterface = NSXPCInterface(with: LNExtensionService.self)
        connection?.exportedObject = self
        connection?.resume()
    }

}
