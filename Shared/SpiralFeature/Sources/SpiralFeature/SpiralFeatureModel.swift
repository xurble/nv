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
    along with Notational Velocity.  If not, see <http://www.gnu.org/licenses/>. */

import Foundation
import SpiralCore

public enum NoteListSort: String, CaseIterable, Codable, Sendable {
    case title
    case modified

    public var label: String {
        switch self {
        case .title: "Title"
        case .modified: "Recently Edited"
        }
    }
}

public struct SpiralFeatureSettings: Equatable, Codable, Sendable {
    public var sort: NoteListSort
    public var showPreviews: Bool

    public init(sort: NoteListSort = .modified, showPreviews: Bool = true) {
        self.sort = sort
        self.showPreviews = showPreviews
    }
}

public enum CollectionAvailability: Equatable, Sendable {
    case available
    case downloading(progress: Double?)
    case unavailable(message: String)
}

public enum SpiralFeaturePhase: Equatable, Sendable {
    case loading
    case empty
    case ready
    case downloading(progress: Double?)
    case conflict(count: Int)
    case failure(String)
}

@MainActor
public final class SpiralFeatureModel: ObservableObject {
    @Published public private(set) var notes: [Note] = []
    @Published public var selectedNoteID: NoteID?
    @Published public var searchText = ""
    @Published public private(set) var conflicts: [NoteConflict] = []
    @Published public private(set) var phase: SpiralFeaturePhase = .loading
    @Published public var settings: SpiralFeatureSettings

    private let store: any NoteStore
    private var availability: CollectionAvailability = .available

    public init(
        store: any NoteStore,
        settings: SpiralFeatureSettings = SpiralFeatureSettings()
    ) {
        self.store = store
        self.settings = settings
    }

    public var selectedNote: Note? {
        guard let selectedNoteID else { return nil }
        return notes.first { $0.id == selectedNoteID }
    }

    public var visibleNotes: [Note] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [Note]
        if query.isEmpty {
            filtered = notes
        } else {
            filtered = notes.filter { note in
                note.title.localizedCaseInsensitiveContains(query)
                    || note.content.text.localizedCaseInsensitiveContains(query)
                    || note.tags.contains { $0.localizedCaseInsensitiveContains(query) }
            }
        }
        return filtered.sorted(by: noteSort)
    }

    public func load() async {
        phase = .loading
        do {
            notes = try await store.allNotes()
            conflicts = await store.conflicts()
            if let selectedNoteID, !notes.contains(where: { $0.id == selectedNoteID }) {
                self.selectedNoteID = nil
            }
            if self.selectedNoteID == nil {
                self.selectedNoteID = visibleNotes.first?.id
            }
            updatePhase()
        } catch {
            phase = .failure(Self.message(for: error))
        }
    }

    @discardableResult
    public func createNote() async -> Note? {
        let note = Note(
            title: uniqueUntitledTitle(),
            content: NoteContent(format: .plainText, text: "")
        )
        do {
            let created = try await store.create(note)
            notes.append(created)
            selectedNoteID = created.id
            searchText = ""
            updatePhase()
            return created
        } catch {
            phase = .failure(Self.message(for: error))
            return nil
        }
    }

    public func renameSelected(to title: String) async {
        await mutateSelected { note in
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            note.title = trimmed.isEmpty ? "Untitled" : trimmed
        }
    }

    public func updateSelectedContent(_ text: String) async {
        await mutateSelected { note in
            note.content.text = text
            note.modifiedAt = Date()
        }
    }

    public func setSelectedTags(from text: String) async {
        let tags = text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        let uniqueTags = tags.filter { seen.insert($0.localizedLowercase).inserted }
        await mutateSelected { $0.tags = uniqueTags }
    }

    public func toggleSelectedPin() async {
        await mutateSelected { $0.isPinned.toggle() }
    }

    public func deleteSelected() async {
        guard let selectedNoteID else { return }
        do {
            try await store.delete(id: selectedNoteID)
            notes.removeAll { $0.id == selectedNoteID }
            conflicts.removeAll { $0.noteID == selectedNoteID }
            self.selectedNoteID = visibleNotes.first?.id
            updatePhase()
        } catch {
            phase = .failure(Self.message(for: error))
        }
    }

    public func restoreSelection(_ rawValue: String?) {
        guard let rawValue, let uuid = UUID(uuidString: rawValue) else { return }
        let candidate = NoteID(uuid)
        if notes.contains(where: { $0.id == candidate }) {
            selectedNoteID = candidate
        }
    }

    public func setAvailability(_ availability: CollectionAvailability) {
        self.availability = availability
        updatePhase()
    }

    private func mutateSelected(_ mutation: (inout Note) -> Void) async {
        guard let selectedNoteID,
              let index = notes.firstIndex(where: { $0.id == selectedNoteID }) else { return }
        var changed = notes[index]
        mutation(&changed)
        do {
            try await store.update(changed)
            notes[index] = changed
            updatePhase()
        } catch {
            phase = .failure(Self.message(for: error))
        }
    }

    private func updatePhase() {
        switch availability {
        case .available:
            if !conflicts.isEmpty {
                phase = .conflict(count: conflicts.count)
            } else {
                phase = notes.isEmpty ? .empty : .ready
            }
        case let .downloading(progress):
            phase = .downloading(progress: progress)
        case let .unavailable(message):
            phase = .failure(message)
        }
    }

    private func uniqueUntitledTitle() -> String {
        let titles = Set(notes.map { $0.title.localizedLowercase })
        if !titles.contains("untitled") { return "Untitled" }
        var number = 2
        while titles.contains("untitled \(number)") { number += 1 }
        return "Untitled \(number)"
    }

    private func noteSort(_ lhs: Note, _ rhs: Note) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
        switch settings.sort {
        case .title:
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        case .modified:
            if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private static func message(for error: Error) -> String {
        let description = String(describing: error)
        return description.isEmpty ? "The collection could not be opened." : description
    }
}
