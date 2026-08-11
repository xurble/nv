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

public enum NoteFileCodecError: Error, Equatable, Sendable {
    case unsupportedFormat(String)
    case undecodableText
    case malformedRichText
    case malformedHTML
    case formatPreservingEditRequired(NoteFormat)
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
            let document: FormattedTextDocument
            do {
                document = try FormattedTextDocument(data: data, format: format)
            } catch {
                throw NoteFileCodecError.malformedRichText
            }
            return NoteContent(
                format: format,
                text: document.text,
                originalData: data,
                originalText: document.text,
                formattedDocument: document
            )
        case .html:
            let document: FormattedTextDocument
            do {
                document = try FormattedTextDocument(data: data, format: format)
            } catch {
                throw NoteFileCodecError.malformedHTML
            }
            return NoteContent(
                format: format,
                text: document.text,
                originalData: data,
                originalText: document.text,
                formattedDocument: document
            )
        }
        return NoteContent(format: format, text: text, originalData: data, originalText: text)
    }

    public func encode(_ content: NoteContent) throws -> Data {
        if let document = content.formattedDocument {
            guard document.format == content.format, document.text == content.text else {
                throw NoteFileCodecError.formatPreservingEditRequired(content.format)
            }
            return try document.encodedData()
        }
        if content.text == content.originalText, let originalData = content.originalData {
            return originalData
        }
        if content.originalData != nil,
           content.originalText != nil,
           content.format != .plainText {
            throw NoteFileCodecError.formatPreservingEditRequired(content.format)
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
