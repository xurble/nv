# Phase 3 verification

All collections used by these tests are disposable. The mobile and Mac UI
fixtures contain the same `Welcome.txt` plus 120 `Fixture Note N.txt` files.

| Requirement | Automated coverage |
| --- | --- |
| Shared mutations and states | `Shared/SpiralFeature/Tests/SpiralFeatureTests/SpiralFeatureTests.swift` |
| Large collections | 1,000-note model test and 121-note UI fixtures |
| iPhone compact navigation and restoration | `SpiralMobileUITests.testCompactCreateSearchEditAndStateRestoration` |
| iPad split navigation and keyboard input | The mobile suite on an iPad simulator, including command-N |
| VoiceOver semantics and Dynamic Type | Labeled editor/commands plus accessibility-size launch coverage in `testKeyboardDynamicTypeAndVoiceOverSemantics` |
| Multitasking/resizing | Mobile rotation coverage and Mac window zoom coverage |
| Mac keyboard-first workflow | `SpiralPhase3MacUITests.testKeyboardFirstCreateSearchAndEditWithLegacyEditor` |
| Mac `LinkingEditor` hosting | The Mac workflow types through the injected editor view |
| Rich-file editing | AppKit/UIKit adapters edit through `FormattedTextDocument`; model, codec, and store tests insert, delete, and format RTF/HTML while preserving surrounding source structure, and still reject bypassing text-only mutations |

Run the full build and compatibility safety net for each configuration with
`Scripts/ci/run-phase3.sh Debug` and `Scripts/ci/run-phase3.sh Release`. The Mac
UI suite requires the test runner to have macOS automation permission; its
build remains part of the configuration-independent safety net.
