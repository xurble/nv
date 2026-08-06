import AppKit
import SwiftUI

@MainActor
private final class SettingsModel: ObservableObject {
    let bridge = NVSettingsBridge()

    @Published var selectedPane: SettingsPane
    @Published var autoCompleteSearches = false
    @Published var confirmNoteDeletion = false
    @Published var quitWhenClosingWindow = false
    @Published var tabKeyIndents = false
    @Published var checkSpelling = false
    @Published var pastePreservesStyle = false
    @Published var linksAutoSuggested = false
    @Published var softTabs = false
    @Published var urlsAreClickable = false
    @Published var highlightSearchTerms = false
    @Published var tableFontSize: Double = 12
    @Published var bodyFontDescription = ""
    @Published var foregroundColor = NSColor.textColor
    @Published var backgroundColor = NSColor.textBackgroundColor
    @Published var highlightColor = NSColor.systemYellow
    @Published var shortcutDescription = ""
    @Published var notesFolderPath = ""

    @Published var storageFormat = 0
    @Published var confirmFileDeletion = false
    @Published var encryptionEnabled = false
    @Published var storesPasswordInKeychain = false
    @Published var secureTextEntry = false
    @Published var encryptionKeyLength = 0
    @Published var hasKeychainItem = false
    @Published var allowedExtensions: [String] = []
    @Published var allowedTypes: [String] = []
    @Published var defaultExtensionIndex = 0

    private var observers: [NSObjectProtocol] = []

    init() {
        selectedPane = SettingsPane(legacyValue: UserDefaults.standard.string(forKey: "LastSelectedPrefsPane"))
        refresh()

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NVSettingsBridgeDidChange, object: bridge, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        observers.append(center.addObserver(forName: NSWindow.didEndSheetNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func select(_ pane: SettingsPane) {
        selectedPane = pane
        UserDefaults.standard.set(pane.title, forKey: "LastSelectedPrefsPane")
    }

    func refresh() {
        autoCompleteSearches = bridge.autoCompleteSearches
        confirmNoteDeletion = bridge.confirmNoteDeletion
        quitWhenClosingWindow = bridge.quitWhenClosingWindow
        tabKeyIndents = bridge.tabKeyIndents
        checkSpelling = bridge.checkSpellingAsYouType
        pastePreservesStyle = bridge.pastePreservesStyle
        linksAutoSuggested = bridge.linksAutoSuggested
        softTabs = bridge.softTabs
        urlsAreClickable = bridge.urlsAreClickable
        highlightSearchTerms = bridge.highlightSearchTerms
        tableFontSize = bridge.tableFontSize
        bodyFontDescription = bridge.noteBodyFontDescription
        foregroundColor = bridge.foregroundTextColor
        backgroundColor = bridge.backgroundTextColor
        highlightColor = bridge.searchHighlightColor
        shortcutDescription = bridge.appShortcutDescription
        notesFolderPath = bridge.notesFolderPath

        storageFormat = bridge.storageFormat
        confirmFileDeletion = bridge.confirmFileDeletion
        encryptionEnabled = bridge.encryptionEnabled
        storesPasswordInKeychain = bridge.storesPasswordInKeychain
        secureTextEntry = bridge.secureTextEntry
        encryptionKeyLength = Int(bridge.encryptionKeyLength)
        hasKeychainItem = bridge.hasKeychainItem
        allowedExtensions = bridge.allowedExtensions
        allowedTypes = bridge.allowedTypes
        defaultExtensionIndex = Int(bridge.defaultExtensionIndex)

    }
}

@objc(ModernSettingsWindowController)
@MainActor
final class ModernSettingsWindowController: NSObject, NSWindowDelegate {
    private let model = SettingsModel()
    private var settingsWindowController: NSWindowController?

    @objc(showWindow:)
    func showWindow(_ sender: Any?) {
        if settingsWindowController == nil {
            let rootView = SettingsRootView(model: model)
            let hostingController = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = String(localized: "Settings")
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.titlebarAppearsTransparent = false
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 760, height: 600))
            window.minSize = NSSize(width: 680, height: 520)
            window.center()
            window.setFrameAutosaveName("ModernSettingsWindow")
            window.delegate = self
            settingsWindowController = NSWindowController(window: window)
        }

        model.refresh()
        settingsWindowController?.showWindow(sender)
        settingsWindowController?.window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        model.bridge.synchronize()
        NSFontPanel.shared.close()
    }
}

private struct SettingsRootView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: Binding(
                get: { model.selectedPane },
                set: { if let pane = $0 { model.select(pane) } }
            )) { pane in
                Label(pane.title, systemImage: pane.systemImage)
                    .tag(pane)
                    .accessibilityIdentifier("settings.sidebar.\(pane.rawValue)")
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            Group {
                switch model.selectedPane {
                case .general: GeneralSettingsView(model: model)
                case .notes: NotesSettingsView(model: model)
                case .editing: EditingSettingsView(model: model)
                case .appearance: AppearanceSettingsView(model: model)
                }
            }
            .navigationTitle(model.selectedPane.title)
            .frame(minWidth: 490, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
        }
        .background(LegacyWorkflowHost(view: model.bridge.legacyWorkflowView).frame(width: 0, height: 0).hidden())
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        SettingsForm {
            Section("Behavior") {
                SettingsToggle("Complete note titles while searching", isOn: binding(\.autoCompleteSearches, action: model.bridge.setAutoCompleteSearches))
                SettingsToggle("Confirm before deleting a note", isOn: binding(\.confirmNoteDeletion, action: model.bridge.setConfirmNoteDeletion))
                SettingsToggle("Quit when the main window closes", isOn: binding(\.quitWhenClosingWindow, action: model.bridge.setQuitWhenClosingWindow))
            }

            Section("Keyboard Shortcut") {
                LabeledContent("Show Spiral") {
                    Button(model.shortcutDescription.isEmpty ? String(localized: "Set Shortcut…") : model.shortcutDescription) {
                        if let window = NSApp.keyWindow { model.bridge.chooseApplicationShortcut(for: window) }
                    }
                    .accessibilityIdentifier("settings.general.shortcut")
                }
                Text("This global shortcut brings Spiral to the foreground from any app.")
                    .settingsHelpText()
            }

            Section("External Editor") {
                LabeledContent("Open notes with") {
                    ExternalEditorPicker(bridge: model.bridge)
                        .frame(width: 230, height: 24)
                }
            }
        }
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<SettingsModel, Bool>, action: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(get: { model[keyPath: keyPath] }, set: { model[keyPath: keyPath] = $0; action($0) })
    }
}

