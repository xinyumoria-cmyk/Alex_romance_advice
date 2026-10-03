# Alex advice study — reference v3

[Methods and limitations](docs/METHODS.md) · [File guide](docs/FILES.md) · [Publication notes](docs/PUBLICATION.md)

A reproducibility package containing candidate extractions, the advice corpus, selection decisions, scenarios, prompts, and two batches of 40 original responses. **No participant data, API keys, or completed model fine-tuning are included.**

## Run the offline workflow

Python 3.10 or newer is required. No third-party Python packages are needed. Run the following command from the directory containing this README on Windows, macOS, or Linux:

```bash
python scripts/reproduce.py
```

The `build/` directory will contain the reconstructed 288-entry corpus, 60 selected entries, 60 reserves, 2,304 scenario-applicability records, eight byte-matched prompts, both response batches in JSONL/CSV, archived Word copies, and a verification report. This command makes no network or model calls and does not modify `data/`, `results/`, or `documents/`.

| Stage | Input → output | What is reproduced |
|---|---|---|
| Collection and extraction | 46 public sources → 382 candidate paraphrases | Saved candidates, source URLs, locators and access dates; full source pages are not distributed |
| Semantic deduplication | 382 → 288 retained + 93 merged + 1 excluded | Replay of recorded AI-assisted judgments, not a new semantic-model assessment |
| Eligibility screening | 288 → 120 eligible/conditionally eligible + 168 outside scope | Recorded item-level rules expanded across eight scenarios |
| Functional selection | 120 → 60 selected + 60 reserves | Functions, comparison IDs and reasons; 60 was not a preset quota |
| Prompts | Common 60-entry pack + scenario + writing instructions | Eight prompts reproduced byte-for-byte against the actual inputs |
| Codex batch | Eight scenarios × five independent calls → 40 responses | Original responses, events and parameter records checked against Word document 08 |
| API batch | Eight scenarios × five independent calls → 40 responses | Original requests, responses and token usage checked against Word document 10 |

**Interface clarification:** the v3 batch previously referred to informally as the web version was actually generated using **Codex CLI authenticated through a ChatGPT account**, not by manually entering prompts in the ChatGPT browser interface. It is labeled `codex_chatgpt`. The CLI requested `gpt-6-astra` with `medium` reasoning effort; its exact serving snapshot was not independently verified.

## Browse the materials

| Directory | Contents |
|---|---|
| `data/corpus/` | 382 candidates, 288 corpus entries, 46 sources, merge mappings and wording decisions |
| `data/selection/` | 288 eligibility decisions, 120 functional decisions, 60 selected entries and 60 reserves |
| `data/scenarios.json`, `data/prompts/` | Eight scenarios, complete writing instructions and references |
| `results/codex_chatgpt/` | 40 Codex responses and original events |
| `results/api/` | 40 API responses, original request/response bodies and records |
| `documents/` | Word documents 01, 02, 07, 08 and 10, plus the teacher's original scenario document |
| `provenance/` | Historical implementation copies, publication logs and verification results |

Documents 08 and 10 represent different generation interfaces; they must not be pooled as ten equivalent replications per scenario. Document 10 contains the current API outputs. Neither batch was rewritten or selected in response to the observation notes. The API observation log is Codex-assisted commentary, not independent human validation, quality scoring, or an automatic exclusion rule. **Researcher-only notes must not be shown to survey evaluators.**

## Verify and package

```bash
python -m unittest discover -s tests -v
python scripts/package.py --verify
python scripts/package.py
```

`--verify` checks the current release inventory, SHA-256 hashes and credential patterns. After intentional code or data changes, inspect those changes and run the packaging command without `--verify` to regenerate the inventory and ZIP. The archive is written to `dist/alex-advice-v3.zip`; it excludes derived `build/` files, new `runs/` output, credentials and Git history.

## Prepare a new generation without calling a model

```bash
python scripts/generate.py --channel api --output runs/api-preview
python scripts/generate.py --channel codex_chatgpt --output runs/codex-preview
```

These commands only prepare 40 request files and a new run protocol. Choose a new, nonexistent output directory under `runs/`. Archived records cannot be overwritten. Use `--scenarios S01 S02` to prepare only those scenarios. Each scenario has five independent requests with identical inputs; later requests are not instructed to differ from earlier ones.

## Optional live generation

The historical API key was disabled for use in this project. It is not included and is not automatically reused.

To run a new batch with **your own new credentials**, first ensure that your account has access to the requested model and sufficient API credit, then run:

```bash
python scripts/generate.py --channel api --output runs/api-new --execute --allow-paid-api
```

If `OPENAI_API_KEY` is not set, the script requests a key through a hidden prompt and does not save it. Do not place keys in code, documentation, or GitHub. Errors or incomplete outputs are retained and stop the run; there is no automatic retry, model substitution, or advice rewriting.

New runs retain each request, raw response and record, and export `generated_advice.jsonl`, `generated_advice.csv`, and `format_checks.json`. Format checks do not replace contextual review or automatically edit or discard responses outside the requested format.

For a new Codex batch, authenticate using your own ChatGPT account:

```bash
codex login
python scripts/generate.py --channel codex_chatgpt --output runs/codex-new --execute
```

The historical CLI version was `0.155.0-alpha.16.3`. Other versions may not support the same isolation options; failures are retained rather than silently weakening isolation. New model calls are not guaranteed to produce identical text. **Release validation covers offline replay, request preparation and mocked network tests; no new paid calls were made with the disabled key.**

## Upload to GitHub

Upload this project directory, not the original desktop workspace or unrelated archives. For a new local repository and an empty GitHub repository:

```bash
git init
git add .
git commit -m "Add reproducible Alex advice v3 materials"
git branch -M main
git remote add origin https://github.com/YOUR_ACCOUNT/YOUR_REPOSITORY.git
git push -u origin main
```

Replace `YOUR_ACCOUNT/YOUR_REPOSITORY`. If the repository is already initialized, stage and commit only the intended updates instead of repeating initialization. Packaging does not publish remotely. GitHub Actions runs offline reproduction, tests and inventory checks on Windows/Linux, without model credentials.

## Research and translation boundaries

The main comparison is **reference-supported AI advice versus independently written advice from ordinary adults**. Differences cannot be attributed solely to intrinsic AI or human ability. Five responses to one scenario may be highly similar; they do not necessarily represent five different strategies. This package covers completed material preparation and generation, not future human-response collection or evaluation-study findings.

Recorded decisions support reconstruction of the corpus, references and prompts, and verification of historical outputs. Re-fetching websites, re-adjudicating decisions or calling a cloud model again is not guaranteed to yield identical results.

This English release translates research annotations, explanatory text and one historical operating-system error message. Annotation keys ending in `_zh` are renamed `_en`, and replay scripts use the same translations. The English advice corpus text, eight scenarios, generation instructions, actual request bodies and all 80 advice texts are unchanged. `provenance/english_translation_log.json` records before/after file hashes. Historical generation-time hashes remain historical; `MANIFEST.sha256.json` identifies the current English release.
