import argparse
import contextlib
import io
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import reproduce as rp
import generate
import package

class ReproductionTests(unittest.TestCase):
    def test_full_offline_replay(self):
        with tempfile.TemporaryDirectory() as temp:
            report = rp.reproduce(output=Path(temp) / 'output')
            self.assertEqual((report['corpus'],report['selected'],report['reserve']), (288,60,60))
            self.assertEqual(report['batches']['api']['count'],40)
            self.assertEqual(report['batches']['codex_chatgpt']['count'],40)
            self.assertEqual(report['batches']['api']['usage'], {'input_tokens':135540,'output_tokens':9427})

    def test_protected_output_rejected(self):
        for path in [rp.ROOT, rp.ROOT / 'results/overwrite', rp.ROOT / 'data/overwrite']:
            with self.assertRaises(ValueError):
                rp.reproduce(output=path)

    def test_changed_decision_is_detected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            shutil.copytree(rp.ROOT / 'data',root / 'data')
            corpus,_ = rp.replay_corpus(root)
            path = root / 'data/selection/functional_review.tsv'
            text = path.read_text(encoding='utf-8-sig').replace('|S1|','|R2|',1)
            path.write_text(text,encoding='utf-8')
            with self.assertRaisesRegex(ValueError,'Selection status mismatch'):
                rp.replay_selection(root,corpus,rp.read(root / 'data/scenarios.json'))

    def test_changed_advice_is_detected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            shutil.copytree(rp.ROOT / 'data/prompts',root / 'data/prompts')
            shutil.copytree(rp.ROOT / 'results/api',root / 'results/api')
            p = root / 'results/api/responses/API-V3-S01-01.txt'
            p.write_text(p.read_text(encoding='utf-8')+' changed',encoding='utf-8')
            prompts={f'S{i:02d}':(root / f'data/prompts/S{i:02d}.txt').read_text(encoding='utf-8') for i in range(1,9)}
            with self.assertRaisesRegex(ValueError,'Advice hash mismatch'):
                rp.verify_results(root,'api',prompts)

    def test_secret_scanner_catches_environment_file(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            (root / '.env').write_text('not a real secret',encoding='utf-8')
            with self.assertRaisesRegex(ValueError,'Environment file'):
                package.scan(root)

    def test_packaged_files_have_no_credentials(self):
        self.assertGreater(package.scan(),500)

class GenerationTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.root=Path(self.temp.name)
        shutil.copytree(rp.ROOT / 'data',self.root / 'data')
        target=self.root / 'results/codex_chatgpt'
        target.mkdir(parents=True)
        shutil.copyfile(rp.ROOT / 'results/codex_chatgpt/protocol.json',target / 'protocol.json')
        self.root_patch=patch.object(generate,'ROOT',self.root)
        self.root_patch.start()

    def tearDown(self):
        self.root_patch.stop()
        self.temp.cleanup()

    def args(self,execute=False):
        return argparse.Namespace(channel='api', scenarios=['S01'], output=str(self.root / 'runs/new'), execute=execute, allow_paid_api=execute)

    def test_dry_run_never_uses_network_or_credentials(self):
        with patch.object(generate,'api_call',side_effect=AssertionError('network')), patch.object(generate.getpass,'getpass',side_effect=AssertionError('credentials')), contextlib.redirect_stdout(io.StringIO()):
            generate.run(self.args())
        requests=list((self.root / 'runs/new/requests').glob('*.json'))
        self.assertEqual(len(requests),5)
        self.assertTrue(all(rp.read(p)==rp.read(requests[0]) for p in requests))
        self.assertNotIn('previous_response_id',rp.read(requests[0]))
        with self.assertRaisesRegex(ValueError,'Output already exists'):
            generate.run(self.args())

    def test_mock_live_api_saves_all_five_independent_outputs(self):
        calls=[]
        def fake(payload,key):
            calls.append(payload)
            return json.dumps(dict(id='test-'+str(len(calls)),status='completed',model='gpt-6-astra',usage={'input_tokens':1,'output_tokens':1},output=[dict(type='message',content=[dict(type='output_text',text='Example '+str(len(calls)))])])), 'test-request'
        with patch.dict(generate.os.environ,{'OPENAI_API_KEY':'sk-'+'test-placeholder'}), patch.object(generate,'api_call',side_effect=fake), contextlib.redirect_stdout(io.StringIO()):
            generate.run(self.args(True))
        self.assertEqual(len(calls),5)
        self.assertTrue(all(p==calls[0] for p in calls))
        self.assertEqual(rp.read(self.root / 'runs/new/status.json')['completed'],5)
        self.assertEqual(len(list((self.root / 'runs/new/records').glob('*.json'))),5)

    def test_http_failure_stops_without_retry_and_redacts_key(self):
        key='sk-'+'test-placeholder'
        error=urllib.error.HTTPError('https://api.openai.com/v1/responses',429,'quota',{},io.BytesIO(('quota '+key).encode()))
        with patch.dict(generate.os.environ,{'OPENAI_API_KEY':key}), patch.object(generate,'api_call',side_effect=error) as call, contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(RuntimeError,'Generation stopped'):
                generate.run(self.args(True))
        self.assertEqual(call.call_count,1)
        status=rp.read(self.root / 'runs/new/status.json')
        self.assertEqual(status['completed'],0)
        self.assertNotIn(key,json.dumps(status))

    def test_live_api_requires_explicit_cost_opt_in(self):
        args=self.args(True); args.allow_paid_api=False
        with patch.object(generate,'api_call',side_effect=AssertionError('network')):
            with self.assertRaisesRegex(ValueError,'allow-paid-api'):
                generate.run(args)

    def test_codex_isolation_flags_are_explicit(self):
        args=generate.codex_args('codex','isolated','output.txt')
        for flag in ['--ephemeral','--ignore-user-config','--skip-git-repo-check','project_doc_max_bytes=0','web_search="disabled"']:
            self.assertIn(flag,args)

if __name__=='__main__':
    unittest.main()
