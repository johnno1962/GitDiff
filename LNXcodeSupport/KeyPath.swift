//
//  KeyPath.swift
//  LNProvider
//
//  Created by John Holdsworth on 09/06/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//

import Foundation

@objc public class KeyPath: NSObject {

    @objc public class func object(for keyPath: String, from: AnyObject) -> AnyObject? {
        var out = from
        for key in keyPath.components(separatedBy: ".") {
            for (name, value) in Mirror(reflecting: out).children {
                if name == key || name == key + ".storage" {
                    let mirror = Mirror(reflecting: value)
                    if name == "lineNumberLayers" {
                        let dict = NSMutableDictionary()
                        for (_, pair) in mirror.children {
                            let children = Mirror(reflecting: pair).children
                            let key = children.first!.value as! Int
                            let value = children.dropFirst().first!.value
                            dict[NSNumber(value: key)] = value
                        }
                        out = dict
                    } else if name == "name" {
                        out = value as! String as NSString
                    } else if mirror.displayStyle == .optional,
                        let value = mirror.children.first?.value {
                        out = value as AnyObject
                    } else {
                        out = value as AnyObject
                    }
                    break
                }
            }
        }
        return out === from ? nil : out
    }
}
