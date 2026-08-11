/*Copyright (c) 2026 Gareth Simpson and Zachary Schneirov. All rights reserved.
    This file is part of Spiral, a fork of Notational Velocity.

    Spiral is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Spiral is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Spiral.  If not, see <http://www.gnu.org/licenses/>. */

import AppKit
import Foundation
import XCTest

final class Phase1FormatTests: XCTestCase {
    private struct EncodingFixture: Decodable {
        let name: String
        let encoding: UInt
        let text: String
        let hex: String
    }

    private var fixturesURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
    }

    func testGoldenPlainTextEncodingsLoadAndSaveByteForByte() throws {
        let data = try Data(contentsOf: fixturesURL.appendingPathComponent("note-encodings.json"))
        let fixtures = try JSONDecoder().decode([EncodingFixture].self, from: data)

        for fixture in fixtures {
            let bytes = try XCTUnwrap(Data(hexadecimal: fixture.hex), fixture.name)
            let encoding = String.Encoding(rawValue: fixture.encoding)
            XCTAssertEqual(String(data: bytes, encoding: encoding), fixture.text, fixture.name)
            XCTAssertEqual(fixture.text.data(using: encoding), bytes, fixture.name)
        }
    }

    func testEveryEncodingOfferedByLegacyEncodingManagerRoundTripsASCII() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Apps/macOS/Sources/EncodingsManager.m")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let rawValues = try legacyEncodingRawValues(from: source)
        XCTAssertGreaterThan(rawValues.count, 15, "The test must continue to cover the complete legacy menu")

        for rawValue in rawValues {
            let encoding = String.Encoding(rawValue: rawValue)
            let bytes = try XCTUnwrap("ASCII note".data(using: encoding), "encoding \(rawValue)")
            XCTAssertEqual(String(data: bytes, encoding: encoding), "ASCII note", "encoding \(rawValue)")
        }
    }

    func testTXTFixtureImportsAndExportsLosslessly() throws {
        let source = fixturesURL.appendingPathComponent("plain-note.txt")
        let text = try String(contentsOf: source, encoding: .utf8)
        let exported = try XCTUnwrap(text.data(using: .utf8))
        XCTAssertEqual(exported, try Data(contentsOf: source))
    }

    func testRTFFixtureImportsExportsAndRetainsAuthoredFormatting() throws {
        let source = try Data(contentsOf: fixturesURL.appendingPathComponent("rich-note.rtf"))
        let note = try NSAttributedString(
            data: source,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        XCTAssertTrue(note.string.contains("Rich title"))
        let font = try XCTUnwrap(note.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))

        let exported = try note.data(
            from: NSRange(location: 0, length: note.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let reopened = try NSAttributedString(
            data: exported,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        XCTAssertEqual(reopened.string, note.string)
    }

    func testHTMLFixtureImportsAndExportsTextWithoutAttachments() throws {
        let source = try Data(contentsOf: fixturesURL.appendingPathComponent("html-note.html"))
        let note = try NSAttributedString(
            data: source,
            options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        )
        XCTAssertTrue(note.string.contains("HTML title"))
        XCTAssertNil(note.attribute(.attachment, at: 0, effectiveRange: nil))

        let exported = try note.data(
            from: NSRange(location: 0, length: note.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
        )
        let reopened = try NSAttributedString(
            data: exported,
            options: [.documentType: NSAttributedString.DocumentType.html],
            documentAttributes: nil
        )
        XCTAssertEqual(reopened.string.trimmingCharacters(in: .whitespacesAndNewlines),
                       note.string.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func testHistoricalSyncMetadataArchiveLoadsWithoutRewritingOrStartingAService() throws {
        let archiveURL = fixturesURL.appendingPathComponent("historical-sync-archive.plist")
        let before = try Data(contentsOf: archiveURL)
        let object = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: before, format: nil) as? [String: Any]
        )
        let notes = try XCTUnwrap(object["notes"] as? [[String: Any]])
        let metadata = try XCTUnwrap(notes.first?["syncServicesMD"] as? [String: [String: Any]])

        XCTAssertEqual(metadata["Simplenote"]?["key"] as? String, "historic-remote-identifier")
        XCTAssertEqual(metadata["Simplenote"]?["version"] as? Int, 7)
        XCTAssertEqual(try Data(contentsOf: archiveURL), before)
        XCTAssertNil(ProcessInfo.processInfo.environment["SPIRAL_TEST_REMOTE_SERVICE_STARTED"])
    }

    private func legacyEncodingRawValues(from source: String) throws -> [UInt] {
        let block = try XCTUnwrap(source.range(of: "static const NSStringEncoding AllowedEncodings[]"))
        let tail = source[block.lowerBound...]
        let end = try XCTUnwrap(tail.range(of: "};"))
        let declarations = String(tail[..<end.upperBound])

        let named: [String: UInt] = [
            "NSASCIIStringEncoding": String.Encoding.ascii.rawValue,
            "NSNEXTSTEPStringEncoding": String.Encoding.nextstep.rawValue,
            "NSJapaneseEUCStringEncoding": String.Encoding.japaneseEUC.rawValue,
            "NSUTF8StringEncoding": String.Encoding.utf8.rawValue,
            "NSISOLatin1StringEncoding": String.Encoding.isoLatin1.rawValue,
            "NSSymbolStringEncoding": String.Encoding.symbol.rawValue,
            "NSNonLossyASCIIStringEncoding": String.Encoding.nonLossyASCII.rawValue,
            "NSShiftJISStringEncoding": String.Encoding.shiftJIS.rawValue,
            "NSISOLatin2StringEncoding": String.Encoding.isoLatin2.rawValue,
            "NSUnicodeStringEncoding": String.Encoding.unicode.rawValue,
            "NSWindowsCP1251StringEncoding": String.Encoding.windowsCP1251.rawValue,
            "NSWindowsCP1252StringEncoding": String.Encoding.windowsCP1252.rawValue,
            "NSWindowsCP1253StringEncoding": String.Encoding.windowsCP1253.rawValue,
            "NSWindowsCP1254StringEncoding": String.Encoding.windowsCP1254.rawValue,
            "NSWindowsCP1250StringEncoding": String.Encoding.windowsCP1250.rawValue,
            "NSISO2022JPStringEncoding": String.Encoding.iso2022JP.rawValue,
            "NSMacOSRomanStringEncoding": String.Encoding.macOSRoman.rawValue
        ]

        var values: [UInt] = []
        for rawLine in declarations.split(separator: "\n") {
            let line = rawLine.split(separator: "//", maxSplits: 1).first.map(String.init) ?? ""
            if line.contains("-1") || line.contains("AllowedEncodings") || line.contains("};") { continue }
            if let hexRange = line.range(of: #"0x[0-9A-Fa-f]+"#, options: .regularExpression),
               let value = UInt(line[hexRange].dropFirst(2), radix: 16) {
                values.append(value)
                continue
            }
            if let entry = named.first(where: { line.contains($0.key) }) {
                values.append(entry.value)
            }
        }
        return Array(Set(values)).sorted()
    }
}

private extension Data {
    init?(hexadecimal: String) {
        guard hexadecimal.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hexadecimal.count / 2)
        var index = hexadecimal.startIndex
        while index < hexadecimal.endIndex {
            let next = hexadecimal.index(index, offsetBy: 2)
            guard let byte = UInt8(hexadecimal[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }
}
