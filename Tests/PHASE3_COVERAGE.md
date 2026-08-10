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
| Multitasking/resizing | Mobile rotation coverage and Mac full-screen frame-change coverage |
| Mac keyboard-first workflow | `SpiralPhase3MacUITests.testKeyboardFirstCreateSearchAndEditWithLegacyEditor` |
| Mac `LinkingEditor` hosting | The Mac workflow types through the injected editor view |
| Rich-file editing | AppKit/UIKit adapters edit through `FormattedTextDocument`; model, codec, and store tests insert, delete, and format RTF/HTML while preserving surrounding source structure, and still reject bypassing text-only mutations |

Run the full build and compatibility safety net for each configuration with
`Scripts/ci/run-phase3.sh Debug` and `Scripts/ci/run-phase3.sh Release`. The
gate executes the UI suites on these explicit default destinations:

- native Mac using the host architecture;
- `platform=iOS Simulator,name=iPhone 17 Pro,OS=latest`; and
- `platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=latest`.

Set `SPIRAL_UI_IPHONE_DESTINATION` or `SPIRAL_UI_IPAD_DESTINATION` to select a
different installed OS 26 simulator. macOS prompts once to authorize “Enable UI
Automation”; grant that local permission before running the Mac leg. The Mac
fixture shell additionally requires a randomized XCTest temporary root, UUID
token, and matching regular-file sentinel, and refuses to open unverified paths.
