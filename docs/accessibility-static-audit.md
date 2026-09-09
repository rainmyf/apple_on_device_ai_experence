# Accessibility static audit

Scope: source inspection of the SwiftUI navigation shell and all destination views. Runtime VoiceOver, Dynamic Type, Reduce Motion, permission-denial, and dark-mode behavior remain unobserved until a concrete simulator or device is available.

| Check | Source evidence | Static result | Runtime boundary |
| --- | --- | --- | --- |
| Dynamic Type | Body/title text uses semantic fonts; long copy uses `fixedSize(horizontal: false, vertical: true)`; forms are in `ScrollView`. | Covered by source | Large-size clipping still needs device observation. |
| VoiceOver labels | Decorative SF Symbols use `accessibilityHidden(true)`; cards expose opening hints; category See all links expose explicit labels; home header combines children with a label. | Covered by source | VoiceOver traversal still needs runtime observation. |
| Status not color-only | Capability status is rendered as text plus an icon; error and result surfaces use text. | Covered by source | Contrast/readability still needs runtime observation. |
| 44-point targets | Category See all has `minHeight: 44`; primary controls use system bordered buttons; navigation rows/cards have substantially larger frames. | Covered by source | Actual hit testing still needs runtime observation. |
| Reduced motion | No app-authored animation or transition is present in the inspected source; streaming and recording lifecycle actions are explicit. | Covered by source | Reduce Motion setting still needs runtime observation. |
| Permission/unavailable states | Capability requirements and framework-specific error/status text are rendered in page content; unavailable pages stay navigable. | Covered by source | Denial flows still need runtime observation. |

Static audit conclusion: no source-level accessibility blocker was found in these checks. This is not a runtime accessibility pass.
