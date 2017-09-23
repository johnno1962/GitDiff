//
//  DefaultManager.swift
//  LNProvider
//
//  Created by John Holdsworth on 03/04/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//

import Cocoa

open class DefaultManager: NSObject {

    open var defaults = UserDefaults(suiteName: "LineNumber")!

    @IBOutlet weak var popoverColorWell: NSColorWell!
    @IBOutlet weak var deletedColorWell: NSColorWell!
    @IBOutlet weak var modifiedColorWell: NSColorWell!
    @IBOutlet weak var addedColorWell: NSColorWell!
    @IBOutlet weak var extraColorWell: NSColorWell!
    @IBOutlet weak var recentColorWell: NSColorWell!
    @IBOutlet weak var formatColorWell: NSColorWell!
    @IBOutlet weak var inferColorWell: NSColorWell!

    @IBOutlet weak var recentDaysField: NSTextField!
    @IBOutlet weak var formatIndentField: NSTextField!

    open var popoverKey:  String { return "PopoverColor" }
    open var deletedKey:  String { return "DeletedColor" }
    open var modifiedKey: String { return "ModifiedColor" }
    open var addedKey:    String { return "AddedColor" }
    open var extraKey:    String { return "ExtraColor" }
    open var recentKey:   String { return "RecentColor" }
    open var formatKey:   String { return "FormatColor" }
    open var inferKey:    String { return "InferColor" }

    open var showHeadKey: String { return "ShowHead" }
    open var recentDaysKey: String { return "RecentDays" }
    open var formatIndentKey: String { return "FormatIndent" }

    open lazy var wellKeys: [NSColorWell: String] = [
        self.popoverColorWell:  self.popoverKey,
        self.deletedColorWell:  self.deletedKey,
        self.modifiedColorWell: self.modifiedKey,
        self.addedColorWell:    self.addedKey,
        self.extraColorWell:    self.extraKey,
        self.recentColorWell:   self.recentKey,
        self.formatColorWell:   self.formatKey,
        self.inferColorWell:    self.inferKey,
    ]

    open override func awakeFromNib() {
        for (colorWell, key) in wellKeys {
            setup(colorWell, key: key)
        }
        if let existing = defaults.value(forKey: recentDaysKey) {
            recentDaysField?.stringValue = existing as! String
        } else if recentDaysField != nil {
            defaults.set(recentDaysField.stringValue, forKey: recentDaysKey)
        }
        if let existing = defaults.value(forKey: formatIndentKey) {
            formatIndentField?.stringValue = existing as! String
        } else if formatIndentField != nil {
            defaults.set(formatIndentField.stringValue, forKey: formatIndentKey)
        }
        defaults.synchronize()
    }

    open func setup(_ colorWell: NSColorWell?, key: String) {
        if let existing = defaults.value(forKey: key) {
            colorWell?.color = NSColor(string: existing as! String)
        } else if colorWell != nil {
            defaults.set(colorWell!.color.stringRepresentation, forKey: key)
        }
    }

    @IBAction func colorChanged(sender: NSColorWell) {
        if let key = wellKeys[sender] {
            defaults.set(sender.color.stringRepresentation, forKey: key)
        }
    }

    @IBAction func reset(sender: NSButton) {
        for (_, key) in wellKeys {
            defaults.removeObject(forKey: key)
        }
        popoverColorWell?.color  = popoverColor
        deletedColorWell?.color  = deletedColor
        modifiedColorWell?.color = modifiedColor
        addedColorWell?.color    = addedColor
        extraColorWell?.color    = extraColor
        recentColorWell?.color   = recentColor
        formatColorWell?.color   = formatColor
        inferColorWell?.color    = inferColor
        awakeFromNib()
    }

    open func defaultColor(for key: String, default value: String) -> NSColor {
        return NSColor(string: defaults.value(forKey: key) as? String ?? value)
    }

    open var popoverColor: NSColor {
        return defaultColor(for: popoverKey, default: "1 0.914 0.662 1")
    }

    open var deletedColor: NSColor {
        return defaultColor(for: deletedKey, default: "1 0.584 0.571 1")
    }

    open var modifiedColor: NSColor {
        return defaultColor(for: modifiedKey, default: "1 0.576 0 1")
    }

    open var addedColor: NSColor {
        return defaultColor(for: addedKey, default: "0.253 0.659 0.694 1")
    }

    open var extraColor: NSColor {
        return defaultColor(for: extraKey, default: "0.5 0 0 1")
    }

    open var recentColor: NSColor {
        return defaultColor(for: recentKey, default: "0.5 1.0 0.5 1")
    }

    open var formatColor: NSColor {
        return defaultColor(for: formatKey, default: "0.129 0.313 1 1")
    }

    open var inferColor: NSColor {
        return defaultColor(for: inferKey, default: "1 0 0 1")
    }

    open var showHead: Bool {
        return defaults.bool(forKey: showHeadKey)
    }

    @IBAction open func showHeadChanged(sender: NSButton) {
        defaults.set(sender.state == NSOnState, forKey: showHeadKey)
    }

    @IBAction open func recentChanged(sender: NSTextField) {
        defaults.setValue(sender.stringValue, forKey: recentDaysKey)
    }

    @IBAction open func indentChanged(sender: NSTextField) {
        defaults.setValue(sender.stringValue, forKey: formatIndentKey)
    }

}
