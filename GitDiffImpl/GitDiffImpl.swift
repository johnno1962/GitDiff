//
//  GitDiffImpl.swift
//  LNProvider
//
//  Created by John Holdsworth on 31/03/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//

import Foundation

let implementationFactory = GitDiffImpl.self
var lineNumberDefaults = DefaultManager()
var diffgen = DiffProcessor()

open class GitDiffImpl: LNExtensionBase, LNExtensionService {

    open override func getConfig(_ callback: @escaping LNConfigCallback) {
        callback([
            LNPopoverColorKey: lineNumberDefaults.popoverColor.stringRepresentation,
            LNApplyTitleKey: "GitDiff",
            LNApplyPromptKey: "Revert code at lines %d-%d to staged version?",
            LNApplyConfirmKey: "Revert",
        ])
    }

    open func requestHighlights(forFile filepath: String, callback: @escaping LNHighlightCallback) {
        DispatchQueue.global().async {
            let url = URL(fileURLWithPath: filepath)
            var arguments = ["git", "diff", "--no-ext-diff", "--no-color"]
            if lineNumberDefaults.showHead {
                arguments.append("HEAD")
            }
            arguments.append(url.lastPathComponent)
            let generator = TaskGenerator(launchPath: "/usr/bin/env", arguments: arguments,
                                          directory: url.deletingLastPathComponent().path)

            for _ in 0 ..< 4 {
                _ = generator.next()
            }

            let highlights = diffgen.generateHighlights(sequence: generator.lineSequence, defaults: lineNumberDefaults)
            callback(highlights.jsonData(), nil)
        }
    }
    
}
