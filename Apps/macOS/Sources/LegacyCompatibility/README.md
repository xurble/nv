# Notational Velocity and nvAlt Legacy Compatibility

This directory defines the permanent macOS-only boundary for opening historic
Notational Velocity and nvAlt collections. `NVLegacyCollectionImporter` wraps
the existing `NotationController`, `FrozenNotation`, `NotationPrefs`, crypto,
and WAL implementations. Those implementations remain in their established
files while they are required by the running Mac application.

The boundary has strict rules:

- it receives only a disposable, byte-verified copy selected by the user;
- passphrase verification, decryption, archive decoding, and WAL replay happen
  only inside that copy;
- it never removes the source Keychain item;
- it emits standard TXT, RTF, or HTML files and value snapshots, never legacy
  controller or model objects; and
- shared `SpiralCore` code does not import this header, AppKit, or the legacy
  Objective-C object graph.

`LegacyCompatibilitySource` in `Shared/SpiralCore` is the other side of this
boundary. The production adapter can feed its platform-neutral snapshot after
the retained compatibility implementation has completed recovery.
