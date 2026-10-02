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
alias_reasons = {x['from']: x['reason_zh'] for x in decisions['aliases']}
excluded = {x['key']: x['reason_zh'] for x in decisions['excluded_keys']}

def root(key):
    seen = set()
    while key in aliases:
        assert key not in seen, 'Alias cycle'
        seen.add(key)
        key = aliases[key]
    return key

SCOPE_LABEL = {'core':'关系防骗与账户防护','dating_safety':'交友平台与会面安全','investment':'关系投资／加密骗局','sextortion':'私密影像与勒索','recovery':'受骗后止损与恢复','support':'亲友／支持者建议'}
STAGE_LABEL = {'prevention':'事前防护','suspicion':'出现可疑线索','recovery':'暴露或受骗后','support':'支持他人'}
SCOPE_GATE = {
 'core':'在线建立或维持关系时，按该建议明确提及的线索或请求适用。',
 'dating_safety':'涉及交友平台设置或安排线下会面；仅采用与当前活动匹配的步骤。',
 'investment':'仅在出现投资、交易平台、加密货币或钱包操作时适用。',
 'sextortion':'仅在私密影像、性勒索、影像传播风险或相关威胁出现时适用。',
 'recovery':'仅在已付款、已泄露信息、账号受侵或发现受骗后，按实际损害适用。',
 'support':'建议对象是正在帮助他人的亲友或支持人员，不直接冒充给潜在受骗者的建议。'
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
        result.append('仅涉及对方自称美国军人的情形；不以职业或国籍本身判定诈骗。')
    if key.startswith('hash_') or key in {'adult_hash_prevention','save_hash_case_pin'}:
        result.append('工具操作以 StopNCII 当时的资格和平台覆盖为限；相关影像须满足成人服务条件。')
    if key == 'image_age_service':
        result.append('成年人求助时如影像摄于未满 18 岁，转介未成年人影像服务；不要求重新获取影像。')
    if key in {'keep_payee_check','payee_mismatch_stop','card_channel_controls','temporary_card_freeze','personal_payment_limits'}:
        result.append('仅当用户的银行或支付渠道提供该功能时；姓名匹配或额度控制不保证交易安全。')
    if any(r['stage']=='recovery' for r in members):
        result.append('涉及追回款项时只表示可以请求处理，不承诺退款或追回成功。')
    if key in {'elder_reporting_assistance','official_report_address','fake_ic3_social','avoid_report_search_ads','mail_fraud_report'}:
        result.append('所述机构渠道属于美国；其他地区应使用相应本地渠道。')
    if key in {'scam_call_filter','anti_scam_helpline','no_identity_account_lending'}:
        result.append('所述 ScamShield 或 Singpass 服务属于新加坡。')
    result.append('国家、机构与工具名称须结合来源地区使用；此栏是研究用途适用性标注。')
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
      'applicability_zh':applicability(key,members),
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
          'reason_zh':'；'.join(changes) if changes else ('该语义组的代表候选。' if is_rep else '行动及适用条件与同组代表实质相同；保留独立出处。'),
          'canonical_wording_revised':key in overrides})
for r in candidate_rows:
    if r['key'] in excluded:
        log.append({'candidate_id':r['candidate_id'],'source_id':r['source_id'],'input_key':r['key'],
                    'advice_id':None,'final_key':None,'disposition':'excluded','reason_zh':excluded[r['key']]})
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
 {'source_id':'S015','item':'Geographic stereotyping in military impersonation warning','decision':'not_extracted','reason_zh':'不把来自某地区本身当作诈骗证据。'},
 {'source_id':'S015','item':'Requested customized photograph as an identity check','decision':'not_extracted','reason_zh':'未将定制照片当作可靠的身份保证；采用其他来源的有限证据表述。'},
 {'source_id':'S022','item':'Alcohol and sexual-health advice','decision':'not_extracted','reason_zh':'超出本项目恋爱诈骗及其直接风险范围。'},
 {'url':'https://bumble.com/the-buzz/bumble-protect-information','item':'Platform privacy marketing page','decision':'source_not_included','reason_zh':'读取部分主要是企业做法介绍，没有提取适用的个人行动建议。'},
 {'url':'https://www.barclays.co.uk/help/security-fraud/latest-scams/','item':'Bank page with incomplete retrieval','decision':'source_not_included','reason_zh':'未用不完整页面作为最终条目依据。'},
 {'source_id':'S034','item':'Deletion of original image after hashing','decision':'not_extracted','reason_zh':'避免在未处理报案证据需求时诱导删除原始材料。'},
 {'source_id':'S026','item':'loss_limit_plan','decision':'candidate_excluded','reason_zh':excluded['loss_limit_plan']}
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

