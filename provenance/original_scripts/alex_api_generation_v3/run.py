"""Generate authorized tasks, retaining completed records and all attempts."""
import getpass
import hashlib
import json
import re
import shutil
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT.parent / 'alex_direct_generation_v3'

def now():
    return datetime.now(timezone.utc).isoformat()

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()

def save(path, obj):
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding='utf-8')

def prepare():
    if (ROOT / 'protocol_40.json').exists():
        return json.loads((ROOT / 'protocol_40.json').read_text(encoding='utf-8-sig'))
    if (ROOT / 'protocol.json').exists():
        return json.loads((ROOT / 'protocol.json').read_text(encoding='utf-8-sig'))
    original = json.loads((SOURCE / 'protocol.json').read_text(encoding='utf-8-sig'))
    for folder in ('prompts', 'raw', 'responses', 'records', 'requests'):
        (ROOT / folder).mkdir(exist_ok=True)
    inputs = {'generation_instructions.txt': original['instructions_sha256']}
    tasks = []
    for task in original['tasks']:
        if task['scenario_id'] not in ('S01', 'S02'):
            continue
        inputs[task['prompt_file']] = task['prompt_sha256']
        tasks.append(dict(task, task_id='API-' + task['task_id']))
    assert len(tasks) == 10
    for relative, expected in inputs.items():
        assert sha(SOURCE / relative) == expected, relative
        shutil.copyfile(SOURCE / relative, ROOT / relative)
    protocol = dict(batch_id='alex-api-reference-v3-s01-s02-2026-09-30',
        prepared_utc=now(), endpoint='https://api.openai.com/v1/responses',
        model='gpt-6-astra', reasoning={'effort': 'medium'}, max_output_tokens=8192,
        store=False, reference_count=60, reference_pack_sha256=original['reference_pack_sha256'],
        inputs=inputs, tasks=tasks, expected=10,
        policy='Ten independent calls; no history, tools, or automatic retries. Keep first output including failures and incomplete outputs. No rewriting or selection.',
        authorization='User explicitly requested S01 and S02, five responses each, using supplied OpenAI API key.',
        source_interface='OpenAI Responses API; separate from historical Codex CLI outputs')
    save(ROOT / 'protocol.json', protocol)
    save(ROOT / 'status.json', dict(status='prepared', completed=0, expected=10))
    return protocol

