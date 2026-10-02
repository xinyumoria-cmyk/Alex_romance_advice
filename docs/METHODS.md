# Methods and reproducibility scope

## Research framing

The study compares reference-supported AI advice with advice independently written by ordinary adults, and separately examines source-disclosure effects. The corpus is supplied only to AI. Differences must not be attributed solely to intrinsic human versus AI ability. No participant response or outcome data are included in this release.

## Recorded material preparation

| Stage | Recorded implementation | Limit |
|---|---|---|
| Collection | Purposive collection from 46 pages across 23 publisher domains; English paraphrases with URLs, locators and access dates | Not a systematic review or a verbatim human-authored advice dataset |
| Semantic review | 382 candidates; aliases, canonical-wording decisions and exclusions replay to 288 advice units | AI-assisted contextual judgments; no embedding model, independent double coding or zero-duplication claim |
| Eligibility | 288 recorded item rules, expanded across eight scenarios; 120 eligible, 168 outside scope | Carried forward from v2, not freshly adjudicated in v3 |
| Functional selection | All 120 eligible items reviewed; retain S1–S3, reserve R1–R4; 60 selected, 60 reserve | Purposeful qualitative selection; no fixed quota or optimality claim |
| Input | Same ordered 60-entry reference block and item-specific applicability guards for all scenarios | Context augmentation, not parameter fine-tuning |
| Format | English, 120–180 words, two or three paragraphs | All raw outputs retained; no quality-based replacement |

The v3 revision followed v2 pilot development and preceded v3 generation. It is not retrospectively preregistered. The project researcher confirmed the selection principles on 30 September 2026; this does not establish independent source verification or full human adjudication.

## Eight scenarios

The teacher-derived 2 × 2 × 2 design varies urgency, financial request and Alex's expressed emotional intensity. S01–S04 have low urgency; S05–S08 have high urgency. S03/S04/S07/S08 include a financial request. S02/S04/S06/S08 include high expressed emotional intensity. Urgency concerns conversation tonight, not an explicit immediate-payment deadline. Alex's expressed attachment does not establish the recipient's feelings.

## Two separate batches

| Attribute | Codex / ChatGPT-login batch | API batch |
|---|---|---|
| Advice count | 40; five per scenario | 40; five per scenario |
| Historical interface | Codex CLI, ChatGPT-account authentication | OpenAI Responses API |
| Model | Requested `gpt-6-astra`; serving snapshot not independently verified | Requested and returned `gpt-6-astra`; alias, not a dated snapshot |
| Reasoning effort | `medium` | `medium` |
| Sampling parameters | Temperature, top_p and seed not set | Temperature, top_p and seed omitted |
| Context | Fresh isolated executions; supplied instructions and scenario/reference prompt | Independent requests; no previous_response_id or conversation history |
| Tool use | Disabled by recorded CLI flags; event logs checked | No tools provided |
| API output cap / storage | Not an API request parameter in this batch | max_output_tokens 8192; store false |
| Word document | 08 | 10 |

CLI requests also involve runtime context that is not captured as the exact API request schema. The two interfaces are not assumed interchangeable. Within-scenario text similarity is expected under fixed inputs and is not corrected by editing or asking later responses to differ.

## Observation notes

The advice body is model output. Researcher-only commentary is separate, Codex-assisted observation rather than validated error scoring. In particular, S05-01 and S05-02 in the API batch broaden a situational willingness to talk into an only-support paraphrase. These original texts are retained. Other qualifiers and suggested boundary wording are also documented. These notes do not mandate editing, exclusion or regeneration and must not be shown to evaluators. Any future exclusion policy needs explicit justification, timing and consistent application to AI and human material; it should not be described as preregistered after the fact.

## What can be reproduced

`scripts/reproduce.py` reconstructs the corpus from saved candidates, aliases and wording decisions; applies recorded eligibility and functional decisions; rebuilds all eight prompts byte-for-byte; verifies both 40-response batches against raw logs and Word text; exports tables. Word files are copied from the archived approved versions, not re-authored by the pipeline. No new visualization/render QA of their layout is claimed.

The original webpages and the act of AI-assisted extraction/review are not reproducible deterministic computations. Source URLs, dates and locators are preserved; full webpage/PDF text is not redistributed. Source metadata retains hashes of local retrieval evidence for provenance, but those evidence snapshots are not in this public package. `provenance/original_scripts/` preserves implementation history; those scripts depend on the old workspace and are not the supported entrypoints.

## Official product documentation

Generation settings follow the [OpenAI reasoning guide](https://developers.openai.com/api/docs/guides/reasoning), [GPT-6 Astra model page](https://developers.openai.com/api/docs/models/gpt-6-astra), and [Codex non-interactive documentation](https://learn.chatgpt.com/docs/non-interactive-mode). Model availability, aliases, CLI features and billing can change. New live runs require current account access and may produce different text. Offline replay is the tested default.
