# On-device SMS Classifier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a self-contained iOS 26 experience that classifies and annotates one SMS with Apple's on-device Foundation Model, supports bundled random JSONL samples, and renders entity labels directly over the source text.

**Architecture:** Keep model-independent parsing, validation, UTF-16 offset resolution, and highlight segmentation as pure Swift components. A FoundationModels adapter performs one guided-generation request and a MainActor view model coordinates availability, random samples, execution, latency, errors, JSON, and UI state. The page is routed through the existing experience catalog.

**Tech Stack:** Swift 6, SwiftUI, FoundationModels, Swift Testing, JSONL bundle resource.

**Spec:** `docs/superpowers/specs/2026-09-01-on-device-sms-classifier.md`

## Global Constraints

- Deployment target remains iOS 26.0.
- Use `SystemLanguageModel.default` and `LanguageModelSession` only.
- No network, cloud fallback, third-party AI API, database, adapter, or tool calling.
- Final offsets use JavaScript slice / UTF-16 code-unit semantics.
- Simulator evidence and physical-device model evidence remain explicitly separate.

---

### Task 1: Pure classification result pipeline

**Files:**
- Create: `AppleOnDeviceModelDemo/SMSClassificationModels.swift`
- Create: `AppleOnDeviceModelDemoTests/SMSClassificationModelsTests.swift`

**Interfaces:**
- Produces: `SMSGeneratedResult`, `SMSGeneratedEntity`, `SMSAnnotationResult`, `SMSAnnotationEntity`, `SMSAnnotationValidator.validate(_:source:)`, `SMSHighlightSegmenter.segments(source:entities:)`.

- [ ] Write failing tests for legal domain/label acceptance, invalid values, UTF-16 offsets with emoji/CJK, repeated occurrences, missing text, and deterministic non-overlap selection.
- [ ] Run the focused tests and save the expected RED log.
- [ ] Implement minimal Sendable/Codable models, v7.24 domain/entity white lists, deterministic UTF-16 resolver, validator, JSON encoder, and highlight segmenter.
- [ ] Run focused tests until GREEN, then rerun adjacent Foundation tests.

### Task 2: Bundled JSONL sample library

**Files:**
- Create: `AppleOnDeviceModelDemo/SMSRandomSamples.swift`
- Create: `AppleOnDeviceModelDemo/sms_samples.jsonl`
- Modify: `AppleOnDeviceModelDemo.xcodeproj/project.pbxproj`
- Create: `AppleOnDeviceModelDemoTests/SMSRandomSamplesTests.swift`

**Interfaces:**
- Produces: `SMSSample`, `SMSJSONLParser.parse(_:)`, `SMSRandomSamplePicker.next(from:excluding:randomIndex:)`, `BundledSMSSampleStore.load()`.

- [ ] Write failing tests for blank lines, malformed rows, empty text, Unicode preservation, deterministic injected random index, bounds, and immediate-repeat avoidance.
- [ ] Run focused tests and record RED.
- [ ] Add a small representative, non-sensitive v7.24 sample set covering every main domain plus ignored hard negatives; add parser/picker/store and Copy Bundle Resources membership.
- [ ] Run focused tests until GREEN and verify the built app contains `sms_samples.jsonl`.

### Task 3: Prompt, guided model adapter, and orchestration

**Files:**
- Create: `AppleOnDeviceModelDemo/SMSClassificationService.swift`
- Create: `AppleOnDeviceModelDemo/SMSClassifierPrompt.swift`
- Create: `AppleOnDeviceModelDemoTests/SMSClassificationServiceTests.swift`

**Interfaces:**
- Produces: `SMSClassificationServing`, `SMSClassificationService`, `SMSClassifierPrompt.make(sms:)`, `SMSClassificationViewModel`.
- Consumes: Task 1 result validator and Task 2 sample store.

- [ ] Write failing tests proving the prompt contains v7.24, all domain labels, critical priority/exclusion rules, untrusted-data delimiters, and no network instruction; test unavailable/empty input, successful validation, malformed generated entities, latency, cancellation, duplicate-run suppression, and random sample state reset.
- [ ] Run focused tests and record RED.
- [ ] Implement simulator-compatible `Generable` representations and the real-device `@Generable` schema; add a `LanguageModelSession` adapter using `SystemLanguageModel.default` and guided generation.
- [ ] Implement the MainActor view model with availability gating, deterministic latency injection, random sample selection, result validation, and error handling.
- [ ] Run focused tests until GREEN and run `build-for-testing` for generic iOS Simulator.

### Task 4: SwiftUI experience and routing

**Files:**
- Create: `AppleOnDeviceModelDemo/SMSClassificationExperience.swift`
- Modify: `AppleOnDeviceModelDemo/Experience.swift`
- Modify: `AppleOnDeviceModelDemo/ExperienceCatalog.swift`
- Modify: `AppleOnDeviceModelDemo/ExperienceDestinationView.swift`
- Modify: `AppleOnDeviceModelDemo.xcodeproj/project.pbxproj`
- Modify: `AppleOnDeviceModelDemoTests/ExperienceCatalogTests.swift`
- Create: `AppleOnDeviceModelDemoTests/SMSClassificationPresentationTests.swift`

**Interfaces:**
- Consumes: `SMSClassificationViewModel`, `SMSHighlightSegmenter`, and existing shared page styles.

- [ ] Write failing catalog/routing tests and presentation-model tests for source-order text, visible labels, accessibility descriptions, button enablement, and implementation-principle copy.
- [ ] Run focused tests and record RED.
- [ ] Add “SMS Classification” to Language & Text and implement one scrollable page with input, random sample, analysis action, highlighted annotation output, JSON, latency/error, and bottom on-device explanation.
- [ ] Ensure keyboard dismissal uses the existing `.dismissibleKeyboard()` behavior.
- [ ] Run focused tests until GREEN.

### Task 5: Full regression and physical-device verification

**Files:**
- Create: `docs/testing/on-device-sms-classifier-test-report.md`

**Interfaces:**
- Consumes: complete Tasks 1–4 implementation.

- [ ] Run the full Simulator test suite and record exact totals, failures, destination, and log path.
- [ ] Build and launch on the connected iPhone without changing lock state unless installation requires it.
- [ ] Verify random sample, manual edit, keyboard dismissal, model availability, classification, highlighted source text, JSON offsets, latency, and offline execution on representative delivery, repayment, and ignored samples.
- [ ] Record compile, Simulator runtime, physical-device automation, and manual observation as separate evidence sections; do not infer unavailable evidence.
