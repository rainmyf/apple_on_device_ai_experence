# SMS Device F1 Evaluation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and run a reproducible 30-sample-per-domain physical-device evaluation for SMS domain classification and exact entity extraction.

**Architecture:** A host-side sampler produces a deterministic JSONL test resource from `_all` files. A serial physical-device Swift Testing suite invokes the production service and prints structured results; a host-side scorer resumes, aggregates, and reports domain/entity F1.

**Tech Stack:** Node.js, Swift Testing, FoundationModels, XCTest/xcodebuild, JSONL.

**Spec:** `docs/superpowers/specs/2026-09-01-sms-device-f1-evaluation.md`

## Global Constraints

- Read only `*_all.jsonl` files under the external dataset.
- Sample 30 unique texts per actual full domain with stable SHA-256 ordering.
- Run FoundationModels sequentially on the connected iPhone.
- Gate on per-domain domain F1 and exact entity F1 >= 0.90.
- Do not commit if any evaluable metric misses the threshold.

---

### Task 1: Deterministic sampler and fixtures

**Files:**
- Create: `tools/build-sms-device-eval.mjs`
- Create: `AppleOnDeviceModelDemoTests/Resources/sms_device_eval_30.jsonl`
- Test: `tools/tests/build-sms-device-eval.test.mjs`

**Interfaces:**
- Consumes: external `_all.jsonl` records.
- Produces: `buildEvaluationSet(root, countPerDomain)` and one 960-row JSONL fixture.

- [ ] Write tests for `_all` filtering, per-domain text deduplication, stable order, 30-row cap, and required fields.
- [ ] Run the tests and verify RED because the sampler does not exist.
- [ ] Implement the sampler with SHA-256 ordering and schema validation.
- [ ] Run tests and verify GREEN.
- [ ] Generate the fixture and verify exactly 30 rows for each of 32 domains.

### Task 2: Metrics and report generator

**Files:**
- Create: `tools/score-sms-device-eval.mjs`
- Test: `tools/tests/score-sms-device-eval.test.mjs`

**Interfaces:**
- Consumes: fixture rows plus prediction JSONL keyed by `msg_id`.
- Produces: per-domain domain/entity PRF, macro/micro summaries, confusion counts, and failure samples.

- [ ] Write RED tests for one-vs-rest domain F1, exact `(label,start,end)` entity matching, duplicates, empty entities, errors, and `N/A` entity domains.
- [ ] Implement deterministic scoring and Markdown/JSON output.
- [ ] Run tests and verify GREEN.

### Task 3: Serial physical-device evaluator

**Files:**
- Create: `AppleOnDeviceModelDemoTests/SMSDeviceEvaluationTests.swift`
- Modify: `AppleOnDeviceModelDemo.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: bundled `sms_device_eval_30.jsonl` and optional domain filter from the test process environment.
- Produces: one `SMS_EVAL_RESULT|<json>` line per sample using production `SMSClassificationService` and validated annotations.

- [ ] Write RED parser/selection tests before adding the physical evaluator.
- [ ] Implement sequential evaluation with stable sample order and structured error records.
- [ ] Build for Simulator and iPhoneOS; run parser tests.

### Task 4: Run, score, analyze, and gate

**Files:**
- Temporary: `/private/tmp/apple-sms-device-eval-results.jsonl`
- Temporary: `/private/tmp/apple-sms-device-eval-report.md`

**Interfaces:**
- Consumes: Tasks 1-3.
- Produces: complete predictions and F1 report.

- [ ] Run each domain shard on the connected iPhone serially and append structured results.
- [ ] Resume missing `msg_id` rows after interruption until all 960 have terminal results.
- [ ] Score domain and entities; inspect every metric below 0.90.
- [ ] If any metric is below threshold, do not commit; report causes and targeted fixes.
- [ ] If all metrics pass, run full Simulator and physical-device smoke verification, then commit and push the feature branch.
