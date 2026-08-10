# Spiral Mobile

`SpiralMobile` is one universal SwiftUI application target for iPhone and iPad.
Production resolves `iCloud.farm.poplar.spiral` and opens the same coordinated
`Documents` collection and private reconciliation records as the Mac. It refuses
legacy database/WAL artifacts until the Mac finishes the guarded handoff.

The target imports only `SpiralCore` and `SpiralFeature`. It must not link or
import the legacy AppKit controllers, archive implementation, or Objective-C
bridging header. UI test collections use a validated UUID beneath the app's own
Application Support container and never resolve or mutate live iCloud data.
