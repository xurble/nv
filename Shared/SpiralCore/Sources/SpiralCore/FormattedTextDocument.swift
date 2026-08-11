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

import Foundation

public enum InlineTextAttribute: String, CaseIterable, Codable, Sendable {
    case bold
    case italic
    case underline
    case strikethrough
}

public struct InlineTextStyle: Equatable, Codable, Sendable {
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool
    public var strikethrough: Bool

    public init(
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        strikethrough: Bool = false
    ) {
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
    }

    public subscript(attribute: InlineTextAttribute) -> Bool {
        get {
            switch attribute {
            case .bold: bold
            case .italic: italic
            case .underline: underline
            case .strikethrough: strikethrough
            }
        }
        set {
            switch attribute {
            case .bold: bold = newValue
            case .italic: italic = newValue
            case .underline: underline = newValue
            case .strikethrough: strikethrough = newValue
            }
        }
    }
}

public struct FormattedTextRun: Equatable, Codable, Sendable {
    /// UTF-16 offsets, matching `NSTextView` and `UITextView` ranges.
    public let range: Range<Int>
    public let style: InlineTextStyle

    public init(range: Range<Int>, style: InlineTextStyle) {
        self.range = range
        self.style = style
    }
}

public enum FormattedTextDocumentError: Error, Equatable, Sendable {
    case unsupportedFormat(NoteFormat)
    case malformedRepresentation(NoteFormat)
    case invalidUTF16Range
    case structuralBoundaryEdit
    case unencodableText
}

public struct FormattedTextDocument: Equatable, Codable, Sendable {
    private enum SegmentKind: String, Codable, Sendable {
        case markup
        case text
        case lineBreak
    }

    private struct Segment: Equatable, Codable, Sendable {
        var kind: SegmentKind
        var source: String
        var text: String
        var style: InlineTextStyle

        static func markup(_ source: String) -> Segment {
            Segment(kind: .markup, source: source, text: "", style: InlineTextStyle())
        }

        static func text(_ text: String, source: String, style: InlineTextStyle) -> Segment {
            Segment(kind: .text, source: source, text: text, style: style)
        }

        static func lineBreak(_ source: String, style: InlineTextStyle) -> Segment {
            Segment(kind: .lineBreak, source: source, text: "\n", style: style)
        }
    }

    private enum SourceEncoding: String, Codable, Sendable {
        case utf8
        case windows1252
        case isoLatin1
    }

    public let format: NoteFormat
    private var sourceEncoding: SourceEncoding
    private var segments: [Segment]

    public init(data: Data, format: NoteFormat) throws {
        self.format = format
        switch format {
        case .plainText:
            throw FormattedTextDocumentError.unsupportedFormat(format)
        case .richText:
            guard let source = String(data: data, encoding: .isoLatin1),
                  source.hasPrefix("{\\rtf") else {
                throw FormattedTextDocumentError.malformedRepresentation(format)
            }
            sourceEncoding = .isoLatin1
            segments = try Self.parseRTF(source)
        case .html:
            let source: String
            if let value = String(data: data, encoding: .utf8) {
                source = value
                sourceEncoding = .utf8
            } else if let value = String(data: data, encoding: .windowsCP1252) {
                source = value
                sourceEncoding = .windows1252
            } else {
                throw FormattedTextDocumentError.malformedRepresentation(format)
            }
            guard source.range(of: "<[^>]+>", options: .regularExpression) != nil else {
                throw FormattedTextDocumentError.malformedRepresentation(format)
            }
            segments = Self.parseHTML(source)
        }
    }

    public var text: String {
        segments.reduce(into: "") { result, segment in result += segment.text }
    }

    public var runs: [FormattedTextRun] {
        var result: [FormattedTextRun] = []
        var location = 0
        for segment in segments where !segment.text.isEmpty {
            let length = (segment.text as NSString).length
            let range = location..<(location + length)
            if let last = result.last, last.style == segment.style, last.range.upperBound == range.lowerBound {
                result[result.count - 1] = FormattedTextRun(
                    range: last.range.lowerBound..<range.upperBound,
                    style: segment.style
                )
            } else {
                result.append(FormattedTextRun(range: range, style: segment.style))
            }
            location += length
        }
        return result
    }

