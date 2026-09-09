# ImageBridge Demo

Two standalone projects: iOS App Intent accepts one image and sends it to a foreground HarmonyOS app, which decodes and displays it. No manually entered IP addresses. Existing sibling projects stay untouched.

Discovery: HarmonyOS registers `_imgbridge._tcp.` (Harmony API uses `_imgbridge._tcp`), instance `ImageBridge-<device label>`, TCP port 22856. iOS uses Bonjour. One receiver selects automatically; multiple receivers require explicit choice (never silently broadcast).

Wire: inspired by STORM's four-byte little-endian length prefix, but deliberately a separate demo protocol, not a STORM-compatible node. One connection carries one request: uint32 LE image byte count + JPEG bytes (1..20 MiB). Receiver bounds dimensions to 4096x4096 pixels before decoding. ACK is one byte: 0 after decoding and assigning display state; 1 on failure. Sender normalizes images to JPEG <=2048 pixels per edge for interoperability. No retries that silently duplicate deliveries. Discovery ends after results remain stable for 350 milliseconds; deadline 5 seconds; transfer timeout 30 seconds. Connection closes after ACK.

Harmony app starts listener and publication on launch, stops on destruction; restarting reception rebuilds both. UI shows readiness, last image and concise error states. iOS UI includes photo picker and a generated test-image button for reproducible verification, for reproducible device testing. Shortcut action itself remains the external entry point, input constrained to images. Local network consent is handled by iOS. Demo is local plaintext, foreground receiver only.

Verification: parser adversarial tests (fragmentation, length bounds, trailing data); both native builds; real device install/launch, Bonjour browse, generated test image through intent.perform on iOS and receiver screenshot. A shortcut manually/system-invoked action is separate evidence from in-app intent.perform.

## Follow-up requirements

User requested minimal visible text, faster automatic discovery, and iOS 27 LongRunningIntent before system App Intent testing. Use real performBackgroundTask, progress and cancellation; retain a short discovery deadline independently from the long-task allowance. Harmony publishes immediately; mDNS packet frequency is controlled by the platform.
