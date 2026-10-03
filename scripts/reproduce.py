"""Offline replay of recorded decisions and verification of both generation batches.

Python 3.10+, standard library only. Does not fetch websites or call a model.
"""
import argparse
from collections import Counter, defaultdict
import csv
import hashlib
import json
from pathlib import Path
import re
import shutil
import zipfile
from xml.etree import ElementTree as ET
from corpus_rules import applicability

ROOT = Path(__file__).resolve().parents[1]
WORDS = re.compile(r"\b[\w]+(?:['\u2019\-\u2010\u2011][\w]+)*\b")

def check(condition, message):
    if not condition:
        raise ValueError(message)

def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))

def lines(path):
    return [json.loads(x) for x in Path(path).read_text(encoding='utf-8-sig').splitlines() if x.strip()]

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')

def write_lines(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(''.join(json.dumps(x, ensure_ascii=False) + '\n' for x in data), encoding='utf-8', newline='\n')

def table(path, delimiter='|'):
    with path.open(encoding='utf-8-sig', newline='') as stream:
        return list(csv.DictReader(stream, delimiter=delimiter))

def replay_corpus(root):
    folder = root / 'data/corpus'
    candidates = lines(folder / 'candidate_extractions.jsonl')
    sources = {s['id']:s for s in read(folder / 'sources.json')}
    decisions = read(folder / 'semantic_decisions.json')
    overrides = read(folder / 'canonical_overrides.json')
    overrides.update(read(folder / 'final_review_adjustments.json')['overrides'])
    aliases = {x['from']:x['to'] for x in decisions['aliases']}
    reasons = {x['from']:x['reason_en'] for x in decisions['aliases']}
    excluded = {x['key']:x['reason_en'] for x in decisions['excluded_keys']}
    def canonical(key):
        seen = set()
        while key in aliases:
            check(key not in seen, 'Semantic alias cycle')
            seen.add(key)
            key = aliases[key]
        return key
    groups = defaultdict(list)
    for row in candidates:
        check(row['source_id'] in sources, 'Unknown source')
        if row['key'] not in excluded:
            groups[canonical(row['key'])].append(row)
    corpus, log = [], []
    for key, members in groups.items():
        representative = next((r for r in members if r['key'] == key), members[0])
        aid = f'ADV{len(corpus)+1:04d}'
        source_ids = list(dict.fromkeys(r['source_id'] for r in members))
        corpus.append(dict(advice_id=aid, concept_key=key, advice_en=overrides.get(key, representative['text']),
            language='en', text_status='AI-normalized source-grounded paraphrase; not verbatim',
            scopes=sorted({r['scope'] for r in members}), stages=sorted({r['stage'] for r in members}),
            topics=sorted({r['topic'] for r in members}), applicability_en=applicability(key, members),
            source_contexts=sorted({r['source_context'] for r in members}), source_ids=source_ids,
            source_jurisdictions=sorted({sources[s]['jurisdiction'] for s in source_ids}),
            candidate_ids=[r['candidate_id'] for r in members], candidate_count=len(members),
            provenance=[dict(source_id=r['source_id'], url=r['source_url'], locator=r['locator'],
                candidate_id=r['candidate_id'], original_scope=r['scope'], original_stage=r['stage']) for r in members],
            semantic_review='AI contextual comparison plus explicit cluster decisions; no independent human adjudication',
            study_use='AI corpus only; not a human-participant response', collected_on='2026-09-18'))
        for r in members:
            k, changes = r['key'], []
            while k in aliases:
                changes.append(reasons[k]); k = aliases[k]
            is_rep = r['candidate_id'] == representative['candidate_id']
            log.append(dict(candidate_id=r['candidate_id'], source_id=r['source_id'], input_key=r['key'],
                advice_id=aid, final_key=key, disposition='representative' if is_rep else 'merged',
                reason_en='; '.join(changes) if changes else ('Representative candidate for this semantic group.' if is_rep else 'The action and applicability conditions are materially the same as the group representative; independent provenance is retained.'),
                canonical_wording_revised=key in overrides))
    for r in candidates:
        if r['key'] in excluded:
            log.append(dict(candidate_id=r['candidate_id'], source_id=r['source_id'], input_key=r['key'],
                advice_id=None, final_key=None, disposition='excluded', reason_en=excluded[r['key']]))
    log.sort(key=lambda x:x['candidate_id'])
    check(corpus == lines(folder / 'advice_corpus.jsonl'), 'Replayed corpus differs from archived 288')
    check(log == lines(folder / 'deduplication_log.jsonl'), 'Replayed merge log differs')
    check(len(candidates) == 382 and len(corpus) == 288, 'Unexpected corpus counts')
    check(Counter(x['disposition'] for x in log) == {'representative':288, 'merged':93, 'excluded':1}, 'Deduplication counts differ')
    return corpus, log

def replay_selection(root, corpus, scenarios):
    folder = root / 'data/selection'
    eligibility = table(folder / 'eligibility_decisions.tsv')
    functional = table(folder / 'functional_review.tsv')
    check(len(eligibility) == len({x['id'] for x in eligibility}) == 288, 'Eligibility coverage')
    check(len(functional) == len({x['id'] for x in functional}) == 120, 'Functional coverage')
    eidx, fidx = ({x['id']:x for x in rows} for rows in [eligibility, functional])
    check({x['id'] for x in eligibility if x['rule'] != 'N'} == set(fidx), 'Eligible/functional ID mismatch')
    archived = {x['advice_id']:x for x in lines(folder / 'advice_screening_288.jsonl')}
    selected, reserve, matrix = [], [], []
    for item in corpus:
        aid = item['advice_id']; d = eidx[aid]; f = fidx.get(aid)
        check(d['rule'] in {'D','C','N','MONEY','EMOTION'}, 'Unknown eligibility rule')
        check(not f or f['decision'] in {'S1','S2','S3','R1','R2','R3','R4'}, 'Unknown functional rule')
        included = bool(f and f['decision'].startswith('S'))
        old = archived[aid]['screening']
        check({k:archived[aid][k] for k in item} == item, 'Selection changed source paraphrase')
        check(included == old['in_prompt_pack'] and (d['rule'] != 'N') == old['eligible'], 'Selection status mismatch')
        check(d['guard'] == old['use_guard'] and d['reason'] == old['eligibility_reason'], 'Eligibility rationale mismatch')
        if f:
            check(f['comparative_reason'] == old['prompt_selection_reason'] and f['function'] == old['function'], 'Functional rationale mismatch')
            check(set(f['related_ids'].split(',')) <= set(fidx), 'Missing comparison ID')
            (selected if included else reserve).append(dict(item, screening=old))
        for scenario in scenarios:
            sid = scenario['scenario_id']
            classification = d['rule']
            if classification == 'MONEY':
                classification = 'D' if scenario['financial_cue'] == 'present' else 'C'
            if classification == 'EMOTION':
                classification = 'D' if scenario['emotional_intensity'] == 'high' else 'C'
            matrix.append(dict(advice_id=aid, scenario_id=sid, classification=classification,
                eligibility_reason=d['reason'], use_guard=d['guard'], in_prompt_pack=included,
                selection_reason=old['prompt_selection_reason']))
    check(len(selected) == len(reserve) == 60, '60/60 split mismatch')
    for name, rows in [('prompt_pack_60.jsonl', selected), ('eligible_reserve.jsonl', reserve)]:
        expected = lines(folder / name)
        check([{k:r[k] for k in rows[0]} for r in expected] == rows, 'Selected/reserve contents differ')
    check(matrix == lines(folder / 'scenario_applicability_2304.jsonl'), 'Scenario matrix mismatch')
    selected_ids = {x['advice_id'] for x in selected}
    for f in functional:
        if f['decision'] == 'R1':
            check(bool(set(f['related_ids'].split(',')) & selected_ids), 'Reserve lacks selected comparator')
    for a,b in [('ADV0005','ADV0240'),('ADV0153','ADV0241'),('ADV0137','ADV0182'),('ADV0137','ADV0257'),('ADV0021','ADV0121'),('ADV0154','ADV0158'),('ADV0070','ADV0269')]:
        check({a,b} <= selected_ids, 'Missing complementary safeguard')
    check(all(x['screening']['domain'] != 'delivery' for x in selected), 'Role-rule violation')
    return selected, reserve, matrix

def rebuild_prompts(root, selected, scenarios):
    ref = '\n\n'.join(f'[{x["advice_id"]}] RECIPIENT ADVICE REFERENCE\n{x["advice_en"]}\nApplicability guard: {x["screening"]["use_guard"]}' for x in selected)
    prompts = {}
    for s in scenarios:
        sid = s['scenario_id']
        prompts[sid] = f'SCENARIO\n{s["scenario_text"]}\n\nQUESTION\n{s["question"]}\n\nCONDITION METADATA\nurgency={s["urgency"]}; financial_cue={s["financial_cue"]}; emotional_intensity={s["emotional_intensity"]}\n\nREFERENCE MATERIALS (60 entries; common to all eight scenarios)\n{ref}'
        check(prompts[sid].encode('utf-8') == (root / f'data/prompts/{sid}.txt').read_bytes(), 'Prompt bytes differ: ' + sid)
    return prompts

def verify_results(root, channel, prompts):
    folder = root / 'results' / channel
    instructions = (root / 'data/prompts/generation_instructions.txt').read_text(encoding='utf-8-sig')
    protocol = read(folder / ('protocol_40.json' if channel == 'api' else 'protocol.json'))
    records = [read(p) for p in sorted((folder / 'records').glob('*.json'))]
    tasks = {t['task_id']:t for t in protocol['tasks']}
    check(len(records) == len(tasks) == 40, 'Expected forty records/tasks')
    normalized, totals = [], Counter()
    session_ids = []
    for record in records:
        tid, sid = record['task_id'], record['scenario_id']; task = tasks[tid]
        check(sid == task['scenario_id'] and record['replicate'] == task['replicate'], 'Task mapping mismatch')
        check(hashlib.sha256(prompts[sid].encode()).hexdigest().upper() == task['prompt_sha256'].upper(), 'Task prompt hash mismatch')
        response_path = folder / f'responses/{tid}.txt'
        # File hashes preserve original bytes; text comparison normalizes Windows newlines.
        text = response_path.read_text(encoding='utf-8-sig')
        check(sha(response_path).upper() == record['response_sha256'].upper(), 'Advice hash mismatch: ' + tid)
        check(record['status'] == 'completed', 'Incomplete archived response')
        if channel == 'api':
            request = read(folder / f'requests/{tid}.json')
            expected = dict(model='gpt-6-astra', reasoning={'effort':'medium'}, max_output_tokens=8192,
                            store=False, instructions=instructions, input=prompts[sid])
            check(request == expected, 'API request parameters or context differ')
            raw = read(folder / f'raw/{tid}.response.json')
            raw_text = '\n\n'.join(c['text'] for x in raw['output'] if x['type'] == 'message' for c in x['content'] if c['type'] == 'output_text')
            check(raw_text == text == record['advice'] and raw['status'] == 'completed', 'API raw-text mismatch')
            check(raw['model'] == record['model_returned'] == 'gpt-6-astra', 'Returned model mismatch')
            check(raw['usage'] == record['usage'] and raw['id'] == record['response_id'], 'API usage/ID mismatch')
            session_ids.append(raw['id'])
            usage = raw['usage']; totals['input_tokens'] += usage['input_tokens']; totals['output_tokens'] += usage['output_tokens']
        else:
            check(record['requested_model'] == 'gpt-6-astra' and record['reasoning_effort'] == 'medium', 'CLI parameter mismatch')
            events = lines(folder / f'raw/{tid}-attempt{record["attempt"]}.events.jsonl')
            messages = [e['item']['text'] for e in events if e['type'] == 'item.completed' and e['item']['type'] == 'agent_message']
            check(len(messages) == 1 and messages[0].strip() == text.strip(), 'CLI event/text mismatch')
            check(any(e['type'] == 'turn.completed' for e in events), 'CLI completion absent')
            check(not record['unexpected_tool_events'], 'CLI tool event present')
            session_ids.append(record['thread_id'])
            usage = record['usage'][0]; totals['input_tokens'] += usage['input_tokens']; totals['output_tokens'] += usage['output_tokens']
        normalized.append(dict(channel=channel, task_id=tid, scenario_id=sid, replicate=record['replicate'],
            advice=text, word_count=len(WORDS.findall(text)), paragraphs=len(re.split(r'\n\s*\n', text.strip())), sha256=sha(response_path)))
    check(len(set(session_ids)) == 40, 'Duplicate request/session IDs')
    check(Counter(x['scenario_id'] for x in normalized) == {f'S{i:02d}':5 for i in range(1,9)}, 'Unbalanced scenarios')
    check(len({x['sha256'] for x in normalized}) == 40, 'Exact duplicate responses')
    return normalized, dict(totals)

def verify_word(root, channel, rows):
    name = '08 - Alex GPT-6 Advice - 40 Responses - Reference v3.docx' if channel == 'codex_chatgpt' else '10 - Alex GPT-6 API Advice - 40 Responses - Reference v3.docx'
    with zipfile.ZipFile(root / 'documents' / name) as archive:
        doc = ET.fromstring(archive.read('word/document.xml'))
    ns = {'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
    paragraphs = [''.join(t.text or '' for t in p.findall('.//w:t', ns)) for p in doc.findall('.//w:p', ns)]
    for item in rows:
        for p in re.split(r'\n\s*\n', item['advice'].strip()):
            check(p in paragraphs, 'Word advice text missing: ' + item['task_id'])

def reproduce(root=ROOT, output=None):
    output = Path(output or root / 'build').resolve()
    root = Path(root).resolve()
    # Never place derived exports over immutable source data or historical outputs.
    for protected in ['data','results','documents','scripts','provenance','.github']:
        check(not output.is_relative_to(root / protected), 'Output overlaps protected package content')
    check(output != root and not root.is_relative_to(output), 'Unsafe output directory')
    corpus, log = replay_corpus(root)
    scenarios = read(root / 'data/scenarios.json')
    check(len(scenarios) == 8 and len({s['scenario_id'] for s in scenarios}) == 8, 'Eight scenarios required')
    check(len({(s['urgency'],s['financial_cue'],s['emotional_intensity']) for s in scenarios}) == 8, 'Factorial coverage')
    selected, reserve, matrix = replay_selection(root, corpus, scenarios)
    prompts = rebuild_prompts(root, selected, scenarios)
    for name, data in [('corpus_288',corpus),('deduplication_log',log),('selected_60',selected),('reserve_60',reserve),('scenario_matrix_2304',matrix)]:
        write_lines(output / (name + '.jsonl'), data)
    for sid, prompt in prompts.items():
        path = output / 'prompts' / (sid + '.txt'); path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(prompt.encode('utf-8'))
    shutil.copyfile(root / 'data/prompts/generation_instructions.txt', output / 'prompts/generation_instructions.txt')
    summary = dict(candidates=382, corpus=288, eligible=120, selected=60, reserve=60, outside_scope=168, scenario_matrix=2304, batches={})
    for channel in ['codex_chatgpt','api']:
        rows, usage = verify_results(root, channel, prompts)
        verify_word(root, channel, rows)
        write_lines(output / f'{channel}_40.jsonl', rows)
        with (output / f'{channel}_40.csv').open('w', encoding='utf-8-sig', newline='') as stream:
            writer = csv.DictWriter(stream, fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)
        summary['batches'][channel] = dict(count=len(rows), min_words=min(x['word_count'] for x in rows),
            max_words=max(x['word_count'] for x in rows), outside_word_limit=[x['task_id'] for x in rows if not 120 <= x['word_count'] <= 180],
            usage=usage, advice_matches_published_word=True)
    (output / 'documents').mkdir(exist_ok=True)
    for p in (root / 'documents').glob('*.docx'):
        shutil.copyfile(p, output / 'documents' / p.name)
    summary['limitations'] = ['Recorded decision replay, not new source collection or independent semantic adjudication.',
        'Historical outputs verified; no live inference performed. Future generations cannot be guaranteed identical.',
        'Word documents copied from archived publication versions; visual layout not re-rendered.']
    write(output / 'verification_report.json', summary)
    return summary

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    print(json.dumps(reproduce(output=args.output), ensure_ascii=False, indent=2))
