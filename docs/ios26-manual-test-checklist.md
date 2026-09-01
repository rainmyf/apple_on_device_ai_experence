# iOS 26 capability manual test matrix

This checklist records observations only after a real device or concrete simulator run. The observation, latency, availability reason, device, OS, and offline columns intentionally remain blank until that run occurs. Operation type is the expected single-page action boundary from the catalog contract.

| ID | Page opened | Input works | Expected operation type | Observed output | Latency | Availability reason | Device | OS | Offline | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| foundationModel |  |  | One prompt |  |  |  |  |  |  |  |
| guidedGeneration |  |  | One structured request |  |  |  |  |  |  |  |
| contentTagging |  |  | One text tagging request |  |  |  |  |  |  |  |
| streaming |  |  | One streaming request with cancel |  |  |  |  |  |  |  |
| toolCalling |  |  | One local fact request |  |  |  |  |  |  |  |
| translation |  |  | One translation request |  |  |  |  |  |  |  |
| naturalLanguage |  |  | One text analysis request |  |  |  |  |  |  |  |
| vision |  |  | One selected image and mode |  |  |  |  |  |  |  |
| speechTranscription |  |  | One microphone transcript |  |  |  |  |  |  |  |
| soundRecognition |  |  | One microphone sound analysis |  |  |  |  |  |  |  |
| imageCreator |  |  | One image prompt |  |  |  |  |  |  |  |
| imagePlayground |  |  | Open system image UI |  |  |  |  |  |  |  |
| writingTools |  |  | Edit text and invoke system tools |  |  |  |  |  |  |  |
| genmoji |  |  | Edit text and use system input |  |  |  |  |  |  |  |
| smartReply |  |  | Present conversation and await system suggestion |  |  |  |  |  |  |  |
| appIntents |  |  | Run one deterministic app action |  |  |  |  |  |  |  |
| customAdapter |  |  | Inspect local adapter setup |  |  |  |  |  |  |  |

## Required interaction pass

For each row, attempt navigation and return, featured paging where applicable, the single expected action, duplicate-run prevention, cancellation, unavailable-state copy, permission denial, VoiceOver labels, Dynamic Type, Reduce Motion, and dark-mode readability. Record only directly observed behavior in the blank columns above.

## Current execution boundary

No rows are marked observed in this checklist. The automated suite has executed 175 tests in 12 suites on an iPhone 17 Pro iOS 26.5 Simulator, but those tests validate deterministic app logic rather than the manual capability experiences represented by this matrix. Launch-and-interact visual QA requires a concrete simulator pass; Apple Intelligence, microphone, system UI, adapter, and offline claims require an eligible physical device where applicable.
