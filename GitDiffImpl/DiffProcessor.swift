//
//  DiffProessor.swift
//  LNProvider
//
//  Created by John Holdsworth on 03/04/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//

import Foundation

class DiffProcessor {

    let regex = try! NSRegularExpression(pattern: "^(?:(?:@@ -\\d+,\\d+ \\+(\\d+),\\d+ @@)|([-+])(.*))", options: [])

    enum Delta {
        case start(lineno: Int)
        case delete(text: String)
        case insert(text: String)
        case other
    }

    func delta(line: String) -> Delta {
        if let match = regex.firstMatch(in: line, options: [], range: NSMakeRange(0, line.characters.count)) {
            if let lineno = match.group(1, in: line) {
                return .start(lineno: Int(lineno) ?? -1)
            } else if let delta = match.group(2, in: line), let text = match.group(3, in: line) {
                if delta == "-" {
                    return .delete(text: text)
                } else {
                    return .insert(text: text)
                }
            }
        }
        return .other
    }

    func textDiff(_ inserted: String, against deleted: String, defaults: DefaultManager) -> NSAttributedString {
        let attributes = [NSForegroundColorAttributeName: defaults.extraColor]
        let attributed = NSMutableAttributedString()

        for diff in diff_diffsBetweenTexts(deleted, inserted) {
            let diff = diff as! DMDiff
            if diff.operation == DIFF_INSERT {
                continue
            }

            let next = NSMutableAttributedString(string: diff.text ?? "")
            if diff.operation == DIFF_DELETE {
                next.setAttributes(attributes, range: NSMakeRange(0, next.length))
            }

            attributed.append(next)
        }

        return attributed
    }

    open func generateHighlights(sequence: AnySequence<String>, defaults: DefaultManager) -> LNFileHighlights {
        let deletedColor = defaults.deletedColor
        let modifiedColor = defaults.modifiedColor
        let addedColor = defaults.addedColor

        var currentLine = 0, startLine = 0, deletedCount = 0, insertedText = ""
        let fileHighlights = LNFileHighlights()
        var element: LNHighlightElement?

        func closeRange() {
            element?.range = "\(startLine) \(currentLine - startLine)"
            if let deleted = element?.text {
                element?.setAttributedText(textDiff(insertedText, against: deleted, defaults: defaults))
            }
        }

        for line in sequence {

            switch delta(line: line) {
            case .start(let lineno):
                currentLine = lineno
                break
            case .delete(let text):
                if element == nil {
                    startLine = currentLine
                    element = LNHighlightElement()
                    element?.start = currentLine
                    element?.color = modifiedColor
                    element?.text = ""
                    fileHighlights[currentLine] = element
                }
                element?.text = (element?.text ?? "") + text + "\n"
                deletedCount += 1
                break
            case .insert(let text):
                if element == nil || currentLine - startLine >= deletedCount && element?.color != addedColor {
                    if element == nil {
                        startLine = currentLine
                    }
                    closeRange()
                    element = LNHighlightElement()
                    element?.start = currentLine
                    element?.color = addedColor
                }
                fileHighlights[currentLine] = element
                insertedText += text
                currentLine += 1
                break
            case .other:
                if element?.color == modifiedColor && currentLine == startLine {
                    element?.color = deletedColor
                }
                closeRange()
                currentLine += 1
                insertedText = ""
                deletedCount = 0
                element = nil
                break
            }
        }

        return fileHighlights
    }

}

extension NSTextCheckingResult {

    func group(_ group: Int, in string: String) -> String? {
        if rangeAt(group).location != NSNotFound {
            return string[rangeAt(group)]
        }
        return nil
    }

}

extension String {

    public subscript(i: Int) -> String {
        return self[i ..< i + 1]
    }

    public subscript(range: NSRange) -> String {
        return self[range.location ..< range.location + range.length]
    }

    public subscript(r: Range<Int>) -> String {
        return String(describing: utf16[UTF16Index(r.lowerBound) ..< UTF16Index(r.upperBound)])
    }
    
}
