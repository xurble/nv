import Foundation

public enum NoteFileCodecError: Error, Equatable, Sendable {
    case unsupportedFormat(String)
    case undecodableText
    case malformedRichText
    case malformedHTML
}

public struct NoteFileCodec: Sendable {
    public init() {}

    public func read(from url: URL) throws -> NoteContent {
        guard let format = NoteFormat.format(forPathExtension: url.pathExtension) else {
            throw NoteFileCodecError.unsupportedFormat(url.pathExtension)
        }
        return try decode(Data(contentsOf: url), as: format)
    }

    public func decode(_ data: Data, as format: NoteFormat) throws -> NoteContent {
        let text: String
        switch format {
        case .plainText:
            guard let decoded = decodePlainText(data) else {
                throw NoteFileCodecError.undecodableText
            }
            text = decoded
        case .richText:
            text = try decodeRTF(data)
        case .html:
            text = try decodeHTML(data)
        }
        return NoteContent(format: format, text: text, originalData: data, originalText: text)
    }

    public func encode(_ content: NoteContent) throws -> Data {
        if content.text == content.originalText, let originalData = content.originalData {
            return originalData
        }
        switch content.format {
        case .plainText:
            return Data(content.text.utf8)
        case .richText:
            return Data(deterministicRTF(content.text).utf8)
        case .html:
            return Data(deterministicHTML(content.text).utf8)
        }
    }

    public func write(_ content: NoteContent, to url: URL) throws {
        try encode(content).write(to: url, options: .atomic)
    }

    private func decodePlainText(_ data: Data) -> String? {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        if data.starts(with: [0xFF, 0xFE]) {
            return String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        }
        if data.starts(with: [0xFE, 0xFF]) {
            return String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        }
        if let string = String(data: data, encoding: .utf8) { return string }
        if data.contains(where: { (0x80...0x9F).contains($0) }) {
            let likelyWindowsPunctuation: Set<UInt8> = [0x91, 0x92, 0x93, 0x94, 0x96, 0x97]
            let encoding: String.Encoding = data.contains(where: likelyWindowsPunctuation.contains)
                ? .windowsCP1252 : .macOSRoman
            if let string = String(data: data, encoding: encoding) { return string }
        }
        if let string = String(data: data, encoding: .isoLatin1) { return string }
        return nil
    }

