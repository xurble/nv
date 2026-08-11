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

import SpiralCore
import SwiftUI

public struct SpiralCollectionView: View {
    @ObservedObject private var model: SpiralFeatureModel
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @SceneStorage("spiral.selectedNoteID") private var restoredSelection: String?
    @State private var showingSettings = false
    @State private var showingDeleteConfirmation = false
    @State private var saveTask: Task<Void, Never>?

    #if os(macOS)
    private let macEditorFactory: MacTextViewFactory

    public init(
        model: SpiralFeatureModel,
        macEditorFactory: @escaping MacTextViewFactory = { NSTextView() }
    ) {
        self.model = model
        self.macEditorFactory = macEditorFactory
    }
    #else
    public init(model: SpiralFeatureModel) {
        self.model = model
    }
    #endif

    public var body: some View {
        NavigationSplitView {
            noteList
                .navigationTitle("Notes")
                .toolbar { listToolbar }
        } detail: {
            detail
                .toolbar { detailToolbar }
        }
        .searchable(text: $model.searchText, prompt: "Search notes")
        .sheet(isPresented: $showingSettings) { settingsView }
        .confirmationDialog(
            "Delete this note?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Note", role: .destructive) { Task { await model.deleteSelected() } }
        } message: {
            Text("The note file will be deleted from this disposable collection.")
        }
        .task {
            await model.load()
            model.restoreSelection(restoredSelection)
        }
        .onChange(of: model.selectedNoteID) { _, newValue in
            restoredSelection = newValue?.description
        }
        .onDisappear { saveTask?.cancel() }
    }

    private var noteList: some View {
        List(selection: $model.selectedNoteID) {
            if case let .conflict(count) = model.phase {
                Label("\(count) unresolved conflict\(count == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("collection.conflicts")
            }
            ForEach(model.visibleNotes) { note in
                NoteRow(note: note, showPreview: model.settings.showPreviews)
                    .tag(note.id)
            }
        }
        .accessibilityIdentifier("note.list")
        .overlay { listOverlay }
    }

    @ViewBuilder
    private var listOverlay: some View {
        switch model.phase {
        case .loading:
            ProgressView("Opening collection…")
                .accessibilityIdentifier("collection.loading")
        case .empty where model.searchText.isEmpty:
            ContentUnavailableView(
                "No Notes",
                systemImage: "note.text",
                description: Text("Create a note to start this collection.")
            )
            .accessibilityIdentifier("collection.empty")
        case .ready where model.visibleNotes.isEmpty,
             .conflict where model.visibleNotes.isEmpty:
            ContentUnavailableView.search(text: model.searchText)
                .accessibilityIdentifier("collection.noResults")
        case let .downloading(progress):
            VStack(spacing: 12) {
                if let progress { ProgressView(value: progress) } else { ProgressView() }
                Text("Downloading notes…")
            }
            .padding()
            .accessibilityIdentifier("collection.downloading")
        case let .failure(message):
            ContentUnavailableView(
                "Collection Unavailable",
                systemImage: "exclamationmark.icloud",
                description: Text(message)
            )
            .accessibilityIdentifier("collection.error")
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let note = model.selectedNote {
            Group {
            #if os(macOS)
            NoteEditor(
                note: note,
                macEditorFactory: macEditorFactory,
                onRename: { title in Task { await model.renameSelected(to: title) } },
                onContentChange: scheduleContentSave,
                onTagsChange: { tags in Task { await model.setSelectedTags(from: tags) } }
            )
            #else
            NoteEditor(
                note: note,
                onRename: { title in Task { await model.renameSelected(to: title) } },
                onContentChange: scheduleContentSave,
                onTagsChange: { tags in Task { await model.setSelectedTags(from: tags) } }
            )
            #endif
            }
            .id(note.id)
        } else {
            ContentUnavailableView("Select a Note", systemImage: "note.text")
                .accessibilityIdentifier("note.noSelection")
        }
    }

    @ToolbarContentBuilder
    private var listToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { Task { await model.createNote() } } label: { Label("New Note", systemImage: "square.and.pencil") }
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityIdentifier("command.new")
            Button { showingSettings = true } label: { Label("Settings", systemImage: "gear") }
                .accessibilityIdentifier("command.settings")
        }
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItemGroup {
            #if os(iOS)
            if horizontalSizeClass == .compact {
            Button { Task { await model.createNote() } } label: { Label("New Note", systemImage: "square.and.pencil") }
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityIdentifier("command.new")
            }
            #endif
            Button { Task { await model.toggleSelectedPin() } } label: {
                Label(model.selectedNote?.isPinned == true ? "Unpin" : "Pin", systemImage: "pin")
            }
            .disabled(model.selectedNote == nil)
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .accessibilityIdentifier("command.pin")
            Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(model.selectedNote == nil)
            .keyboardShortcut(.delete, modifiers: .command)
            .accessibilityIdentifier("command.delete")
            #if os(iOS)
            if horizontalSizeClass == .compact {
                Button { showingSettings = true } label: { Label("Settings", systemImage: "gear") }
                    .accessibilityIdentifier("command.settings")
            }
            #endif
        }
    }

    private var settingsView: some View {
        NavigationStack {
            Form {
                Picker("Sort Notes", selection: $model.settings.sort) {
                    ForEach(NoteListSort.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle("Show note previews", isOn: $model.settings.showPreviews)
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingSettings = false }
                }
            }
        }
        .frame(minWidth: 320, minHeight: 240)
        .accessibilityIdentifier("settings.view")
    }

    private func scheduleContentSave(_ content: NoteContent) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await model.updateSelectedContent(content)
        }
    }

}