private struct NotesSettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        SettingsForm {
            Section("Storage") {
                LabeledContent("Notes folder") {
                    Button("Choose…") {
                        if let window = NSApp.keyWindow { model.bridge.chooseNotesFolder(for: window) }
                    }
                }
                Text(model.notesFolderPath)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .settingsHelpText()

                Picker("Format", selection: Binding(
                    get: { model.storageFormat },
                    set: { model.bridge.requestStorageFormat($0); model.refresh() }
                )) {
                    ForEach(StorageFormat.supported) { format in
                        Text(format.title).tag(format.id)
                    }
                }
                .accessibilityIdentifier("settings.notes.storageFormat")

                if let format = StorageFormat.supported.first(where: { $0.id == model.storageFormat }) {
                    Text(format.detail).settingsHelpText()
                }

                if model.storageFormat != 0 {
                    SettingsToggle("Confirm before deleting note files", isOn: Binding(
                        get: { model.confirmFileDeletion },
                        set: { model.confirmFileDeletion = $0; model.bridge.setConfirmFileDeletion($0) }
                    ))
                }
            }

            if model.storageFormat != 0 {
                Section("Recognized Files") {
                    EditableValueList(
                        title: "Extensions",
                        values: model.allowedExtensions,
                        defaultIndex: model.defaultExtensionIndex,
                        onReplace: model.bridge.replaceAllowedExtension,
                        onAdd: model.bridge.addAllowedExtension,
                        onRemove: model.bridge.removeAllowedExtension,
                        onMakeDefault: model.bridge.makeDefaultExtension,
                        refresh: model.refresh
                    )
                    EditableValueList(
                        title: "File types",
                        values: model.allowedTypes,
                        defaultIndex: nil,
                        onReplace: model.bridge.replaceAllowedType,
                        onAdd: model.bridge.addAllowedType,
                        onRemove: { model.bridge.removeAllowedType(at: $0); return true },
                        onMakeDefault: nil,
                        refresh: model.refresh
                    )
                }
            }

            Section("Security") {
                LabeledContent("Note encryption") {
                    Button(model.encryptionEnabled ? "Turn Off…" : "Turn On…") {
                        model.bridge.requestEncryptionToggle()
                        model.refresh()
                    }
                }
                Text(model.encryptionEnabled ? "Enabled · \(model.encryptionKeyLength)-bit key" : "Off")
                    .settingsHelpText()

                if model.encryptionEnabled {
                    SettingsToggle("Remember password in Keychain", isOn: Binding(
                        get: { model.storesPasswordInKeychain },
                        set: { model.storesPasswordInKeychain = $0; model.bridge.setStoresPasswordInKeychain($0) }
                    ))
                    SettingsToggle("Use secure text entry", isOn: Binding(
                        get: { model.secureTextEntry },
                        set: { model.secureTextEntry = $0; model.bridge.setSecureTextEntry($0) }
                    ))
                    HStack {
                        Button("Change Password…") { model.bridge.requestPassphraseChange() }
                        Button("Remove Saved Password", role: .destructive) {
                            model.bridge.removeKeychainItem()
                        }
                        .disabled(!model.hasKeychainItem)
                    }
                }
            }
        }
    }
}

private struct EditingSettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        SettingsForm {
            Section("Typing") {
                Picker("Tab key", selection: boolBinding(\.tabKeyIndents, action: model.bridge.setTabKeyIndents)) {
                    Text("Indent note text").tag(true)
                    Text("Move focus").tag(false)
                }
                SettingsToggle("Use spaces instead of tabs", isOn: boolBinding(\.softTabs, action: model.bridge.setSoftTabs))
                SettingsToggle("Check spelling while typing", isOn: boolBinding(\.checkSpelling, action: model.bridge.setCheckSpellingAsYouType))
            }

