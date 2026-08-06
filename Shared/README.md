# Shared Code

This directory is reserved for code intentionally shared by the macOS and
future iOS applications.

Shared code must expose platform-neutral interfaces and must not import AppKit
or UIKit. Existing macOS code remains in `Apps/macOS` until characterization
tests protect its behavior and platform dependencies have been removed behind
an explicit boundary.