private struct NoteRow: View {
    let note: Note
    let showPreview: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(note.title).font(.headline).lineLimit(1)
                if note.isPinned { Image(systemName: "pin.fill").accessibilityLabel("Pinned") }
            }
            if showPreview {
                Text(note.content.text.replacingOccurrences(of: "\n", with: " "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !note.tags.isEmpty {
                Text(note.tags.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("note.row.\(note.id.description)")
    }
}

private struct NoteEditor: View {
    let note: Note
    #if os(macOS)
    let macEditorFactory: MacTextViewFactory
    #endif
    let onRename: (String) -> Void
    let onContentChange: (NoteContent) -> Void
    let onTagsChange: (String) -> Void

    @State private var title: String
    @State private var content: NoteContent
    @State private var tags: String

    #if os(macOS)
    init(
        note: Note,
        macEditorFactory: @escaping MacTextViewFactory,
        onRename: @escaping (String) -> Void,
        onContentChange: @escaping (NoteContent) -> Void,
        onTagsChange: @escaping (String) -> Void
    ) {
        self.note = note
        self.macEditorFactory = macEditorFactory
        self.onRename = onRename
        self.onContentChange = onContentChange
        self.onTagsChange = onTagsChange
        _title = State(initialValue: note.title)
        _content = State(initialValue: note.content)
        _tags = State(initialValue: note.tags.joined(separator: ", "))
    }
    #else
    init(
        note: Note,
        onRename: @escaping (String) -> Void,
        onContentChange: @escaping (NoteContent) -> Void,
        onTagsChange: @escaping (String) -> Void
    ) {
        self.note = note
        self.onRename = onRename
        self.onContentChange = onContentChange
        self.onTagsChange = onTagsChange
        _title = State(initialValue: note.title)
        _content = State(initialValue: note.content)
        _tags = State(initialValue: note.tags.joined(separator: ", "))
    }
    #endif

    var body: some View {
        VStack(spacing: 0) {
            TextField("Title", text: $title)
                .font(.title2.weight(.semibold))
                .textFieldStyle(.plain)
                .padding()
                .onSubmit { onRename(title) }
                .accessibilityIdentifier("note.title")
            Divider()
            #if os(macOS)
            PlatformTextEditor(
                content: $content,
                makeTextView: macEditorFactory
            )
            #else
            PlatformTextEditor(content: $content)
            #endif
            Divider()
            TextField("Tags, separated by commas", text: $tags)
                .textFieldStyle(.plain)
                .padding()
                .onSubmit { onTagsChange(tags) }
                .accessibilityIdentifier("note.tags")
        }
        .navigationTitle(note.title)
        .onChange(of: content) { _, value in
            onContentChange(value)
        }
        .onDisappear {
            if title != note.title { onRename(title) }
            if tags != note.tags.joined(separator: ", ") { onTagsChange(tags) }
        }
    }
}
