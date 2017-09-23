//
//  KeyPath.swift
//  LNProvider
//
//  Created by John Holdsworth on 09/06/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//

import Foundation

@objc public class KeyPath: NSObject {

    @objc public class func object(for keyPath: String, from: AnyObject) -> AnyObject {
        var out = from
        for key in keyPath.components(separatedBy: ".") {
            for (name, value) in Mirror(reflecting: out).children {
                if name == key || name == key + ".storage" {
                    let mirror = Mirror(reflecting: value)
                    if mirror.displayStyle == .optional,
                        let value = mirror.children.first?.value {
                        out = value as AnyObject
                    } else {
                        out = value as AnyObject
                    }
                    break
                }
            }
        }
        return out
    }
}
