//
//  FormatImpl.swift
//  LNProvider
//
//  Created by John Holdsworth on 03/04/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//

import Foundation

let implementationFactory = FormatImpl.self
var diffgen = DiffProcessor()

class FormatDefaults: DefaultManager {

    open override var modifiedKey: String { return formatKey }

}

open class FormatImpl: LNExtensionBase, LNExtensionService {

    open var defaults: DefaultManager {
        return FormatDefaults()
    }

    open override func getConfig(_ callback: @escaping LNConfigCallback) {
        callback([
            LNApplyTitleKey: "Format Lint",
            LNApplyPromptKey: "Apply style suggestion to lines %d-%d",
            LNApplyConfirmKey: "Modify",
        ])
    }

    open var scripts = [
        "swift": "swift_format",
        "m":   "clang_format",
        "mm":  "clang_format",
        "h":   "clang_format",
        "cpp": "clang_format",
        "c":   "clang_format"
    ]

    open func requestHighlights(forFile filepath: String, callback: @escaping LNHighlightCallback) {
        let url = URL(fileURLWithPath: filepath)

        guard let diffScript = scripts[url.pathExtension] else {
            callback(nil, nil)
            return
        }

        guard let script = Bundle.main.path(forResource: diffScript, ofType: "sh") else {
            callback(nil, error(description: "script \(diffScript).sh not in XPC bundle"))
            return
        }

        DispatchQueue.global().async {
            let generator = TaskGenerator(launchPath: script,
                                          arguments: [url.lastPathComponent],
                                          directory: url.deletingLastPathComponent().path)

            for _ in 0 ..< 2 {
                _ = generator.next()
            }

            let highlights = diffgen.generateHighlights(sequence: generator.lineSequence, defaults: self.defaults)
            callback(highlights.jsonData(), nil)
        }
    }

}