            Section("Links and Pasting") {
                SettingsToggle("Preserve styles when pasting", isOn: boolBinding(\.pastePreservesStyle, action: model.bridge.setPastePreservesStyle))
                SettingsToggle("Suggest links to other notes", isOn: boolBinding(\.linksAutoSuggested, action: model.bridge.setLinksAutoSuggested))
                SettingsToggle("Make web addresses clickable", isOn: boolBinding(\.urlsAreClickable, action: model.bridge.setURLsAreClickable))
            }
        }
    }

    private func boolBinding(_ keyPath: ReferenceWritableKeyPath<SettingsModel, Bool>, action: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(get: { model[keyPath: keyPath] }, set: { model[keyPath: keyPath] = $0; action($0) })
    }
}

private struct AppearanceSettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        SettingsForm {
            Section("Note Text") {
                LabeledContent("Font") {
                    Button(model.bodyFontDescription) { model.bridge.chooseNoteBodyFont() }
                }
                ColorPicker("Text color", selection: colorBinding(\.foregroundColor, action: model.bridge.setForegroundTextColor), supportsOpacity: false)
                ColorPicker("Background color", selection: colorBinding(\.backgroundColor, action: model.bridge.setBackgroundTextColor), supportsOpacity: false)
            }

            Section("Notes List") {
                LabeledContent("Text size") {
                    HStack(spacing: 10) {
                        Slider(value: Binding(
                            get: { model.tableFontSize },
                            set: { model.tableFontSize = $0; model.bridge.setTableFontSize($0) }
                        ), in: 9...24, step: 1)
                        .frame(width: 150)
                        Text("\(Int(model.tableFontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }

            Section("Search") {
                SettingsToggle("Highlight matching terms", isOn: Binding(
                    get: { model.highlightSearchTerms },
                    set: { model.highlightSearchTerms = $0; model.bridge.setHighlightSearchTerms($0) }
                ))
                ColorPicker("Highlight color", selection: colorBinding(\.highlightColor, action: model.bridge.setSearchHighlight), supportsOpacity: true)
                    .disabled(!model.highlightSearchTerms)
            }
        }
    }

    private func colorBinding(_ keyPath: ReferenceWritableKeyPath<SettingsModel, NSColor>, action: @escaping (NSColor) -> Void) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: model[keyPath: keyPath]) },
            set: {
                let color = NSColor($0)
                model[keyPath: keyPath] = color
                action(color)
            }
        )
    }
}

private struct SettingsForm<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
    }
}

private struct SettingsToggle: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool

    init(_ title: LocalizedStringKey, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        Toggle(title, isOn: $isOn).toggleStyle(.switch)
    }
}

private struct EditableValueList: View {
    let title: String
    let values: [String]
    let defaultIndex: Int?
    let onReplace: (UInt, String) -> Bool
    let onAdd: () -> Void
    let onRemove: (UInt) -> Bool
    let onMakeDefault: ((UInt) -> Bool)?
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button(action: { onAdd(); refresh() }) {
                    Label("Add", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Add \(title.lowercased())")
            }
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                EditableValueRow(
                    value: value,
                    isDefault: defaultIndex == index,
                    canMakeDefault: onMakeDefault != nil,
                    onCommit: { _ = onReplace(UInt(index), $0); refresh() },
                    onMakeDefault: { _ = onMakeDefault?(UInt(index)); refresh() },
                    onRemove: { _ = onRemove(UInt(index)); refresh() }
                )
            }
        }
        .padding(.vertical, 4)
    }
}

private struct EditableValueRow: View {
    @State var value: String
    let isDefault: Bool
    let canMakeDefault: Bool
    let onCommit: (String) -> Void
    let onMakeDefault: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack {
            TextField("Value", text: $value)
                .onSubmit { onCommit(value) }
            if canMakeDefault {
                Button(action: onMakeDefault) {
                    Image(systemName: isDefault ? "star.fill" : "star")
                }
                .buttonStyle(.borderless)
                .help(isDefault ? "Default extension" : "Make default")
            }
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove")
        }
    }
}

private struct ExternalEditorPicker: NSViewRepresentable {
    let bridge: NVSettingsBridge

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.menu = bridge.externalEditorMenu
        selectDefault(in: button)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        selectDefault(in: button)
    }

    private func selectDefault(in button: NSPopUpButton) {
        let defaultEditor = ExternalEditorListController.sharedInstance().defaultExternalEditor()
        if let index = button.itemArray.firstIndex(where: { ($0.representedObject as AnyObject?) === defaultEditor }) {
            button.selectItem(at: index)
        }
    }
}

private struct LegacyWorkflowHost: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.widthAnchor.constraint(equalToConstant: 1),
            view.heightAnchor.constraint(equalToConstant: 1)
        ])
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private extension View {
    func settingsHelpText() -> some View {
        font(.callout).foregroundStyle(.secondary)
    }
}
