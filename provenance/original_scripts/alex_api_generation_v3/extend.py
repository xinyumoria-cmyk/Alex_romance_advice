"""Freeze S03-S08 inputs without replacing the original ten-response records."""
import json
import shutil
from run import ROOT, SOURCE, sha, save, now

target = ROOT / 'protocol_40.json'
if target.exists():
    raise SystemExit('Forty-response protocol already exists; no changes made.')
original = json.loads((SOURCE / 'protocol.json').read_text(encoding='utf-8-sig'))
prior = json.loads((ROOT / 'protocol.json').read_text(encoding='utf-8-sig'))
assert prior['reference_pack_sha256'] == original['reference_pack_sha256']
assert len(list((ROOT / 'records').glob('*.json'))) == 10
baseline = {}
for folder in ('records', 'responses', 'raw', 'requests'):
    for file in (ROOT / folder).rglob('*'):
        if file.is_file():
            baseline[str(file.relative_to(ROOT))] = sha(file)
for name in ('protocol.json', 'checks.json', 'generated_advice.jsonl', 'collect.ps1'):
    baseline[name] = sha(ROOT / name)
save(ROOT / 'first_ten_baseline.json', baseline)
inputs = dict(prior['inputs'])
tasks = []
for task in original['tasks']:
    tasks.append(dict(task, task_id='API-' + task['task_id']))
    relative = task['prompt_file']
    assert sha(SOURCE / relative) == task['prompt_sha256']
    inputs[relative] = task['prompt_sha256']
    if not (ROOT / relative).exists():
        shutil.copyfile(SOURCE / relative, ROOT / relative)
for relative, expected in inputs.items():
    assert sha(ROOT / relative) == expected
assert len(tasks) == 40 and len({x['task_id'] for x in tasks}) == 40
protocol = dict(prior, batch_id='alex-api-reference-v3-all-eight-2026-09-30',
    extended_utc=now(), expected=40, tasks=tasks, inputs=inputs,
    authorization='User authorized remaining 30 responses: S03-S08, five each. Preserve previous S01-S02 API responses and parameters.',
    policy='Forty independent calls, first ten retained. No history, tools, or automatic retries. Keep first output including failures and incomplete outputs. No rewriting or selection.')
save(target, protocol)
save(ROOT / 'status.json', dict(status='prepared_remaining_30', completed=10, expected=40))
print('Frozen all eight inputs; preserved ten outputs; thirty new calls authorized.')