readme=f'''# Online romance scam advice corpus

完成日期：{DATE}。本语料仅用于 AI 知识准备；实验中的人类建议仍由问卷参与者独立撰写。

| 项目 | 已完成结果 |
|---|---:|
| 有条目纳入的公开来源页面 | {len(source_rows)} |
| 来源网站域名 | {report['publisher_domains']} |
| 来源支持的候选提取 | {len(candidate_rows)} |
| 语义合并的候选 | {report['merged_candidates']} |
| 排除的候选 | {report['excluded_candidates']} |
| 最终建议单元 | **{len(clean)}** |

数量关系：{len(candidate_rows)} = {len(clean)} 条保留 + {report['merged_candidates']} 条合并 + {report['excluded_candidates']} 条排除。网页筛选中未提取的内容另记于 screening_notes.json，不混入候选数量。

## 查看与文件

双击 **corpus_browser.html** 即可离线搜索英文建议、筛选范围／阶段、展开适用条件并点击原始来源。

| 文件 | 内容 |
|---|---|
| advice_corpus.jsonl | 去重后主语料；每行一个 JSON 对象，含适用条件和全部出处 |
| candidate_extractions.jsonl | 合并前的规范化提取；不是网页原文 |
| sources.json | 来源机构、网址、地区、访问日期、检索状态及内部证据摘要值 |
| deduplication_log.jsonl | 每条候选 → 保留条目／合并／排除的去向 |
| semantic_decisions.json | 跨初始类别的合并依据及容易混淆但保留的区别 |
| pair_review_log.json | 42 组词项相似候选的语义复核决定及理由 |
| collection_report.json | 数量、范围、来源类型和方法信息 |
| screening_notes.json | 未纳入内容及排除理由 |

## 内容与范围

**建议正文是 AI 根据已读取公开来源进行的英文规范化转述，并非逐字摘录，也不标为原作者原话。** 原始网页链接和定位随条目保存。部分原文是风险警示，在提取时转化为可识别线索的建议；适用条件栏是研究用途标注。

| 范围 | 条目数（可交叉） | 使用条件 |
|---|---:|---|
'''+''.join(f"| {SCOPE_LABEL[s]} | {n} | {SCOPE_GATE[s]} |\n" for s,n in report['scope_counts_nonexclusive'].items())+f'''
其中 {report['retained_with_romance_specific_source']} 条至少有一个直接涉及恋爱／关系诈骗的来源，{report['retained_adjacent_only']} 条仅由相关诈骗机制、账户防护或恢复支持来源支持。其余涉及交友安全或多种来源背景。**不能把全部 {len(clean)} 条直接当成八个主情境都适用的建议。** 尤其投资、勒索和事后恢复内容，只在对应事实出现时调用；亲友支持内容要匹配建议接收者的角色。

“条”指行动或风险线索单元，不等于同样数量的独立大策略。一般原则与需要不同受理方或操作流程的条件性建议可能并存。例如，联系支付机构是一般原则，礼品卡发行方、银行转账和支付应用的止损步骤有各自条件。

## 收集与语义去重方法

| 步骤 | 实际做法 |
|---|---|
| 收集 | 目的性检索并阅读政府、警方、监管机构、受害者支持机构、大学、银行和平台公开页面；补充恋爱诈骗相关的投资、隐私和止损机制。不是系统综述或全部网站普查。 |
| 提取 | 将行动／风险线索写成短英文转述，保留机构、URL、读取日期及页面定位。不收集评论区个案或参与者个人资料。 |
| 初步归组 | 阅读上下文，按行动、对象、适用条件分配语义类别；同义说法跨来源合并。 |
| 二次语义检查 | 比较初始类别，明确合并 {len(aliases)} 个类别；换措辞、资料字段或示例不单独增加数量。另用词项相似候选列表辅助检查，不把词项分数当成语义准确率。 |
| 保留信息 | 合并不删除出处；候选表和去向日志可追溯到各来源。 |
| 复核性质 | 本轮由 AI 辅助判断完成；没有双人独立编码、专家效度检验或人工一致性系数，不声称已实现客观零重复。 |

来源地区包括美国、英国、澳大利亚、新西兰和新加坡等。机构、报告渠道和工具条件按来源地区使用；访问日期不代表文章发布日期。少数页面使用检索工具返回的实质正文，直接打开失败的情况已标记。完整页面的内部读取证据保留在项目 corpus_work/evidence 中，未打包复制网站全文。

这是一份可供 AI 检索／后续数据准备的知识语料，不是情景—标准回答训练对，也未调用 API 训练模型。正式研究中应如实披露规范化转述与 AI 辅助去重过程。
'''
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
