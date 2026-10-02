"""Prepare new requests; live model calls require explicit opt-in and new credentials.

Historical results are never changed. No stored key is included or read from the project.
"""
import argparse
import csv
from datetime import datetime, timezone
import getpass
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import urllib.error
import urllib.request
from reproduce import ROOT, WORDS, check, read, write, write_lines, sha, rebuild_prompts, replay_corpus, replay_selection

DISABLED_FEATURES = ['memories','multi_agent','multi_agent_v2','apps','plugins','hooks','shell_tool',
    'unified_exec','browser_use','browser_use_external','computer_use','image_generation','view_image',
    'skill_search','workspace_dependencies']

def timestamp():
    return datetime.now(timezone.utc).isoformat()

def redact(text, key=''):
    if key:
        text = text.replace(key, '[REDACTED]')
    return re.sub(r'(?:sk-(?:proj-|svcacct-)?|nvapi-)[A-Za-z0-9_.*-]{12,}', '[REDACTED]', text)

def request_payload(sid):
    return dict(model='gpt-6-astra', reasoning={'effort':'medium'}, max_output_tokens=8192,
        store=False, instructions=(ROOT / 'data/prompts/generation_instructions.txt').read_text(encoding='utf-8-sig'),
        input=(ROOT / f'data/prompts/{sid}.txt').read_text(encoding='utf-8-sig'))

def api_call(payload, key):
    request = urllib.request.Request('https://api.openai.com/v1/responses',
        data=json.dumps(payload).encode('utf-8'), method='POST',
        headers={'Authorization':'Bearer ' + key, 'Content-Type':'application/json'})
    with urllib.request.urlopen(request, timeout=240) as response:
        return response.read().decode('utf-8'), response.headers.get('x-request-id')

def codex_args(executable, temp, output):
    args = [executable,'exec','--ignore-user-config','--ephemeral','--skip-git-repo-check',
        '--sandbox','read-only','--model','gpt-6-astra','--cd',str(temp),'--json','--color','never',
        '--output-last-message',str(output),'-c','model_reasoning_effort="medium"',
        '-c','model_provider="openai"','-c','approval_policy="never"','-c','web_search="disabled"',
        '-c','project_doc_max_bytes=0','-c','personality="none"',
        '-c','model_instructions_file=' + json.dumps((ROOT / 'data/prompts/generation_instructions.txt').as_posix())]
    for feature in DISABLED_FEATURES:
        args.extend(['--disable', feature])
    return args + ['-']

