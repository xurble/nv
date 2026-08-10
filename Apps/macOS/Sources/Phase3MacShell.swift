import AppKit
import SpiralCore
import SpiralFeature
import SwiftUI

/// Opt-in shell for exercising the shared Phase 3 feature against disposable
/// local collections while the shipping AppKit window continues to own legacy
/// collections. It deliberately receives explicit paths and never discovers a
/// user's notes directory.
@objc(SpiralPhase3MacShellController)
final class Phase3MacShellController: NSWindowController {
    private let store: LocalNoteStore
    private let featureModel: SpiralFeatureModel

    @objc init(documentsPath: String, reconciliationPath: String, indexPath: String) {
        store = LocalNoteStore(
            documentsURL: URL(fileURLWithPath: documentsPath, isDirectory: true),
            reconciliationURL: URL(fileURLWithPath: reconciliationPath, isDirectory: true),
            indexURL: URL(fileURLWithPath: indexPath, isDirectory: false)
        )
        featureModel = SpiralFeatureModel(store: store)

        let rootView = SpiralCollectionView(
            model: featureModel,
            macEditorFactory: { NVSettingsBridge.newPhase3Editor() }
        )
        let host = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: host)
        window.title = "Spiral Notes"
        window.setContentSize(NSSize(width: 960, height: 640))
        window.minSize = NSSize(width: 640, height: 420)
        super.init(window: window)

        featureModel.setAvailability(.downloading(progress: nil))
        Task { [store, featureModel] in
            do {
                try await store.reloadFromDisk()
                featureModel.setAvailability(.available)
                await featureModel.load()
            } catch {
                featureModel.setAvailability(.unavailable(message: String(describing: error)))
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