    public func encodedData() throws -> Data {
        let source = segments.reduce(into: "") { result, segment in result += segment.source }
        switch sourceEncoding {
        case .utf8:
            return Data(source.utf8)
        case .windows1252:
            guard let data = source.data(using: .windowsCP1252) else {
                throw FormattedTextDocumentError.unencodableText
            }
            return data
        case .isoLatin1:
            guard let data = source.data(using: .isoLatin1) else {
                throw FormattedTextDocumentError.unencodableText
            }
            return data
        }
    }

    public mutating func replaceText(inUTF16 range: Range<Int>, with replacement: String) throws {
        let totalLength = (text as NSString).length
        guard range.lowerBound >= 0,
              range.upperBound >= range.lowerBound,
              range.upperBound <= totalLength else {
            throw FormattedTextDocumentError.invalidUTF16Range
        }

        if range.isEmpty {
            guard let target = insertionTarget(at: range.lowerBound) else {
                throw FormattedTextDocumentError.structuralBoundaryEdit
            }
            try replaceText(inSegmentAt: target.index, localRange: target.offset..<target.offset, with: replacement)
            return
        }

        var location = 0
        var edits: [(index: Int, range: Range<Int>)] = []
        for (index, segment) in segments.enumerated() {
            let length = (segment.text as NSString).length
            let segmentRange = location..<(location + length)
            let lower = max(range.lowerBound, segmentRange.lowerBound)
            let upper = min(range.upperBound, segmentRange.upperBound)
            if lower < upper {
                guard segment.kind == .text else {
                    throw FormattedTextDocumentError.structuralBoundaryEdit
                }
                edits.append((index, (lower - location)..<(upper - location)))
            }
            location += length
        }
        guard !edits.isEmpty else { throw FormattedTextDocumentError.structuralBoundaryEdit }

        for editIndex in edits.indices.reversed() {
            let edit = edits[editIndex]
            try replaceText(
                inSegmentAt: edit.index,
                localRange: edit.range,
                with: editIndex == edits.startIndex ? replacement : ""
            )
        }
    }

    public mutating func apply(_ attribute: InlineTextAttribute, toUTF16 range: Range<Int>) throws {
        let totalLength = (text as NSString).length
        guard !range.isEmpty,
              range.lowerBound >= 0,
              range.upperBound <= totalLength else {
            throw FormattedTextDocumentError.invalidUTF16Range
        }

        var location = 0
        var targets: [(index: Int, localRange: Range<Int>)] = []
        for (index, segment) in segments.enumerated() {
            let length = (segment.text as NSString).length
            let lower = max(range.lowerBound, location)
            let upper = min(range.upperBound, location + length)
            if lower < upper {
                guard segment.kind == .text else {
                    throw FormattedTextDocumentError.structuralBoundaryEdit
                }
                targets.append((index, (lower - location)..<(upper - location)))
            }
            location += length
        }
        guard !targets.isEmpty else { throw FormattedTextDocumentError.structuralBoundaryEdit }

        for target in targets.reversed() {
            let segment = segments[target.index]
            let nsText = segment.text as NSString
            let before = nsText.substring(with: NSRange(location: 0, length: target.localRange.lowerBound))
            let selected = nsText.substring(with: NSRange(
                location: target.localRange.lowerBound,
                length: target.localRange.count
            ))
            let after = nsText.substring(from: target.localRange.upperBound)
            var replacement: [Segment] = []
            if !before.isEmpty {
                replacement.append(.text(before, source: escape(before), style: segment.style))
            }
            var selectedStyle = segment.style
            selectedStyle[attribute] = true
            replacement.append(.markup(openingMarkup(for: attribute)))
            replacement.append(.text(selected, source: escape(selected), style: selectedStyle))
            replacement.append(.markup(closingMarkup(for: attribute)))
            if !after.isEmpty {
                replacement.append(.text(after, source: escape(after), style: segment.style))
            }
            segments.replaceSubrange(target.index...target.index, with: replacement)
        }
    }