def main():
    if (ROOT / 'API_DISABLED.json').exists():
        raise SystemExit('API use disabled at user request. No key will be requested and no API call will be made.')
    protocol = prepare()
    if '--prepare' in sys.argv:
        print(f'Prepared {protocol["expected"]} tasks with verified frozen v3 inputs.', flush=True)
        return
    if '--retry-network-block' in sys.argv:
        prior = json.loads((ROOT / 'status.json').read_text(encoding='utf-8'))
        failure = prior.get('failure', {})
        if prior.get('status') != 'blocked_transport' or '[WinError 10013]' not in failure.get('detail', ''):
            raise SystemExit('Retry permitted only after a confirmed local socket permission denial.')
        archive = ROOT / 'raw' / 'local_socket_denial'
        archive.mkdir(exist_ok=False)
        for path in (ROOT / 'raw').glob(failure['task_id'] + '.*'):
            destination = archive / path.name
            assert path.resolve().is_relative_to(ROOT.resolve())
            assert destination.resolve().is_relative_to(ROOT.resolve())
            path.rename(destination)
    for relative, expected in protocol['inputs'].items():
        assert sha(ROOT / relative) == expected, 'Frozen input changed: ' + relative
    key = getpass.getpass('API key (hidden; not saved): ')
    if not key.startswith('sk-'):
        raise SystemExit('No valid-format API key supplied.')
    instructions = (ROOT / 'generation_instructions.txt').read_text(encoding='utf-8-sig')
    completed = len(list((ROOT / 'records').glob('*.json')))
    for task in protocol['tasks']:
        if (ROOT / 'API_DISABLED.json').exists():
            key = None
            raise SystemExit('API use disabled at user request. Stopping before the next request.')
        tid = task['task_id']
        if (ROOT / 'records' / (tid + '.json')).exists():
            continue
        if list((ROOT / 'raw').glob(tid + '.*')):
            raise SystemExit('Prior attempt retained; review before retry: ' + tid)
        payload = dict(model=protocol['model'], reasoning=protocol['reasoning'],
            max_output_tokens=protocol['max_output_tokens'], store=False,
            instructions=instructions,
            input=(ROOT / task['prompt_file']).read_text(encoding='utf-8-sig'))
        save(ROOT / 'requests' / (tid + '.json'), payload)
        save(ROOT / 'raw' / (tid + '.launch.json'), dict(task_id=tid, started_utc=now()))
        request = urllib.request.Request(protocol['endpoint'],
            data=json.dumps(payload).encode('utf-8'), method='POST',
            headers={'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json'})
        print('Requesting ' + tid, flush=True)
        try:
            with urllib.request.urlopen(request, timeout=240) as response:
                raw = response.read().decode('utf-8')
                request_id = response.headers.get('x-request-id')
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode('utf-8', errors='replace')
            detail = re.sub(r'sk-[A-Za-z0-9_.*-]+', '[REDACTED_KEY]', detail.replace(key, '[REDACTED_KEY]'))
            failure = dict(task_id=tid, status='http_error', http_status=exc.code,
                detail=detail, request_id=exc.headers.get('x-request-id'), ended_utc=now())
            save(ROOT / 'raw' / (tid + '.error.json'), failure)
            save(ROOT / 'status.json', dict(status='blocked_http_error', completed=completed, expected=protocol['expected'], failure=failure))
            print(json.dumps(failure, ensure_ascii=True), flush=True)
            return
        except Exception as exc:
            failure = dict(task_id=tid, status='transport_error_outcome_unknown',
                error_type=type(exc).__name__, detail=str(exc).replace(key, '[REDACTED_KEY]'), ended_utc=now())
            save(ROOT / 'raw' / (tid + '.error.json'), failure)
            save(ROOT / 'status.json', dict(status='blocked_transport', completed=completed, expected=protocol['expected'], failure=failure))
            print(json.dumps(failure, ensure_ascii=True), flush=True)
            return
        (ROOT / 'raw' / (tid + '.response.json')).write_text(raw, encoding='utf-8')
        data = json.loads(raw)
        texts = [part['text'] for item in data.get('output', []) if item.get('type') == 'message'
                 for part in item.get('content', []) if part.get('type') == 'output_text']
        advice = '\n\n'.join(texts)
        (ROOT / 'responses' / (tid + '.txt')).write_text(advice, encoding='utf-8')
        record = dict(task_id=tid, scenario_id=task['scenario_id'], replicate=task['replicate'],
            response_id=data.get('id'), request_id=request_id, model_returned=data.get('model'),
            status=data.get('status'), usage=data.get('usage'), ended_utc=now(),
            advice=advice, word_count=len(advice.split()), paragraph_count=len(re.split(r'\n\s*\n', advice.strip())),
            response_sha256=sha(ROOT / 'responses' / (tid + '.txt')))
        save(ROOT / 'raw' / (tid + '.result.json'), record)
        if data.get('status') != 'completed' or not advice.strip():
            save(ROOT / 'status.json', dict(status='incomplete_requires_review', completed=completed, expected=protocol['expected'], task_id=tid))
            print('Incomplete output retained; stopping: ' + tid, flush=True)
            return
        save(ROOT / 'records' / (tid + '.json'), record)
        completed += 1
        save(ROOT / 'status.json', dict(status='complete' if completed == protocol['expected'] else 'in_progress', completed=completed, expected=protocol['expected']))
        print(f'Completed {tid}; {completed}/{protocol["expected"]}; words={record["word_count"]}', flush=True)
    key = None

if __name__ == '__main__':
    main()
