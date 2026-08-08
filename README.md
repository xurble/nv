# Spiral

Spiral is a modernization of [Notational Velocity](https://notational.net/), the modeless, keyboard-focused macOS note-taking application created by Zachary Schneirov. The [original Notational Velocity source code](https://github.com/scrod/nv) provides the foundation for this project.

## Purpose

The project aims to preserve the speed, simplicity, keyboard workflows, and long-lived data compatibility of Notational Velocity while making the application reliable on current Apple platforms.

The work is deliberately incremental. Its priorities are to:

- modernize and maintain the native macOS application;
- preserve existing notes, metadata, encryption compatibility, recovery behavior, and familiar keyboard interaction;
- replace obsolete dependencies and deprecated platform APIs without risking user data;
- extract a tested, platform-neutral core and storage boundary;
- use iCloud Drive as a shared data store while supporting offline use, coordinated writes, conflicts, and safe migration from local collections; and
- prepare for a future universal iPhone and iPad application with its own platform-appropriate interface.

This is not intended to be a wholesale rewrite. Stable Objective-C and C code can remain where replacing it offers no concrete safety or maintenance benefit. New and deliberately extracted components should use Swift where it provides clearer boundaries and stronger correctness.

## Project status

The macOS application is being modernized in stages. Automated coverage, embedded Swift and SwiftUI components, and the guarded first-run path for copying an existing collection into the shared “Spiral Notes” iCloud Drive container are in place. The iCloud container still needs production developer-team registration and live verification, and ongoing coordinated storage, conflict handling, substantial persistence, dependency, distribution, and compatibility work remain. The iOS application has not yet been implemented.

See [MIGRATION_STRATEGY.md](MIGRATION_STRATEGY.md) for the architecture, migration phases, current progress, and data-safety requirements.

## Repository layout

- `Apps/macOS` contains the existing AppKit application.
- `Apps/iOS` is reserved for the future universal iPhone and iPad application.
- `Shared` is reserved for tested code shared across platforms.
- `Tests` contains platform-specific and future shared test suites.
- `Notation.xcodeproj` is the Xcode project.

Contributors should read [AGENTS.md](AGENTS.md) before making architectural, persistence, encryption, synchronization, or migration changes.

## Local signing setup

Developer-team selection is kept out of the project file. Copy `Config/Xcode/Local.xcconfig.example` to `Config/Xcode/Local.xcconfig`, then set `DEVELOPMENT_TEAM` to the 10-character Team ID shown in Xcode or the Apple Developer account. The local file appears in Xcode's **Build Configuration** group, is loaded by every Spiral application build configuration, and is ignored by Git. Builds that intentionally do not sign can continue to pass `CODE_SIGNING_ALLOWED=NO` without creating the local file.

## License

This project is distributed under the terms in [COPYING.txt](COPYING.txt).