    private func insertionTarget(at offset: Int) -> (index: Int, offset: Int)? {
        var location = 0
        var precedingText: (index: Int, offset: Int)?
        for (index, segment) in segments.enumerated() {
            let length = (segment.text as NSString).length
            if segment.kind == .text {
                if offset >= location, offset <= location + length {
                    return (index, offset - location)
                }
                if location + length <= offset { precedingText = (index, length) }
            } else if length > 0, offset > location, offset < location + length {
                return nil
            }
            location += length
        }
        return offset == location ? precedingText : nil
    }

    private mutating func replaceText(
        inSegmentAt index: Int,
        localRange: Range<Int>,
        with replacement: String
    ) throws {
        let segment = segments[index]
        let nsText = segment.text as NSString
        guard localRange.lowerBound >= 0, localRange.upperBound <= nsText.length else {
            throw FormattedTextDocumentError.invalidUTF16Range
        }
        let changed = nsText.replacingCharacters(
            in: NSRange(location: localRange.lowerBound, length: localRange.count),
            with: replacement
        )
        segments[index].text = changed
        segments[index].source = escape(changed)
    }

    private func escape(_ text: String) -> String {
        switch format {
        case .plainText: text
        case .richText: Self.escapeRTF(text)
        case .html: Self.escapeHTML(text)
        }
    }

    private func openingMarkup(for attribute: InlineTextAttribute) -> String {
        switch (format, attribute) {
        case (.richText, .bold): "{\\b "
        case (.richText, .italic): "{\\i "
        case (.richText, .underline): "{\\ul "
        case (.richText, .strikethrough): "{\\strike "
        case (.html, .bold): "<strong>"
        case (.html, .italic): "<em>"
        case (.html, .underline): "<u>"
        case (.html, .strikethrough): "<s>"
        case (.plainText, _): ""
        }
    }

    private func closingMarkup(for attribute: InlineTextAttribute) -> String {
        switch (format, attribute) {
        case (.richText, _): "}"
        case (.html, .bold): "</strong>"
        case (.html, .italic): "</em>"
        case (.html, .underline): "</u>"
        case (.html, .strikethrough): "</s>"
        case (.plainText, _): ""
        }
    }

    private struct RTFState {
        var style = InlineTextStyle()
        var skipped = false
    }

