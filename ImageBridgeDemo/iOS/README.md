# ImageBridge iOS sender

Standalone SwiftUI app and image-input App Intent for iOS 27. Bundle ID: `com.rain.ImageBridge`. Open the HarmonyOS ImageBridge receiver on the same local network, allow iOS Local Network access, then choose 1–20 photos in order or send the generated 1200 × 800 test image.

The app UI contains only the title, photo/test buttons, cancel/receiver selection when needed, and concise Chinese status. Implementation details stay in this document.

## Execution and discovery

In Shortcuts, add **发送到我的华为手机** and pass an image to its **图片** parameter. The real `SendImageIntent` conforms to `LongRunningIntent` and `CancellableIntent`; the extracted metadata also lists `ProgressReporting`. Its `perform()` discovers/selects a receiver first, then calls the actual SDK `performBackgroundTask(operation:onCancel:)` API with a String-returning closure for image normalization and transfer. Progress reflects actual 256 KiB send completions; only receiver ACK advances progress to 100%. System cancellation closes the active Network connection through a synchronized cancellation relay; normal Swift Task cancellation does likewise.

Bonjour `_imgbridge._tcp` discovery is event-driven: once nonempty results stop changing for 350 ms, the collected receivers are returned. Discovery ends after at most 5 seconds even if results keep changing. iOS controls mDNS packet timing; the app does not restart browsers or busy-poll. One receiver is automatic; multiple results require an explicit choice. This finite window cannot guarantee finding receivers that only announce later.

The foreground photo/test buttons use the **shared normalization and transfer implementation** directly. They do not call the long-running framework wrapper. This preserves basic image transfer while upcoming system Shortcuts tests verify the new framework execution path. Multiple receivers use a native choice dialog in the app and App Intents disambiguation in Shortcuts.

The image is downsampled with ImageIO, EXIF orientation applied, and encoded as JPEG quality 0.85, at most 2048 pixels per edge. Image service now uses the batch protocol below. Each image may contain 1 byte–20 MiB of JPEG data; the batch total is at most 100 MiB. Each image send/ACK operation has its own 30-second deadline (45 seconds for the last image, including a 15-second preview reserve), with no silent retry. Final success means files saved and the system preview API accepted, not an independent observation of screen pixels.

## Build and install

Requires Xcode 27 and iOS 27. The project uses the available development team `DH255M46VJ`; the reference project's team `8RXT3QWW75` has no usable account on this Mac. Override `DEVELOPMENT_TEAM` if needed.

Run from this directory:

```sh
xcodebuild -project ImageBridge.xcodeproj -scheme ImageBridge \
  -configuration Debug -destination 'id=00008150-001202923A83401C' \
  -derivedDataPath build -allowProvisioningUpdates build
xcrun devicectl device install app --device 00008150-001202923A83401C \
  build/Build/Products/Debug-iphoneos/ImageBridge.app
xcrun devicectl device process launch --device 00008150-001202923A83401C com.rain.ImageBridge
```

After receiver launch, append `--send-test-image` to send the generated image using the foreground shared implementation. The extra diagnostic argument `--test-intent-wrapper` routes this test through a direct Swift `intent.perform()` call; this remains distinct from invoking a system Shortcut. Local network permission may require a user tap on first use.

## Verification

```sh
swiftc ImageBridge/BridgeFrame.swift Tests/main.swift -o build/frame-tests
build/frame-tests
swiftc -parse-as-library ImageBridge/BridgeFrame.swift ImageBridge/BridgeNetwork.swift \
  Tests/NetworkHarness.swift -o build/network-harness
build/network-harness --cancel-test
build/network-harness --relay-cancel-test
# Discover only, or transfer an already normalized JPEG from macOS:
build/network-harness
build/network-harness /absolute/path/test.jpg
```

Observed 2026-09-06:

- Protocol tests passed: little-endian framing, payload preservation, empty/oversized rejection, exact 20 MiB boundary.
- Production NWBrowser cancellation tests passed: native Task cancellation, relay cancellation before startup, and relay cancellation during discovery.
- Production macOS discovery against the actual HarmonyOS receiver completed in **0.378116 seconds**. This measures this run, not a guarantee for every network/device.
- Signed iPhone build and installation succeeded. After an initial free-profile app limit error, the user independently removed two apps to free slots. This subtask did not uninstall existing apps.
- Before the LongRunningIntent change, real iPhone direct `intent.perform()` sent **147472 JPEG bytes** and received ACK success (`launch-test-instrumented.log`). This is historical evidence for the original ordinary intent only.
- The LongRunningIntent build registers LongRunning, ProgressReporting and Cancellable in `Metadata.appintents/extract.actionsdata`. Build and installation evidence: `build-longrunning.log`, `install-longrunning.log`.
- Foreground shared-code regression on the final UI succeeded on the physical iPhone: **147472 JPEG bytes**, receiver success ACK (`launch-shared-ui-test.log`).
- Direct Swift calls into the new framework wrapper failed with `LNPerformActionErrorCodeUnsupportedValueType`, before entering the background closure. A Void-returning closure, plain discovery, explicit JPEG type, initialized optional receiver, and an explicit String return matching Apple’s example did not eliminate this error. Logs: `launch-longrunning-void-test.log`, `launch-longrunning-plain-discovery-test.log`, `launch-longrunning-jpeg-test.log`, `launch-longrunning-string-test.log`. The cause is unresolved; lack of system invocation context is only a hypothesis.
- System Shortcuts invocation, background runtime extension, system progress UI and system cancellation remain **unverified**, to be tested next. No fallback exists inside the actual LongRunningIntent.

