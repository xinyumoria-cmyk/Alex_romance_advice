# File guide

| Path | Role |
|---|---|
| `data/corpus/candidate_extractions.jsonl` | 382 AI-normalized candidate paraphrases, each with source and locator |
| `data/corpus/semantic_decisions.json` | Combined semantic alias/exclusion decisions |
| `data/corpus/canonical_overrides.json`, `final_review_adjustments.json` | Recorded canonical wording and final review |
| `data/corpus/advice_corpus.jsonl` | Frozen 288-entry reference result; replay is compared structurally against it |
| `data/corpus/deduplication_log.jsonl` | Candidate-to-advice mapping, including merged and excluded candidates |
| `data/corpus/sources.json` | Source metadata; internal-evidence names/hashes are provenance only |
| `data/selection/eligibility_decisions.tsv` | Pipe-delimited 288-item decisions, inherited from v2 |
| `data/selection/functional_review.tsv` | Pipe-delimited 120-item functional decisions, comparisons and reasons |
| `data/selection/advice_screening_288.jsonl` | Frozen v3 audit, including historical v2 fields |
| `data/selection/prompt_pack_60.jsonl` | Ordered v3 reference pack |
| `data/selection/eligible_reserve.jsonl` | 60 reserves; not supplied during generation |
| `data/scenarios.json` | Eight scenario texts and factor levels |
| `data/prompts/` | Instructions and exact complete S01–S08 prompts |
| `results/*/responses/` | Original response text files, byte-preserved |
| `results/*/records/` | Task/session/response IDs, timestamps, parameters, usage and hashes |
| `results/codex_chatgpt/raw/` | CLI events and launch/result logs; local paths replaced in publication copies |
| `results/api/raw/` | API response JSON and attempt records; initial sandbox socket denial retained |
| `results/api/requests/` | Actual API request bodies; no Authorization header or credentials |
| `results/api/context_review_40.tsv` | Historical assistant observations; no instruction to edit or exclude |
| `documents/` | English Times New Roman research documents and teacher scenario source |
| `provenance/publication_copy_log.json` | Original and published hashes, any metadata/path sanitization |
| `provenance/offline_verification.json` | Release verification summary |
| `MANIFEST.sha256.json` | Release file inventory and SHA-256 values |

Text-body preservation is checked independently of JSON serialization and CRLF/LF normalization. Original `.txt` hashes are checked on bytes. Prompts are rebuilt and checked on bytes. `.gitattributes` disables automatic line-ending changes so Git checkouts preserve those hashes.

`checks_40.json` and other historical check files contain original-workspace hashes/paths that may differ from publication-copy metadata. The release manifest and publication copy log are authoritative for the packaged files; the historical hashes are retained as provenance rather than overwritten.
