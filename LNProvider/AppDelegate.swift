//
//  AppDelegate.swift
//  LNProvider
//
//  Created by John Holdsworth on 31/03/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: NSWindow!
    @IBOutlet var defaults: DefaultManager!

    @IBOutlet var formatChecked: NSButton!
    @IBOutlet var gitDiffChecked: NSButton!
    @IBOutlet var gitBlameChecked: NSButton!
    @IBOutlet var inferChecked: NSButton!

    var services = [LNExtensionClient]()
    private var statusItem: NSStatusItem!

    lazy var buttonMap: [NSButton: String] = [
        self.formatChecked: "com.johnholdsworth.FormatRelay",
        self.gitDiffChecked: "com.johnholdsworth.GitDiffRelay",
        self.gitBlameChecked: "com.johnholdsworth.GitBlameRelay",
        self.inferChecked: "com.johnholdsworth.InferRelay",
    ]

    func applicationDidFinishLaunching(_: Notification) {
        startServiceAndRegister(checkButton: formatChecked)
        startServiceAndRegister(checkButton: gitDiffChecked)
        startServiceAndRegister(checkButton: gitBlameChecked)
        startServiceAndRegister(checkButton: inferChecked)
        let statusBar = NSStatusBar.system()
        statusItem = statusBar.statusItem(withLength: statusBar.thickness)
        statusItem.toolTip = "GitDiff Preferences"
        statusItem.highlightMode = true
        statusItem.target = self
        statusItem.action = #selector(show(sender:))
        statusItem.isEnabled = true
        statusItem.title = ""
        setMenuIcon(tiffName: "icon_16x16")
        NSColorPanel.shared().showsAlpha = true
        window.appearance = NSAppearance(named: NSAppearanceNameVibrantDark)
    }

    func setMenuIcon(tiffName: String) {
        if let path = Bundle.main.path(forResource: tiffName, ofType: "tiff"),
            let image = NSImage(contentsOfFile: path) {
            image.isTemplate = true
            statusItem.image = image
            statusItem.alternateImage = statusItem.image
        }
    }

    @IBAction func show(sender: Any) {
        window.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    func startServiceAndRegister(checkButton: NSButton) {
        if checkButton.state == NSOnState, let serviceName = buttonMap[checkButton] {
            services.append(LNExtensionClient(serviceName: serviceName, delegate: nil))
        }
    }

    @IBAction func serviceDidChange(checkButton: NSButton) {
        if checkButton.state == NSOnState {
            startServiceAndRegister(checkButton: checkButton)
        } else if let serviceName = buttonMap[checkButton] {
            services.first(where: { $0.serviceName == serviceName })?.deregister()
            services = services.filter { $0.serviceName != serviceName }
        }
    }

    func applicationWillTerminate(_: Notification) {
        _ = services.map { $0.deregister() }
    }

}