## API references

Verified against the Xcode 27 iPhoneOS SDK `AppIntents.swiftinterface` and Apple's current documentation:

- [LongRunningIntent](https://developer.apple.com/documentation/appintents/longrunningintent)
- [performBackgroundTask(options:operation:onCancel:)](https://developer.apple.com/documentation/appintents/longrunningintent/performbackgroundtask(options:operation:oncancel:))

Apple requires regular meaningful progress updates while the extended task runs; adopting the protocol alone does not request extended execution.

Latest user validation: the system App Intent invocation succeeded before the background-only change. The background-only configuration was then requested; build metadata and installation are checked, while no-jump execution requires another system Shortcut run.

## 消息分享（Demo 2）

首页为「图片分享」「消息分享」两个独立入口。新系统动作标题为 **分享消息给我的华为手机**，输入参数「消息」为 String，`supportedModes = .background`。它采用普通 AppIntent；原图片动作 **发送到我的华为手机** 的 LongRunningIntent、进度和取消实现保持不变。

消息通过独立 Bonjour `_msgbridge._tcp` 发现接收端（Harmony TCP 22857），发送 uint32 little-endian UTF-8 字节数及原文。允许 1–65536 字节；不会 trim、规范化或 JSON 包装。ACK 0 表示接收端确认弹窗已打开，不代表用户已读。Harmony 应保持前台运行；这是应用内弹窗，不是系统通知。

消息页提供文本编辑与发送、取消、多设备选择。隐藏启动参数 `--send-test-message` 会直接调用新 `SendMessageIntent.perform()`，发送含中文、emoji、换行、空行和首尾空格的固定消息；这是应用内直接调用证据，不能代替系统快捷指令调用验证。

Demo 2 验证（2026-09-06）：

- 原图片 20 MiB 帧测试继续通过；新增 UTF-8 原文/换行/空格保持、空消息拒绝、65536 字节接受、超限拒绝和 LE header 测试通过。
- `build-message.log` 原生签名构建成功，`install-message.log` 安装至指定 iPhone 成功。
- 构建产物 `Metadata.appintents/extract.actionsdata` 中两个动作均 `supportedModes = 1` 且 `openAppWhenRun = false`，标题准确；图片仍注册 LongRunning、ProgressReporting、Cancellable。
- 用户此前已确认图片系统 App Intent 后台运行成功；上文较早「等待系统验证」记录已由该用户验证更新。新消息动作系统快捷指令调用尚待验证。

## Batch image revision (2026-09-06)

The current image action keeps title **发送到我的华为手机**, `.background`, `LongRunningIntent`, and `CancellableIntent`. The `image` parameter is now `[IntentFile]`, accepts `public.image`, and explicitly connects to preceding Shortcut input. `ImageBridgeShortcuts` registers the same AppShortcutsProvider/AppShortcut pattern as `apple_ai`. App Shortcut registration does not itself enable the Photos Share Sheet: import/configure the image-accepting Share Sheet shortcut in `Shortcuts/` (delivered separately).

PhotosPicker uses ordered selection, maximum 20. It retains picker references, then loads and normalizes one image only after the previous image is acknowledged. System IntentFile input is similarly accessed by index. The diagnostic `--test-intent-wrapper` creates its generated test input up front; it is not the production Photos input path. `--send-test-batch` generates two distinct numbered images lazily, in order.

On one `_imgbridge._tcp` connection (Harmony port 22856), send ASCII `IBAT`, uint32LE count (1–20), then each uint32LE JPEG length + JPEG. The sender waits for one ACK per image before loading/sending the next. ACK 0 confirms saved; the last ACK 0 additionally confirms final system preview API acceptance. ACK 1 rejects the current image. ACK 2 is valid only for the last image: all files saved, preview failed. There is no extra ACK after the last per-image ACK. Errors state the confirmed saved count; an interrupted/unacknowledged final write may still have reached disk, so it is not counted as confirmed. No automatic retry. System cancellation closes the active connection, including during source loading. Images persist in the receiver's app-private directory; this is not a claim of saving into the public photo gallery.

Message demo wire, title and ordinary background AppIntent remain unchanged.

Additional tests:

```sh
python3 Tests/batch_network_test.py
```

The compiled production `ImageBatchSession` tests verify count/image/100 MiB boundaries, ACK order, premature/final ACK2 and partial counts. The local TCP adversarial peer exercises actual `BridgeNetwork.sendImages` with distinct 300000-byte payloads, withheld ACKs, early rejection, final preview failure, invalid ACKs, disconnects and system cancellation. It verifies no next image bytes arrive before ACK and no later image is loaded after failure. These are macOS production-code tests, not iPhone/Shortcuts or Harmony viewer execution evidence.

Current revision verification: `build-batch.log` records a successful signed native build; `install-batch.log` records successful installation on iPhone `00008150-001202923A83401C`. Extracted metadata confirms array image input, `inputConnectionBehavior = 2`, background execution and all three image protocols, plus the registered App Shortcut. Batch physical transfer/Photos Share Sheet invocation and visible receiver preview are not established by these build/install checks.

Final-preview budget regression: `python3 Tests/batch_network_test.py --preview-reserve` holds the last ACK for 31 seconds; the production sender succeeded within its final 45-second operation budget. The preceding image operations remain 30 seconds. The latest `build-batch.log` and `install-batch.log` include this revision.