    private static func parseRTF(_ source: String) throws -> [Segment] {
        var result: [Segment] = []
        var state = RTFState()
        var stack: [RTFState] = []
        var index = source.startIndex
        var pendingHighSurrogate: UInt32?
        var pendingUnicodeSource = ""
        let destinations: Set<String> = [
            "fonttbl", "colortbl", "stylesheet", "info", "pict", "object",
            "header", "footer", "footnote", "generator", "datastore", "themedata"
        ]

        while index < source.endIndex {
            let character = source[index]
            if character == "{" {
                stack.append(state)
                result.append(.markup("{"))
                index = source.index(after: index)
                continue
            }
            if character == "}" {
                result.append(.markup("}"))
                state = stack.popLast() ?? RTFState()
                index = source.index(after: index)
                continue
            }
            if character != "\\" {
                let start = index
                while index < source.endIndex,
                      !["{", "}", "\\", "\r", "\n"].contains(source[index]) {
                    index = source.index(after: index)
                }
                if start == index {
                    let raw = String(character)
                    result.append(.markup(raw))
                    index = source.index(after: index)
                } else {
                    let raw = String(source[start..<index])
                    if state.skipped {
                        result.append(.markup(raw))
                    } else {
                        result.append(.text(decodeRTFPlainText(raw), source: raw, style: state.style))
                    }
                }
                continue
            }

            let controlStart = index
            index = source.index(after: index)
            guard index < source.endIndex else {
                result.append(.markup("\\"))
                break
            }
            let escaped = source[index]
            if escaped == "\\" || escaped == "{" || escaped == "}" {
                index = source.index(after: index)
                let raw = String(source[controlStart..<index])
                if state.skipped { result.append(.markup(raw)) }
                else { result.append(.text(String(escaped), source: raw, style: state.style)) }
                continue
            }
            if escaped == "\r" || escaped == "\n" {
                if escaped == "\r" {
                    index = source.index(after: index)
                    if index < source.endIndex, source[index] == "\n" { index = source.index(after: index) }
                } else {
                    index = source.index(after: index)
                }
                let raw = String(source[controlStart..<index])
                if state.skipped { result.append(.markup(raw)) }
                else { result.append(.lineBreak(raw, style: state.style)) }
                continue
            }
            if escaped == "'" {
                index = source.index(after: index)
                let hexStart = index
                index = source.index(index, offsetBy: 2, limitedBy: source.endIndex) ?? source.endIndex
                let raw = String(source[controlStart..<index])
                if state.skipped {
                    result.append(.markup(raw))
                } else if let byte = UInt8(source[hexStart..<index], radix: 16) {
                    let decoded = String(data: Data([byte]), encoding: .windowsCP1252) ?? "�"
                    result.append(.text(decoded, source: raw, style: state.style))
                }
                continue
            }
            if escaped == "*" {
                index = source.index(after: index)
                state.skipped = true
                result.append(.markup(String(source[controlStart..<index])))
                continue
            }

            let wordStart = index
            while index < source.endIndex, source[index].isLetter { index = source.index(after: index) }
            let word = String(source[wordStart..<index]).lowercased()
            var sign = 1
            if index < source.endIndex, source[index] == "-" {
                sign = -1
                index = source.index(after: index)
            }
            let numberStart = index
            while index < source.endIndex, source[index].isNumber { index = source.index(after: index) }
            let number = Int(source[numberStart..<index]).map { $0 * sign }
            if index < source.endIndex, source[index] == " " { index = source.index(after: index) }

            if word == "u", index < source.endIndex {
                index = source.index(after: index) // Retain the one-character ANSI fallback.
            }
            let raw = String(source[controlStart..<index])
            if destinations.contains(word) { state.skipped = true }
            guard !state.skipped else {
                result.append(.markup(raw))
                continue
            }

            switch word {
            case "b": state.style.bold = number != 0
            case "i": state.style.italic = number != 0
            case "ul": state.style.underline = number != 0
            case "ulnone": state.style.underline = false
            case "strike": state.style.strikethrough = number != 0
            case "par", "line":
                result.append(.lineBreak(raw, style: state.style))
                continue
            case "tab":
                result.append(.text("\t", source: raw, style: state.style))
                continue
            case "u":
                if let number {
                    let codeUnit = UInt32(number >= 0 ? number : number + 65_536)
                    if (0xD800...0xDBFF).contains(codeUnit) {
                        pendingHighSurrogate = codeUnit
                        pendingUnicodeSource = raw
                        continue
                    }
                    if (0xDC00...0xDFFF).contains(codeUnit), let high = pendingHighSurrogate {
                        let scalarValue = 0x10000 + ((high - 0xD800) << 10) + (codeUnit - 0xDC00)
                        if let scalar = UnicodeScalar(scalarValue) {
                            result.append(.text(String(scalar), source: pendingUnicodeSource + raw, style: state.style))
                        }
                        pendingHighSurrogate = nil
                        pendingUnicodeSource = ""
                        continue
                    }
                    if let scalar = UnicodeScalar(codeUnit) {
                        result.append(.text(String(scalar), source: raw, style: state.style))
                        continue
                    }
                }
            default: break
            }
            result.append(.markup(raw))
        }
        return result
    }

