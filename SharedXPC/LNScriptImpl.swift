//
//  LNScriptImpl.swift
//  LNProvider
//
//  Created by John Holdsworth on 31/03/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//

import Foundation

let implementationFactory = LNScriptImpl.self

open class LNScriptImpl: LNExtensionBase, LNExtensionService {

    open var scriptExt: String {
        return "py"
    }

    open func requestHighlights(forFile filepath: String, callback: @escaping LNHighlightCallback) {
        guard let script = Bundle.main.path(forResource: EXTENSION_IMPL_SCRIPT, ofType: scriptExt) else {
            callback(nil, error(description: "script \(EXTENSION_IMPL_SCRIPT).\(scriptExt) not in XPC bundle"))
            return
        }

        DispatchQueue.global().async {
            let url = URL(fileURLWithPath: filepath)
            let task = Process()

            task.launchPath = script
            task.arguments = [url.lastPathComponent]
            task.currentDirectoryPath = url.deletingLastPathComponent().path

            let pipe = Pipe()
            task.standardOutput = pipe.fileHandleForWriting
            task.standardError = pipe.fileHandleForWriting

            task.launch()
            pipe.fileHandleForWriting.closeFile()
            let json = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            if task.terminationStatus != 0 {
                let alert = "Script \(EXTENSION_IMPL_SCRIPT).\(self.scriptExt) exit status " +
                    "\(task.terminationStatus):\n" + (String(data: json, encoding: .utf8) ?? "No output")
                callback(json, self.error(description: alert))
            } else {
                callback(json, nil)
            }
        }
    }
    
}