    /// A deliberately small, platform-neutral RTF text reader. It retains the
    /// source bytes for lossless reopening; this parser extracts searchable and
    /// editable text without importing AppKit into the shared package.
    private func decodeRTF(_ data: Data) throws -> String {
        guard let source = String(data: data, encoding: .isoLatin1),
              source.hasPrefix("{\\rtf") else {
            throw NoteFileCodecError.malformedRichText
        }
        var output = ""
        var index = source.startIndex
        var skippedDestinationDepth: Int?
        var pendingHighSurrogate: UInt32?
        var depth = 0

        while index < source.endIndex {
            let character = source[index]
            if character == "{" {
                depth += 1
                index = source.index(after: index)
                continue
            }
            if character == "}" {
                if skippedDestinationDepth == depth { skippedDestinationDepth = nil }
                depth -= 1
                index = source.index(after: index)
                continue
            }
            if character != "\\" {
                if skippedDestinationDepth == nil, character != "\n", character != "\r" {
                    output.append(character)
                }
                index = source.index(after: index)
                continue
            }

            let slash = index
            index = source.index(after: index)
            guard index < source.endIndex else { break }
            let escaped = source[index]
            if escaped == "\\" || escaped == "{" || escaped == "}" {
                if skippedDestinationDepth == nil { output.append(escaped) }
                index = source.index(after: index)
                continue
            }
            if escaped == "\n" || escaped == "\r" {
                if skippedDestinationDepth == nil { output.append("\n") }
                index = source.index(after: index)
                continue
            }
            if escaped == "'" {
                let start = source.index(after: index)
                let end = source.index(start, offsetBy: 2, limitedBy: source.endIndex) ?? source.endIndex
                if end <= source.endIndex, let byte = UInt8(source[start..<end], radix: 16), skippedDestinationDepth == nil {
                    output.append(String(data: Data([byte]), encoding: .windowsCP1252) ?? "�")
                }
                index = end
                continue
            }
            if escaped == "*" {
                skippedDestinationDepth = depth
                index = source.index(after: index)
                continue
            }

            let wordStart = index
            while index < source.endIndex, source[index].isLetter {
                index = source.index(after: index)
            }
            let word = String(source[wordStart..<index])
            var sign = 1
            if index < source.endIndex, source[index] == "-" {
                sign = -1
                index = source.index(after: index)
            }
            let numberStart = index
            while index < source.endIndex, source[index].isNumber {
                index = source.index(after: index)
            }
            let number = Int(source[numberStart..<index]).map { $0 * sign }
            if index < source.endIndex, source[index] == " " { index = source.index(after: index) }

            guard skippedDestinationDepth == nil else { continue }
            switch word {
            case "par", "line": output.append("\n")
            case "tab": output.append("\t")
            case "u":
                if let number {
                    let codeUnit = UInt32(number >= 0 ? number : number + 65_536)
                    if (0xD800...0xDBFF).contains(codeUnit) {
                        pendingHighSurrogate = codeUnit
                    } else if (0xDC00...0xDFFF).contains(codeUnit), let high = pendingHighSurrogate {
                        let scalarValue = 0x10000 + ((high - 0xD800) << 10) + (codeUnit - 0xDC00)
                        if let scalar = UnicodeScalar(scalarValue) { output.unicodeScalars.append(scalar) }
                        pendingHighSurrogate = nil
                    } else if let scalar = UnicodeScalar(codeUnit) {
                        pendingHighSurrogate = nil
                        output.unicodeScalars.append(scalar)
                    }
                    if index < source.endIndex { index = source.index(after: index) }
                }
            case "fonttbl", "colortbl", "stylesheet", "info", "pict", "object":
                skippedDestinationDepth = depth
            default:
                if word.isEmpty { index = source.index(after: slash) }
            }
        }
        return output.trimmingCharacters(in: .newlines)
    }

    private func decodeHTML(_ data: Data) throws -> String {
        guard let source = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .windowsCP1252) else {
            throw NoteFileCodecError.malformedHTML
        }
        var result = source
        result = result.replacingOccurrences(
            of: "(?is)<(script|style)[^>]*>.*?</\\1>",
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: ">\\s+<",
            with: "><",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "(?i)<(br\\s*/?|/p|/div|/li|/h[1-6])>",
            with: "\n",
            options: .regularExpression
        )
        result = result.replacingOccurrences(of: "(?s)<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'"]
        for (entity, value) in entities { result = result.replacingOccurrences(of: entity, with: value) }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func deterministicRTF(_ text: String) -> String {
        var body = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 10: body += "\\par\n"
            case 9: body += "\\tab "
            case 92: body += "\\\\"
            case 123: body += "\\{"
            case 125: body += "\\}"
            case 0...127: body.unicodeScalars.append(scalar)
            case 0x10000...0x10FFFF:
                let value = scalar.value - 0x10000
                let high = 0xD800 + (value >> 10)
                let low = 0xDC00 + (value & 0x3FF)
                body += "\\u\(signedRTFCodeUnit(high))?\\u\(signedRTFCodeUnit(low))?"
            default:
                body += "\\u\(signedRTFCodeUnit(scalar.value))?"
            }
        }
        return "{\\rtf1\\ansi\\ansicpg1252\\uc1\n\(body)}"
    }

    private func signedRTFCodeUnit(_ value: UInt32) -> Int {
        value <= 32_767 ? Int(value) : Int(value) - 65_536
    }

    private func deterministicHTML(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "<p>\($0.isEmpty ? "<br>" : String($0))</p>" }
            .joined(separator: "\n")
        return "<!doctype html>\n<html><head><meta charset=\"utf-8\"><title></title></head><body>\n\(escaped)\n</body></html>\n"
    }
}
