"""Build the source-grounded corpus and a self-contained reader. Python stdlib only.

This script REPLAYS the AI-reviewed semantic decisions; it does not perform
embedding clustering or pretend that concept keys are a semantic model.
"""
from pathlib import Path
from collections import Counter, defaultdict
from urllib.parse import urlparse
import json, re, hashlib, html, zipfile, shutil, math

WORK = Path(__file__).resolve().parent
OUT = WORK.parent / 'romance_scam_corpus'
OUT.mkdir(exist_ok=True)
DATE = '2026-09-18'

def read(p):
    return json.loads(p.read_text(encoding='utf-8'))

def write_json(name, value):
    (OUT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

def write_jsonl(name, rows):
    (OUT / name).write_text(''.join(json.dumps(r, ensure_ascii=False)+'\n' for r in rows), encoding='utf-8')

sources = [s for p in sorted((WORK/'extraction_batches').glob('*.json')) for s in read(p)]
decisions = read(WORK/'semantic_decisions.json')
overrides = read(WORK/'canonical_overrides.json')
final_review = read(WORK/'final_review_adjustments.json')
decisions['aliases'].extend(final_review['aliases'])
decisions['lexical_pair_review'] = {'pairs_reviewed':len(final_review['pairs']), 'additional_merges':len(final_review['aliases']), 'method':final_review['candidate_generation']}
overrides.update(final_review['overrides'])
aliases = {x['from']: x['to'] for x in decisions['aliases']}
alias_reasons = {x['from']: x['reason_en'] for x in decisions['aliases']}
excluded = {x['key']: x['reason_en'] for x in decisions['excluded_keys']}

def root(key):
    seen = set()
    while key in aliases:
        assert key not in seen, 'Alias cycle'
        seen.add(key)
        key = aliases[key]
    return key

SCOPE_LABEL = {'core':'Relationship-scam prevention and account protection','dating_safety':'Dating-platform and meeting safety','investment':'Relationship-based investment and cryptocurrency scams','sextortion':'Intimate images and blackmail','recovery':'Post-scam harm limitation and recovery','support':'Advice for friends, relatives and supporters'}
STAGE_LABEL = {'prevention':'Prevention','suspicion':'Suspicious cues','recovery':'After exposure or fraud','support':'Supporting others'}
SCOPE_GATE = {
 'core':'Applicable when establishing or maintaining an online relationship, according to the cues or requests explicitly mentioned in the advice.',
 'dating_safety':'Applicable to dating-platform settings or arranging an in-person meeting; use only steps matching the current activity.',
 'investment':'Applicable only when investment, trading-platform, cryptocurrency, or wallet activity is present.',
 'sextortion':'Applicable only when intimate images, sextortion, image-distribution risks, or related threats are present.',
 'recovery':'Applicable after payment, information disclosure, account compromise, or discovery of fraud, according to the actual harm.',
 'support':'The advice addresses friends, relatives, or support workers helping another person; it is not presented directly as advice to a potential victim.'
}
DIRECT = {'S001','S002','S003','S004','S005','S007','S008','S009','S010','S012','S013','S014','S015','S016','S017','S018','S020','S021','S026','S029','S031','S032','S040','S043','S044'}
DATING = {'S006','S019','S022'}
SEARCH_ONLY = {'S016','S021'}
candidate_rows = []
source_rows = []
for s in sources:
    evidence = WORK/'evidence'/s['evidence']
    assert evidence.exists(), s['id']
    rel = 'romance_specific' if s['id'] in DIRECT else ('dating_safety' if s['id'] in DATING else 'adjacent_scam_or_recovery_mechanism')
    source_rows.append({k:v for k,v in s.items() if k not in {'records','evidence'}} | {
      'accessed_on':DATE,'source_context':rel,
      'retrieval_status':'substantive_search_result_text; direct_open_unavailable' if s['id'] in SEARCH_ONLY else 'substantive_page_or_pdf_text',
      'internal_evidence_file':s['evidence'],'internal_evidence_sha256':hashlib.sha256(evidence.read_bytes()).hexdigest(),
      'candidate_count':len(s['records']),
      'original_language':'en','text_handling':'AI-normalized English paraphrase, not a verbatim quotation',
      'paraphrase_word_count':sum(len(r['text'].split()) for r in s['records'])})
    for r in s['records']:
        candidate_rows.append({'candidate_id':f'R{len(candidate_rows)+1:04d}', 'source_id':s['id'], 'source_url':s['url'],
            'source_context':rel,'accessed_on':DATE, 'text_status':'AI-normalized source-grounded paraphrase', **r})
keys = {r['key'] for r in candidate_rows}
assert set(aliases) <= keys
assert set(aliases.values()) <= keys
assert len({s['id'] for s in sources}) == len(sources)
assert len({s['url'] for s in sources}) == len(sources)
assert all(s['paraphrase_word_count'] <= 200 for s in source_rows)
source_by_id = {s['id']:s for s in source_rows}
groups = defaultdict(list)
for r in candidate_rows:
    if r['key'] not in excluded:
        groups[root(r['key'])].append(r)

def applicability(key, members):
    scopes = sorted({r['scope'] for r in members})
    result = [SCOPE_GATE[x] for x in scopes]
    if key.startswith('military_'):
        result.append('Applicable only when the contact claims to be a member of the US military; occupation or nationality alone is not evidence of fraud.')
    if key.startswith('hash_') or key in {'adult_hash_prevention','save_hash_case_pin'}:
        result.append('Use of StopNCII is subject to its eligibility requirements and platform coverage at the time; the images must meet adult-service conditions.')
    if key == 'image_age_service':
        result.append('If an adult seeks help for images taken before age 18, refer to the appropriate service for images of minors; do not require reacquiring the images.')
    if key in {'keep_payee_check','payee_mismatch_stop','card_channel_controls','temporary_card_freeze','personal_payment_limits'}:
        result.append('Applicable only if the user\'s bank or payment channel provides this feature; name matching and payment limits do not guarantee transaction safety.')
    if any(r['stage']=='recovery' for r in members):
        result.append('Advice about recovering funds means that assistance may be requested, not that a refund or recovery is guaranteed.')
    if key in {'elder_reporting_assistance','official_report_address','fake_ic3_social','avoid_report_search_ads','mail_fraud_report'}:
        result.append('The agency channels described are US-specific; use the corresponding local channels in other jurisdictions.')
    if key in {'scam_call_filter','anti_scam_helpline','no_identity_account_lending'}:
        result.append('The ScamShield or Singpass services mentioned are Singapore-specific.')
    result.append('Country, agency, and tool names must be interpreted in the source jurisdiction; this field is a research applicability annotation.')
    return result

clean = []
log = []
for key,members in groups.items():
    representative = next((r for r in members if r['key']==key), members[0])
    aid = f'ADV{len(clean)+1:04d}'
    sid = list(dict.fromkeys(r['source_id'] for r in members))
    item = {'advice_id':aid,'concept_key':key,'advice_en':overrides.get(key, representative['text']),
      'language':'en','text_status':'AI-normalized source-grounded paraphrase; not verbatim',
      'scopes':sorted({r['scope'] for r in members}), 'stages':sorted({r['stage'] for r in members}),
      'topics':sorted({r['topic'] for r in members}),
      'applicability_en':applicability(key,members),
      'source_contexts':sorted({r['source_context'] for r in members}),
      'source_ids':sid,'source_jurisdictions':sorted({source_by_id[x]['jurisdiction'] for x in sid}),
      'candidate_ids':[r['candidate_id'] for r in members], 'candidate_count':len(members),
      'provenance':[{'source_id':r['source_id'],'url':r['source_url'],'locator':r['locator'],
          'candidate_id':r['candidate_id'],'original_scope':r['scope'],'original_stage':r['stage']} for r in members],
      'semantic_review':'AI contextual comparison plus explicit cluster decisions; no independent human adjudication',
      'study_use':'AI corpus only; not a human-participant response','collected_on':DATE}
    clean.append(item)
    for r in members:
        changes = []
        k = r['key']
        while k in aliases:
            changes.append(alias_reasons[k]); k=aliases[k]
        is_rep = r['candidate_id']==representative['candidate_id']
        log.append({'candidate_id':r['candidate_id'],'source_id':r['source_id'],'input_key':r['key'],
          'advice_id':aid,'final_key':key,'disposition':'representative' if is_rep else 'merged',
          'reason_en':'; '.join(changes) if changes else ('Representative candidate for this semantic group.' if is_rep else 'The action and applicability conditions are materially the same as the group representative; independent provenance is retained.'),
          'canonical_wording_revised':key in overrides})
for r in candidate_rows:
    if r['key'] in excluded:
        log.append({'candidate_id':r['candidate_id'],'source_id':r['source_id'],'input_key':r['key'],
                    'advice_id':None,'final_key':None,'disposition':'excluded','reason_en':excluded[r['key']]})
log.sort(key=lambda x:x['candidate_id'])

# A lexical candidate list supports a second semantic inspection. Scores are NOT semantic distances.
stop = set('a an the to of in on for from and or with your you their that as by at it do not be is if when into after through someone person contact'.split())
tokens = [{w for w in re.findall(r'[a-z]+',r['advice_en'].lower()) if w not in stop} for r in clean]
df = Counter(t for row in tokens for t in row)
weights = [{t:math.log((1+len(clean))/(1+df[t]))+1 for t in row} for row in tokens]
norm = [math.sqrt(sum(v*v for v in row.values())) for row in weights]
pairs=[]
for i in range(len(clean)):
    for j in range(i+1,len(clean)):
        score=sum(weights[i][t]*weights[j][t] for t in tokens[i]&tokens[j])/(norm[i]*norm[j])
        if score >= .28:
            pairs.append({'key_a':clean[i]['concept_key'],'key_b':clean[j]['concept_key'],
                'score':round(score,4),'text_a':clean[i]['advice_en'],'text_b':clean[j]['advice_en']})
pairs.sort(key=lambda x:-x['score'])
(WORK/'similarity_review_candidates.json').write_text(json.dumps(pairs,ensure_ascii=False,indent=2),encoding='utf-8')

screening=[
 {'source_id':'S015','item':'Geographic stereotyping in military impersonation warning','decision':'not_extracted','reason_en':'A person\'s geographic origin is not treated as evidence of fraud.'},
 {'source_id':'S015','item':'Requested customized photograph as an identity check','decision':'not_extracted','reason_en':'Customized photographs are not treated as reliable identity guarantees; limited-evidence wording from other sources is used.'},
 {'source_id':'S022','item':'Alcohol and sexual-health advice','decision':'not_extracted','reason_en':'Outside the scope of romance scams and their direct risks in this project.'},
 {'url':'https://bumble.com/the-buzz/bumble-protect-information','item':'Platform privacy marketing page','decision':'source_not_included','reason_en':'The retrieved material mainly described company practices; no applicable individual action advice was extracted.'},
 {'url':'https://www.barclays.co.uk/help/security-fraud/latest-scams/','item':'Bank page with incomplete retrieval','decision':'source_not_included','reason_en':'An incompletely retrieved page was not used as the basis for final entries.'},
 {'source_id':'S034','item':'Deletion of original image after hashing','decision':'not_extracted','reason_en':'Avoid encouraging deletion of original material before addressing evidence needs for reporting.'},
 {'source_id':'S026','item':'loss_limit_plan','decision':'candidate_excluded','reason_en':excluded['loss_limit_plan']}
]
normalized=[re.sub(r'\W+',' ',r['text'].lower()).strip() for r in candidate_rows]
report={
 'completed_on':DATE,'status':'collection_and_AI_semantic_deduplication_complete',
 'source_pages':len(source_rows),'publisher_domains':len({urlparse(s['url']).netloc.removeprefix('www.') for s in source_rows}),
 'candidate_extractions':len(candidate_rows),'exact_duplicate_texts':len(normalized)-len(set(normalized)),
 'initial_semantic_keys':len(keys),'cross_key_merge_decisions':len(aliases),
 'excluded_candidates':sum(x['disposition']=='excluded' for x in log),
 'merged_candidates':sum(x['disposition']=='merged' for x in log), 'retained_units':len(clean),
 'scope_counts_nonexclusive':dict(Counter(s for r in clean for s in r['scopes'])),
 'stage_counts_nonexclusive':dict(Counter(s for r in clean for s in r['stages'])),
 'source_type_counts':dict(Counter(s['type'] for s in source_rows)),
 'source_context_counts':dict(Counter(s['source_context'] for s in source_rows)),
 'retained_with_romance_specific_source':sum('romance_specific' in r['source_contexts'] for r in clean),
 'retained_adjacent_only':sum(r['source_contexts']==['adjacent_scam_or_recovery_mechanism'] for r in clean),
 'semantic_method':'AI-assisted contextual reading; same action, object and materially relevant condition; cross-key aliases explicitly adjudicated. Script replays decisions.',
 'embedding_model':None,'independent_human_coders':0,
 'not_claimed':['systematic literature review','300 independent macro-strategies','expert-validated effectiveness','verbatim human-authored advice','model training completed'],
 'source_locator_note':'L numbers refer to the retrieved text snapshot; PDF page/section locators refer to the captured document. Website layouts may change.',
 'full_source_pages_distributed':False
}
assert len(clean)+report['merged_candidates']+report['excluded_candidates']==len(candidate_rows)
assert len({r['advice_en'].lower() for r in clean})==len(clean)
assert len({r['candidate_id'] for r in log})==len(candidate_rows)
assert all(len(r['advice_en'])>20 and r['provenance'] for r in clean)
assert all(urlparse(p['url']).scheme=='https' for r in clean for p in r['provenance'])

write_jsonl('advice_corpus.jsonl',clean)
write_jsonl('candidate_extractions.jsonl',candidate_rows)
write_jsonl('deduplication_log.jsonl',log)
write_json('sources.json',source_rows)
write_json('semantic_decisions.json',decisions)
write_json('pair_review_log.json',final_review)
write_json('screening_notes.json',screening)
write_json('collection_report.json',report)

readme=f"""# Online romance scam advice corpus

Completed: {DATE}. This corpus supports AI knowledge preparation only. Human participants write their own advice independently.

| Measure | Count |
|---|---:|
| Public source pages | {len(source_rows)} |
| Publisher domains | {report['publisher_domains']} |
| Candidate paraphrases | {len(candidate_rows)} |
| Retained advice units | {len(clean)} |
| Merged candidates | {report['merged_candidates']} |
| Excluded candidates | {report['excluded_candidates']} |

The advice consists of AI-normalized English paraphrases grounded in public sources, not verbatim quotations. Each record retains provenance, applicability conditions and source locators. Collection was purposive, not a systematic review. Semantic decisions were AI-assisted, without independent double coding or expert validation. The script replays those recorded decisions; lexical scores are not semantic accuracy measures.

Use advice only when its conditions are met. Investment, intimate-image abuse and post-loss recovery advice are conditional; supporter advice requires the appropriate recipient role. Agencies and tools depend on jurisdiction. Source access dates are not publication dates. Full source pages are not distributed.

The advice_corpus.jsonl file contains retained units; candidate_extractions.jsonl and deduplication_log.jsonl trace candidates to retained, merged or excluded decisions. sources.json records provenance, semantic_decisions.json and pair_review_log.json explain review decisions, and collection_report.json and screening_notes.json describe scope and exclusions. The historical browser export is optional. The corpus is neither scenario-answer training pairs nor evidence of completed fine-tuning.
"""
(OUT/'README.md').write_text(readme,encoding='utf-8')

payload=json.dumps({'advice':clean,'sources':source_rows,'report':report,'scopeLabels':SCOPE_LABEL,'stageLabels':STAGE_LABEL},ensure_ascii=False).replace('<','\\u003c')
template=(WORK/'browser_template.html').read_text(encoding='utf-8')
(OUT/'corpus_browser.html').write_text(template.replace('__CORPUS_DATA__',payload),encoding='utf-8')

# Distribution contains extracted data and reviewed decisions, not full source pages.
manifest={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(OUT.iterdir()) if p.is_file() and p.name!='checksums.json'}
write_json('checksums.json',manifest)
archive=WORK.parent/'Romance scam advice corpus.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
    for p in sorted(OUT.iterdir()):
        if p.is_file(): z.write(p,arcname='romance_scam_corpus/'+p.name)
print(json.dumps(report,ensure_ascii=False,indent=2))
print('Lexical review pairs:',len(pairs))
print('Output:',OUT)
