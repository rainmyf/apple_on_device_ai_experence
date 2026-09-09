# ImageBridge Implementation Plan

**Goal:** Automatically discover a HarmonyOS receiver from an image-taking iOS App Intent and display the transferred image.
**Architecture:** Native Swift AppIntents/Network sender, ArkTS NetworkKit mDNS/TCP receiver; independent sample framing documented in the spec.
**Tech Stack:** Xcode 27, SwiftUI, AppIntents, Network; DevEco, ArkTS, ArkUI, NetworkKit, ImageKit.
**Spec:** ../../design.md

## Global Constraints
- New files only under ImageBridgeDemo. No existing app replacement.
- No manual IP. No backend, Rust, topology or CRDT dependency.
- Exact service, frame, ACK and size constraints in design.md are shared by both platforms.

## Tasks
- [x] iOS: Create independently buildable Xcode project, image-input App Intent, Bonjour selection, normalized JPEG transfer with bounded timeout and ACK, photo/test image UI; build for connected iPhone. Files: iOS/ImageBridge/*, iOS/ImageBridge.xcodeproj, iOS/README.md.
- [x] HarmonyOS: Create standalone Stage project, frame accumulator, TCP listener and mDNS publisher, image decoding and display, lifecycle cleanup. Files: HarmonyOS/entry/src/main/ets/{protocol,services,pages,entryability}/*.ets and platform build/resources. Write protocol tests before parser and run against actual parser.
- [x] Integrate: build/install both with distinct bundle IDs, discover real receiver, send image and inspect physical screen. Record precise evidence and startup instructions in README.md. Do not claim Shortcut invocation based solely on in-app perform().

## Follow-up
- [x] Adopt LongRunningIntent, progress/cancellation and event-driven 350 ms discovery stabilization (5 s deadline).
- [x] Remove explanatory UI text on Harmony; rebuild and install.
- [x] Rebuild/install latest iOS and distinguish preparation from future system App Intent testing.

Validation boundary: Native build/install and faster shared foreground transfer passed. Direct Swift invocation of the genuine long-running framework API returned LNPerformActionErrorCodeUnsupportedValueType, including a String-return diagnostic; cause unresolved. System Shortcuts invocation/extended runtime remains the next validation, not a passed gate.
