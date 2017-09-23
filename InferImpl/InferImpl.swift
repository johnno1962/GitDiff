//
//  FormatImpl.swift
//  LNProvider
//
//  Created by John Holdsworth on 03/04/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//

import Foundation

let implementationFactory = InferImpl.self
var diffgen = DiffProcessor()

class InferDefaults: DefaultManager {

    open override var modifiedKey: String { return inferKey }

}

open class InferImpl: LNExtensionBase, LNExtensionService {

    open var defaults: DefaultManager {
        return InferDefaults()
    }

    open override func getConfig(_ callback: @escaping LNConfigCallback) {
        callback([
            LNApplyTitleKey: "Infer Types",
            LNApplyPromptKey: "Make type explicit",
            LNApplyConfirmKey: "Modify",
        ])
    }

    open func requestHighlights(forFile filepath: String, callback: @escaping LNHighlightCallback) {
        let url = URL(fileURLWithPath: filepath)

        guard url.pathExtension == "swift" else {
            callback(nil, nil)
            return
        }

        guard let script = Bundle.main.path(forResource: "infer", ofType: "sh") else {
            callback(nil, error(description: "script infer.sh not in XPC bundle"))
            return
        }

        DispatchQueue.global().async {
            let generator = TaskGenerator(launchPath: script, arguments: [filepath],
                                          directory: url.deletingLastPathComponent().path)

            for _ in 0 ..< 2 {
                _ = generator.next()
            }

            let highlights = diffgen.generateHighlights(sequence: generator.lineSequence, defaults: self.defaults)
            callback(highlights.jsonData(), nil)
        }
    }

}

