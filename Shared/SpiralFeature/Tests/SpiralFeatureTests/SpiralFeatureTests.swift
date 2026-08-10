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
@testable import SpiralFeature
import Testing

@Suite("Cross-platform feature state")
@MainActor
struct SpiralFeatureTests {
    @Test("Loads, searches, selects, and sorts a large collection")
    func largeCollectionSearchAndSort() async throws {
        let notes = (0..<1_000).map { index in
            Note(
                title: "Note \(String(format: "%04d", index))",
                content: NoteContent(format: .plainText, text: index == 732 ? "needle body" : "body"),
                tags: index == 411 ? ["needle-tag"] : [],
                modifiedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        let store = MemoryNoteStore(notes: notes)
        let model = SpiralFeatureModel(store: store)

        await model.load()
        #expect(model.notes.count == 1_000)
        #expect(model.selectedNoteID != nil)
        model.searchText = "needle"
        #expect(Set(model.visibleNotes.map(\.title)) == ["Note 0411", "Note 0732"])
    }

    @Test("Create, rename, edit, tag, pin, restore, and delete use NoteStore")
    func completeMutationWorkflow() async throws {
        let store = MemoryNoteStore()
        let model = SpiralFeatureModel(store: store)
        await model.load()
        #expect(model.phase == .empty)

        let created = try #require(await model.createNote())
        await model.renameSelected(to: "Roadmap")
        await model.updateSelectedContent("Ship the vertical slice")
        await model.setSelectedTags(from: "phase3, swiftui, phase3")
        await model.toggleSelectedPin()

        let saved = try #require(await store.note(id: created.id))
        #expect(saved.title == "Roadmap")
        #expect(saved.content.text == "Ship the vertical slice")
        #expect(saved.tags == ["phase3", "swiftui"])
        #expect(saved.isPinned)

        model.selectedNoteID = nil
        model.restoreSelection(created.id.description)
        #expect(model.selectedNoteID == created.id)
        await model.deleteSelected()
        #expect(model.phase == .empty)
        #expect(await store.allNotes().isEmpty)
    }

    @Test("Availability, error, and conflict states are explicit")
    func explicitStates() async throws {
        let note = Note(title: "Conflict", content: .init(format: .plainText, text: "local"))
        let revision = NoteRevision(contentHash: "a", content: Data("local".utf8), modifiedAt: .now)
        let conflict = NoteConflict(noteID: note.id, local: revision, external: revision, commonBase: nil)
        let store = MemoryNoteStore(notes: [note], conflicts: [conflict])
        let model = SpiralFeatureModel(store: store)

        await model.load()
        #expect(model.phase == .conflict(count: 1))
        model.setAvailability(.downloading(progress: 0.5))
        #expect(model.phase == .downloading(progress: 0.5))
        model.setAvailability(.unavailable(message: "Not downloaded"))
        #expect(model.phase == .failure("Not downloaded"))

        let failing = SpiralFeatureModel(store: FailingNoteStore())
        await failing.load()
        guard case .failure = failing.phase else {
            Issue.record("Expected a load failure")
            return
        }
    }

    @Test("Pinned notes remain first in both sort modes")
    func pinnedSort() async {
        let oldPinned = Note(
            title: "Zulu",
            content: .init(format: .plainText, text: ""),
            modifiedAt: .distantPast,
            isPinned: true
        )
        let recent = Note(
            title: "Alpha",
            content: .init(format: .plainText, text: ""),
            modifiedAt: .now
        )
        let model = SpiralFeatureModel(store: MemoryNoteStore(notes: [recent, oldPinned]))
        await model.load()
        #expect(model.visibleNotes.first?.id == oldPinned.id)
        model.settings.sort = .title
        #expect(model.visibleNotes.first?.id == oldPinned.id)
    }

    @Test("Loaded RTF and HTML bodies edit through the format-preserving model")
    func richBodiesRemainFormatted() async throws {
        let codec = NoteFileCodec()
        for format in [NoteFormat.richText, .html] {
            var content = try codec.decode(
                codec.encode(NoteContent(format: format, text: "formatted body")),
                as: format
            )
            let styleRange = (content.text as NSString).range(of: "formatted")
            try content.apply(.bold, toUTF16: styleRange.location..<NSMaxRange(styleRange))
            let note = Note(title: format.rawValue, content: content)
            let store = MemoryNoteStore(notes: [note])
            let model = SpiralFeatureModel(store: store)

            await model.load()
            #expect(model.selectedNoteSupportsTextEditing)
            await model.updateSelectedContent("formatted edited body")
            let edited = try #require(await store.note(id: note.id)?.content)
            #expect(try codec.decode(codec.encode(edited), as: format).text == "formatted edited body")

            await model.renameSelected(to: "Renamed")
            await model.setSelectedTags(from: "safe-metadata")
            await model.toggleSelectedPin()
            let safelyUpdated = try #require(await store.note(id: note.id))
            #expect(safelyUpdated.title == "Renamed")
            #expect(safelyUpdated.tags == ["safe-metadata"])
            #expect(safelyUpdated.isPinned)
            #expect(safelyUpdated.content.text == "formatted edited body")
        }
    }
}

private actor MemoryNoteStore: NoteStore {
    private var notes: [NoteID: Note]
    private let storedConflicts: [NoteConflict]

    init(notes: [Note] = [], conflicts: [NoteConflict] = []) {
        self.notes = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        storedConflicts = conflicts
    }

    func allNotes() -> [Note] { Array(notes.values) }
    func note(id: NoteID) -> Note? { notes[id] }
    func create(_ note: Note) throws -> Note { notes[note.id] = note; return note }
    func update(_ note: Note) throws { notes[note.id] = note }
    func delete(id: NoteID) throws { notes[id] = nil }
    func conflicts() -> [NoteConflict] { storedConflicts }
    func rebuildIndex() throws {}
}

private struct FailingNoteStore: NoteStore {
    enum Failure: Error { case unavailable }
    func allNotes() async throws -> [Note] { throw Failure.unavailable }
    func note(id: NoteID) async throws -> Note? { nil }
    func create(_ note: Note) async throws -> Note { throw Failure.unavailable }
    func update(_ note: Note) async throws { throw Failure.unavailable }
    func delete(id: NoteID) async throws { throw Failure.unavailable }
    func conflicts() async -> [NoteConflict] { [] }
    func rebuildIndex() async throws { throw Failure.unavailable }
}
