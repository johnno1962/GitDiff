//
//  LNProviderTests.swift
//  LNProviderTests
//
//  Created by John Holdsworth on 31/03/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//

import XCTest
@testable import LNProvider

class LNProviderTests: XCTestCase {

    var service: LNExtensionClient!

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
        // service = LNExtensionClient(serviceName: "com.johnholdsworth.GitBlameRelay", delegate: nil)
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testBlame() {
        if let service = service {
            // This is an example of a functional test case.
            // Use XCTAssert and related functions to verify your tests produce the correct results.
            service.requestHighlights(forFile: #file)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.0))
            if let highlights = service[(#file)] {
                let element = highlights[(#line)]
                XCTAssertNotNil(element, "Got blame")
                NSLog("element: \(String(describing: element))")
            } else {
                XCTFail("No highlights")
            }
        }
    }

    func testSerializing() {
        let reference = LNFileHighlights()
        for i in stride(from: 1, to: 100, by: 10) {
            let element = LNHighlightElement()
            element.start = i
            element.color = NSColor(string: ".1 .3 .3 .4")
            element.text = "\(i)"
            element.range = "\(i) \(i + 1)"
            reference[i] = element
            for j in 1 ... 9 {
                reference[i + j] = element
            }
        }

        let highlights = LNFileHighlights(data: reference.jsonData(), service:"none")!
        XCTAssertTrue(highlights[1] == reference[1], "basic")
        XCTAssertTrue(highlights[1] != reference[11], "other")
        XCTAssertTrue(highlights[1] === highlights[2], "alias")
    }

    func testDiff() {
        let path = Bundle(for: type(of: self)).path(forResource: "example_diff", ofType: "txt")
        let sequence = FileGenerator(path: path!)!.lineSequence
        let highlights = DiffProcessor().generateHighlights(sequence: sequence, defaults: DefaultManager())
        print(String(data: highlights.jsonData(), encoding: .utf8)!)
        highlights.foreachHighlightRange {
            (range, element) in
            print(range, element)
        }
    }

    func testFormat() {
        FormatImpl(connection: nil)?.requestHighlights(forFile: #file, callback: {
            json, _ in
            if let json = json {
                print(String(data: json, encoding: .utf8)!)
            }
        })
    }

    func testAttributed() {
        let element = LNHighlightElement()
        let string = NSMutableAttributedString(string: "hello world")
        string.addAttributes([NSFontAttributeName: NSFont(name: "Arial", size: 10)!], range: NSMakeRange(0, 4))
        element.setAttributedText(string)
        print("\(String(describing: element.attributedText()))")
    }

    func testPerformanceExample() {
        // This is an example of a performance test case.
        measure {
            // Put the code you want to measure the time of here.
        }
    }
    
}
