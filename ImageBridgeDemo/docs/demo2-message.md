# Demo 2: 消息分享

User-approved scope: both apps gain a demo list with separate 图片分享 and 消息分享 entries. Keep existing background image Intent named 发送到我的华为手机 unchanged. Add a background text-input Intent named 分享消息给我的华为手机. Harmony shows modal title exactly 收到来自iPhone的通知 and body exactly original text.

Contract: a separate Bonjour service `_msgbridge._tcp` (Harmony name ImageBridge-Message), TCP port22857, preserves original image service22856. Message frame uint32 LE UTF-8 byte length then original UTF-8 bytes (1..65536). Empty/oversized/malformed UTF-8 fail without display. ACK byte0 only after popup open resolves; byte1 failure. No JSON/trim/normalization. Discover350ms stabilization/deadline5s; timeout30s. Foreground Harmony app owns both listeners while navigating; no OS notification or background wake guarantee implied by app modal.

UI: root demo list, image detail, message detail. Minimal text. Harmony modal uses scrollable text and 确定. Later incoming message replaces current dialog only after closing it (no ambiguous overlapping dialogs); contents not truncated. iOS text editor and send action for testing share transport, exact system Intent remains background.

Implementation/verification:
- iOS bounded worker: navigation, SendMessageIntent, reusable discovery/frame transport, native tests, build/install, metadata verification and real text transfer after receiver ready.
- Harmony parent: configurable FrameReader bound tests first, message listener+UTF8, persistent root services and dialog, build/install, visual popup verify, image regression.
- Review protocol/lifecycle and final evidence. Separate in-app sender run from system Shortcut invocation.
