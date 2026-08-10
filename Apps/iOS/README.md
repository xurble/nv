# Spiral Mobile

`SpiralMobile` is one universal SwiftUI application target for iPhone and iPad.
Its Phase 3 storage root is deliberately local Application Support; production
iCloud coordination belongs to Phase 4.

The target imports only `SpiralCore` and `SpiralFeature`. It must not link or
import the legacy AppKit controllers, archive implementation, or Objective-C
bridging header. UI test collections use a validated UUID beneath the app's own
Application Support container and are never inferred from a user's notes
location.