def run(args):
    corpus, _ = replay_corpus(ROOT)
    scenarios = read(ROOT / 'data/scenarios.json')
    selected, _, _ = replay_selection(ROOT, corpus, scenarios)
    rebuild_prompts(ROOT, selected, scenarios)
    chosen = args.scenarios or [f'S{i:02d}' for i in range(1,9)]
    check(len(set(chosen)) == len(chosen) and set(chosen) <= {s['scenario_id'] for s in scenarios}, 'Invalid scenarios')
    task_order = read(ROOT / 'results/codex_chatgpt/protocol.json')['tasks']
    tasks = [dict(t, task_id='NEW-' + t['task_id']) for t in task_order if t['scenario_id'] in chosen]
    # Require a new child of runs/, isolating all mutations from archived results.
    out = Path(args.output).resolve()
    check(out.is_relative_to((ROOT / 'runs').resolve()) and out != (ROOT / 'runs').resolve(), 'Use a new output directory under runs/')
    check(not out.exists(), 'Output already exists; no overwriting or implicit retries')
    if args.execute and args.channel == 'api':
        check(args.allow_paid_api, 'Live API generation also requires --allow-paid-api')
    out.mkdir(parents=True)
    for folder in ['requests','raw','responses','records']:
        (out / folder).mkdir()
    write(out / 'protocol.json', dict(channel=args.channel, created_at=timestamp(), execute=args.execute,
        model='gpt-6-astra', reasoning_effort='medium', reference_count=60, tasks=tasks,
        instructions_sha256=sha(ROOT / 'data/prompts/generation_instructions.txt'),
        prompt_sha256={sid:sha(ROOT / f'data/prompts/{sid}.txt') for sid in chosen},
        note='New replication; model alias and service behavior may change. No guarantee of identical output.'))
    for task in tasks:
        write(out / 'requests' / (task['task_id'] + '.json'), request_payload(task['scenario_id']))
    if not args.execute:
        write(out / 'status.json', dict(status='dry_run_no_network', prepared=len(tasks), completed=0))
        print(f'Prepared {len(tasks)} independent requests. No credentials requested; no network calls.')
        return
    key = ''
    executable = None
    env = dict(os.environ)
    try:
        if args.channel == 'api':
            key = os.environ.get('OPENAI_API_KEY') or getpass.getpass('New API key (not saved): ')
            check(key.startswith('sk-'), 'Provide a valid API key through environment or hidden prompt')
        else:
            executable = shutil.which('codex')
            check(bool(executable), 'Codex CLI required; recorded original version: 0.155.0-alpha.16.3')
            for name in ['OPENAI_API_KEY','CODEX_API_KEY','CODEX_ACCESS_TOKEN','CODEX_THREAD_ID']:
                env.pop(name, None)
            login = subprocess.run([executable,'login','status'], env=env, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=30)
            check('Logged in using ChatGPT' in login.stdout + login.stderr, 'Log in to Codex with a ChatGPT account before running')
            version = subprocess.run([executable,'--version'], env=env, capture_output=True, text=True, timeout=30)
            write(out / 'cli_version.json', dict(version=version.stdout.strip()))
        completed = 0
        collected = []
        for task in tasks:
            tid = task['task_id']
            write(out / 'raw' / (tid + '.launch.json'), dict(task_id=tid, started=timestamp()))
            print('Generating ' + tid, flush=True)
            try:
                if args.channel == 'api':
                    raw_text, request_id = api_call(request_payload(task['scenario_id']), key)
                    (out / 'raw' / (tid + '.response.json')).write_text(raw_text, encoding='utf-8', newline='\n')
                    raw = json.loads(raw_text)
                    text = '\n\n'.join(c['text'] for x in raw.get('output',[]) if x['type'] == 'message' for c in x['content'] if c['type'] == 'output_text')
                    record = dict(status=raw.get('status'), model_returned=raw.get('model'), response_id=raw.get('id'), request_id=request_id, usage=raw.get('usage'))
                else:
                    with tempfile.TemporaryDirectory(prefix='alex-v3-') as temp:
                        target = out / 'responses' / (tid + '.txt')
                        result = subprocess.run(codex_args(executable, temp, target),
                            input=request_payload(task['scenario_id'])['input'], env=env, cwd=temp,
                            capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=600)
                        events_text = result.stdout.replace(temp, '<ISOLATED_TEMP>')
                        (out / 'raw' / (tid + '.events.jsonl')).write_text(events_text, encoding='utf-8')
                        (out / 'raw' / (tid + '.stderr.txt')).write_text(redact(result.stderr), encoding='utf-8')
                        events = [json.loads(x) for x in events_text.splitlines() if x.strip()]
                        messages = [e['item']['text'] for e in events if e['type']=='item.completed' and e['item']['type']=='agent_message']
                        check(result.returncode == 0 and any(e['type']=='turn.completed' for e in events), 'CLI generation failed; inspect retained events')
                        check(len(messages) == 1 and target.exists(), 'CLI response is missing or ambiguous')
                        check(not any(e['type']=='item.completed' and e['item']['type'] not in {'agent_message','reasoning'} for e in events), 'Unexpected CLI tool use')
                        text = target.read_text(encoding='utf-8-sig')
                        check(text.strip() == messages[0].strip(), 'CLI output/event mismatch')
                        record = dict(status='completed', model_requested='gpt-6-astra', serving_snapshot=None,
                            usage=[e['usage'] for e in events if e['type']=='turn.completed'])
                (out / 'responses' / (tid + '.txt')).write_text(text, encoding='utf-8', newline='\n')
                check(record['status']=='completed' and text.strip(), 'Incomplete output retained; no automatic retry')
                if args.channel == 'api':
                    check(record['model_returned'] == 'gpt-6-astra', 'Unexpected returned model; retained, stopping')
                record.update(task_id=tid, scenario_id=task['scenario_id'], replicate=task['replicate'],
                    completed_at=timestamp(), response_sha256=sha(out / 'responses' / (tid + '.txt')))
                write(out / 'records' / (tid + '.json'), record)
                collected.append(dict(task_id=tid, scenario_id=task['scenario_id'], replicate=task['replicate'],
                    advice=text, word_count=len(WORDS.findall(text)), paragraphs=len(re.split(r'\n\s*\n',text.strip()))))
                write_lines(out / 'generated_advice.jsonl', collected)
                with (out / 'generated_advice.csv').open('w',encoding='utf-8-sig',newline='') as stream:
                    writer=csv.DictWriter(stream,fieldnames=list(collected[0])); writer.writeheader(); writer.writerows(collected)
                write(out / 'format_checks.json', dict(completed=len(collected),
                    outside_word_limit=[r['task_id'] for r in collected if not 120 <= r['word_count'] <= 180],
                    outside_paragraph_limit=[r['task_id'] for r in collected if r['paragraphs'] not in (2,3)],
                    semantic_review='Not performed automatically; all first outputs retained unchanged.'))
                completed += 1
                write(out / 'status.json', dict(status='complete' if completed==len(tasks) else 'in_progress', completed=completed, expected=len(tasks)))
                print(f'Completed {completed}/{len(tasks)}', flush=True)
            except Exception as exc:
                detail = exc.read().decode('utf-8', errors='replace') if isinstance(exc, urllib.error.HTTPError) else str(exc)
                failure = dict(status='stopped_failure_no_retry', task_id=tid, completed=completed,
                    error_type=type(exc).__name__, http_status=getattr(exc,'code',None), detail=redact(detail,key))
                write(out / 'status.json', failure)
                write(out / 'raw' / (tid + '.error.json'), failure)
                raise RuntimeError('Generation stopped. Inspect redacted status.json; no automatic retry.') from None
    finally:
        key = ''

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--channel', choices=['api','codex_chatgpt'], required=True)
    parser.add_argument('--scenarios', nargs='+')
    parser.add_argument('--output', required=True)
    parser.add_argument('--execute', action='store_true')
    parser.add_argument('--allow-paid-api', action='store_true')
    run(parser.parse_args())