    private static func parseHTML(_ source: String) -> [Segment] {
        var result: [Segment] = []
        var index = source.startIndex
        var style = InlineTextStyle()
        var styleStack: [(String, InlineTextStyle)] = []
        var hiddenDepth = 0
        let blockTags: Set<String> = ["p", "div", "li", "h1", "h2", "h3", "h4", "h5", "h6"]

        while index < source.endIndex {
            guard source[index] == "<" else {
                let start = index
                while index < source.endIndex, source[index] != "<" { index = source.index(after: index) }
                let raw = String(source[start..<index])
                if hiddenDepth > 0 || raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result.append(.markup(raw))
                } else {
                    result.append(.text(decodeHTMLEntities(raw), source: raw, style: style))
                }
                continue
            }

            let tagStart = index
            var quote: Character?
            while index < source.endIndex {
                let character = source[index]
                index = source.index(after: index)
                if character == "\"" || character == "'" {
                    if quote == character { quote = nil }
                    else if quote == nil { quote = character }
                } else if character == ">", quote == nil {
                    break
                }
            }
            let raw = String(source[tagStart..<index])
            let descriptor = htmlTagDescriptor(raw)
            let tag = descriptor.name
            let priorStyle = style

            if descriptor.isClosing {
                if tag == "head" || tag == "script" || tag == "style" { hiddenDepth = max(0, hiddenDepth - 1) }
                if let match = styleStack.lastIndex(where: { $0.0 == tag }) {
                    style = styleStack[match].1
                    styleStack.removeSubrange(match...)
                }
                if hiddenDepth == 0, blockTags.contains(tag) {
                    result.append(.lineBreak(raw, style: priorStyle))
                } else {
                    result.append(.markup(raw))
                }
            } else {
                if tag == "head" || tag == "script" || tag == "style" { hiddenDepth += 1 }
                if ["strong", "b", "em", "i", "u", "s", "strike", "del"].contains(tag) {
                    styleStack.append((tag, style))
                    switch tag {
                    case "strong", "b": style.bold = true
                    case "em", "i": style.italic = true
                    case "u": style.underline = true
                    case "s", "strike", "del": style.strikethrough = true
                    default: break
                    }
                }
                if hiddenDepth == 0, tag == "br" {
                    result.append(.lineBreak(raw, style: style))
                } else {
                    result.append(.markup(raw))
                }
            }
        }

        if let firstVisible = result.firstIndex(where: { !$0.text.isEmpty }),
           result[firstVisible].kind == .lineBreak {
            result[firstVisible].kind = .markup
            result[firstVisible].text = ""
        }
        if let lastVisible = result.lastIndex(where: { !$0.text.isEmpty }),
           result[lastVisible].kind == .lineBreak {
            result[lastVisible].kind = .markup
            result[lastVisible].text = ""
        }
        return result
    }

    private static func htmlTagDescriptor(_ raw: String) -> (name: String, isClosing: Bool) {
        var value = raw.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
        let isClosing = value.hasPrefix("/")
        if isClosing { value = value.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines) }
        let name = value.prefix { $0.isLetter || $0.isNumber }.lowercased()
        return (name, isClosing)
    }

    private static func decodeRTFPlainText(_ raw: String) -> String {
        guard let bytes = raw.data(using: .isoLatin1) else { return raw }
        return String(data: bytes, encoding: .windowsCP1252) ?? raw
    }

    private static func decodeHTMLEntities(_ source: String) -> String {
        var result = ""
        var index = source.startIndex
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}"]
        while index < source.endIndex {
            guard source[index] == "&",
                  let semicolon = source[index...].firstIndex(of: ";") else {
                result.append(source[index])
                index = source.index(after: index)
                continue
            }
            let entityStart = source.index(after: index)
            let entity = String(source[entityStart..<semicolon])
            let decoded: String?
            if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                decoded = UInt32(entity.dropFirst(2), radix: 16).flatMap(UnicodeScalar.init).map(String.init)
            } else if entity.hasPrefix("#") {
                decoded = UInt32(entity.dropFirst()).flatMap(UnicodeScalar.init).map(String.init)
            } else {
                decoded = named[entity.lowercased()]
            }
            if let decoded {
                result += decoded
                index = source.index(after: semicolon)
            } else {
                result.append(source[index])
                index = source.index(after: index)
            }
        }
        return result
    }

    private static func escapeRTF(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 10: result += "\\par\n"
            case 9: result += "\\tab "
            case 92: result += "\\\\"
            case 123: result += "\\{"
            case 125: result += "\\}"
            case 0...127: result.unicodeScalars.append(scalar)
            case 0x10000...0x10FFFF:
                let value = scalar.value - 0x10000
                result += "\\u\(signedRTFCodeUnit(0xD800 + (value >> 10)))?"
                result += "\\u\(signedRTFCodeUnit(0xDC00 + (value & 0x3FF)))?"
            default:
                result += "\\u\(signedRTFCodeUnit(scalar.value))?"
            }
        }
        return result
    }

    private static func signedRTFCodeUnit(_ value: UInt32) -> Int {
        value <= 32_767 ? Int(value) : Int(value) - 65_536
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
