$ErrorActionPreference='Stop'
$root=(Get-Location).Path
$utf=[Text.UTF8Encoding]::new($false)
$v2=Join-Path $root 'alex_reference_materials/review_v2'
. ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $root 'alex_direct_generation/docx_helpers.ps1'),[Text.Encoding]::UTF8)))
function Write-Json($name,$value){[IO.File]::WriteAllText((Join-Path $v2 $name),(ConvertTo-Json -InputObject $value -Depth 40),$utf)}
function Write-Lines($name,$value){[IO.File]::WriteAllLines((Join-Path $v2 $name),[string[]]@($value|ForEach-Object{ConvertTo-Json -InputObject $_ -Depth 40 -Compress}),$utf)}
$corpus=Lines 'romance_scam_corpus/advice_corpus.jsonl'
$sources=Load 'romance_scam_corpus/sources.json'
$oldProtocol=Load 'alex_direct_generation/protocol.json'
$scenarios=@($oldProtocol.scenarios)
$decisions=@(Import-Csv -LiteralPath (Join-Path $v2 'decisions.tsv') -Delimiter '|' -Encoding UTF8)
$reserve=@{}; Import-Csv -LiteralPath (Join-Path $v2 'prompt_reserve_notes.tsv') -Delimiter '|' -Encoding UTF8|ForEach-Object{$reserve[$_.id]=$_.prompt_reason}
$oldIds=@((Lines 'alex_reference_materials/alex_applicable_corpus.jsonl').advice_id)
$byId=@{};foreach($d in $decisions){if($byId.ContainsKey($d.id)){throw 'Duplicate screening ID'};$byId[$d.id]=$d}
if($corpus.Count-ne 288 -or $decisions.Count-ne 288 -or $scenarios.Count-ne 8){throw 'Input count mismatch'}
$snapshot=Join-Path $v2 'before_revision'
[void][IO.Directory]::CreateDirectory($snapshot)
$protected=@('romance_scam_corpus','alex_direct_generation','Scenarios for AI models_3.docx','Word versions/01 - Advice Corpus - 288 Entries.docx','Word versions/03 - Alex GPT-6 Advice - 40 Responses.docx','Word versions/04 - Alex Advice - Human Review.docx','Word versions/05 - Alex GPT-6 Generation - Methods and Checks.docx','Word versions/06 - Survey 2 - Concise Questionnaire.docx')
$hashes=@(foreach($p in $protected){Get-ChildItem -LiteralPath (Join-Path $root $p) -File -Recurse|ForEach-Object{@{path=$_.FullName.Substring($root.Length+1);sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}}})
if(!(Test-Path -LiteralPath (Join-Path $v2 'protected_before.json'))){Write-Json 'protected_before.json' $hashes}
foreach($p in @('Analysis plan.docx','Word versions/00 - Document Guide.docx','README.md','alex_reference_materials/README.md')){
 $dest=Join-Path $snapshot $p;[void][IO.Directory]::CreateDirectory((Split-Path $dest -Parent));if(!(Test-Path -LiteralPath $dest)){Copy-Item -LiteralPath (Join-Path $root $p) -Destination $dest}
}
function Get-Class($d,$s){switch($d.rule){'D'{'D'};'C'{'C'};'N'{'N'};'MONEY'{if($s.financial_cue-eq'present'){'D'}else{'C'}};'EMOTION'{if($s.emotional_intensity-eq'high'){'D'}else{'C'}};default{throw 'Unknown screening rule'}}}
$rows=[Collections.Generic.List[object]]::new();$matrix=[Collections.Generic.List[object]]::new()
foreach($entry in $corpus){
 $d=$byId[$entry.advice_id];if(!$d){throw ('Missing decision '+$entry.advice_id)}
 $classes=[ordered]@{};foreach($s in $scenarios){$class=Get-Class $d $s;$classes[$s.id]=$class;$matrix.Add([ordered]@{advice_id=$entry.advice_id;scenario_id=$s.id;classification=$class;reason=$d.reason;use_guard=$d.guard;in_prompt_pack=($d.prompt-eq'use')})}
 $eligible=$d.rule-ne'N';$selected=$d.prompt-eq'use'
 if($eligible -and (!$d.guard -or $d.guard-eq'-')){throw 'Missing eligible-use guard'}
 if(!$eligible -and $d.prompt-ne'out'){throw 'Ineligible prompt choice'}
 if($eligible -and !$selected -and !$reserve.ContainsKey($entry.advice_id)){throw 'Missing reserve-selection reason'}
 $selectionReason=if($selected){'Selected for '+$d.domain+' coverage: '+$d.reason}else{if($eligible){$reserve[$entry.advice_id]}else{'Outside the present Alex scope; this is an eligibility decision, not a prompt-length omission.'}}
 $copy=[ordered]@{};foreach($prop in $entry.PSObject.Properties){$copy[$prop.Name]=$prop.Value}
 $copy['screening']=[ordered]@{version='2.0';review_date='2026-09-24';reviewer='AI-assisted screening; researcher validation pending';eligible=$eligible;ever_direct=(@($classes.Values)-contains'D');scenario_classification=$classes;rule=$d.rule;domain=$d.domain;eligibility_reason=$d.reason;use_guard=$d.guard;role= $(if($d.domain-eq'delivery'){'Adviser communication principle; explicit role adaptation required'}else{'Recipient-facing action or risk information'});prompt_decision=$d.prompt;in_prompt_pack=$selected;prompt_selection_reason=$selectionReason;in_original_22=($oldIds-contains$entry.advice_id)}
 $rows.Add([pscustomobject]$copy)
}
$pool=@($rows|Where-Object{$_.screening.eligible});$pack=@($rows|Where-Object{$_.screening.in_prompt_pack});$excluded=@($rows|Where-Object{!$_.screening.eligible})
if($pool.Count-ne120 -or $pack.Count-ne53 -or $excluded.Count-ne168 -or $matrix.Count-ne2304){throw 'Revised count mismatch'}
Write-Lines 'advice_screening_288.jsonl' $rows
Write-Lines 'scenario_applicability_2304.jsonl' $matrix
Write-Lines 'applicable_pool_120.jsonl' $pool
Write-Lines 'prompt_pack_53.jsonl' $pack
$maps=@(foreach($s in $scenarios){$m=@($matrix|Where-Object{$_.scenario_id-eq$s.id});[ordered]@{scenario_id=$s.id;urgency=$s.urgency;financial_cue=$s.financial_cue;emotional_intensity=$s.emotional_intensity;scenario_text=$s.text;question=$s.question;eligible_count=120;direct_ids=@(($m|Where-Object{$_.classification-eq'D'}).advice_id);conditional_ids=@(($m|Where-Object{$_.classification-eq'C'}).advice_id);inapplicable_count=168;prompt_reference_count=53;prompt_reference_ids=@($pack.advice_id)}})
Write-Json 'scenario_reference_map.json' $maps
$summary=[ordered]@{version='2.0';date='2026-09-24';corpus_count=288;eligible_count=120;direct_in_at_least_one_scenario=@($pool|Where-Object{$_.screening.ever_direct}).Count;conditional_only=@($pool|Where-Object{!$_.screening.ever_direct}).Count;inapplicable_count=168;prompt_pack_count=53;eligible_reserve_count=67;old_22_retained=@($pool|Where-Object{$_.screening.in_original_22}).Count;newly_eligible_count=98;new_prompt_entries=31;scenario_decisions=2304;delivery_principles_eligible=11;delivery_principles_selected=3;exclusion_domains=@($excluded|Group-Object{$_.screening.domain}|ForEach-Object{@{domain=$_.Name;count=$_.Count}});selected_domains=@($pack|Group-Object{$_.screening.domain}|ForEach-Object{@{domain=$_.Name;count=$_.Count}});independent_human_validation=$false;new_generation_performed=$false;fresh_source_reverification=$false}
Write-Json 'summary.json' $summary
$instructions=[IO.File]::ReadAllText((Join-Path $root 'alex_direct_generation/generation_instructions.txt'),[Text.Encoding]::UTF8).Trim()
$instructions+="`n`nRevised reference protocol (v2): Every scenario receives the same reference pack. Reference availability does not establish that a described event occurred. Follow each applicability guard. Items marked ADVISER DELIVERY PRINCIPLE inform your tone only; do not tell the recipient to act as a supporter of another victim. Alex's expressed attachment does not establish the recipient's feelings. Do not turn hypothetical warning signs into facts. Choose only the few actions most relevant to the actual scenario; the pack is not a checklist. Do not add a reporting directory or post-loss instructions to this ambiguous pre-loss situation."
[IO.File]::WriteAllText((Join-Path $v2 'generation_instructions.txt'),$instructions,$utf)
$referenceText=(@(foreach($e in $pack){$role=if($e.screening.domain-eq'delivery'){'ADVISER DELIVERY PRINCIPLE'}else{'RECIPIENT ADVICE REFERENCE'};"[$($e.advice_id)] $role`n$($e.advice_en)`nApplicability guard: $($e.screening.use_guard)"}) -join "`n`n")
[void][IO.Directory]::CreateDirectory((Join-Path $v2 'prompts'))
$promptHashes=@(foreach($s in $scenarios){$text="SCENARIO`n$($s.text)`n`nQUESTION`n$($s.question)`n`nCONDITION METADATA`nurgency=$($s.urgency); financial_cue=$($s.financial_cue); emotional_intensity=$($s.emotional_intensity)`n`nREFERENCE MATERIALS (53 entries; common to all eight scenarios)`n$referenceText";$path=Join-Path $v2 ('prompts/'+$s.id+'.txt');[IO.File]::WriteAllText($path,$text,$utf);@{scenario_id=$s.id;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash;word_count=([regex]::Matches($text,'\S+')).Count}})
Write-Json 'protocol.json' ([ordered]@{version='2.0';status='Prepared references and prompts; not generated; researcher screening approval pending';model_plan='Retain selected GPT-6 workflow; exact future interface, model identifier and available settings must be recorded before a new batch';generation_plan='Five independent first responses per scenario; 40 responses; 120-180 English words; two or three paragraphs';fine_tuning=$false;reference_method='Fixed common 53-entry context pack, drawn from 120 eligible entries after full 288-entry screening';selection_basis='Judgment-based domain coverage and case proximity, not an empirically optimized number or a random sample';no_new_deduplication=$true;human_writers='Independent survey respondents; no reference corpus supplied; disclose this information-access difference';legacy_batch='Existing 40 responses used v1: 19-22 references per scenario; they cannot be relabeled as v2 outputs';reference_pack_sha256=(Get-FileHash -LiteralPath (Join-Path $v2 'prompt_pack_53.jsonl') -Algorithm SHA256).Hash;teacher_sha256=(Get-FileHash -LiteralPath (Join-Path $root 'Scenarios for AI models_3.docx') -Algorithm SHA256).Hash;corpus_sha256=(Get-FileHash -LiteralPath (Join-Path $root 'romance_scam_corpus/advice_corpus.jsonl') -Algorithm SHA256).Hash;prompts=$promptHashes})
function Add-EnglishSources($catalog){Add-Break;Add-P 'Source directory' 'Heading1';Add-P 'Source metadata and locators are retained from the original collection. This screening does not constitute a new verification of every web page. Entries are source-grounded paraphrases, not verbatim quotations.';foreach($s in $catalog){Add-P ($s.id+' | '+$s.org+' | '+$s.title) 'SourceHeading' $true;Add-Link $s.url $s.url 'Small';Add-P ('Jurisdiction: '+$s.jurisdiction+' | Accessed: '+$s.accessed_on) 'Small'}}
function Class-Label($entry){switch($entry.screening.rule){'D'{'D in S01-S08'};'C'{'C in S01-S08'};'MONEY'{'D: S03, S04, S07, S08; C: S01, S02, S05, S06'};'EMOTION'{'D: S02, S04, S06, S08; C: S01, S03, S05, S07'};'N'{'N in S01-S08'}}}
New-Doc '02 - Alex Reference Selection - Revised.docx'
Add-P 'Alex Reference Selection' 'Title'
Add-P 'Revised screening and proposed common prompt pack | 24 September 2026 | Version 2.0' 'Subtitle'
Add-P 'Decision in brief' 'Heading1'
Add-P 'The complete 288-entry corpus is retained. The revised screen identifies 120 potentially usable entries: 32 are directly relevant in at least one Alex version, and 88 are conditional in every version. The other 168 fall outside the present scenario scope. Of the 120 eligible entries, 53 form a proposed common prompt pack and 67 remain available in reserve.'
Add-P 'These are AI-assisted screening judgments for researcher review. Neither 120 nor 53 is an empirically established optimum. No new advice has been generated, and no model parameters have been trained or fine-tuned.'
Add-P 'Why the original 22 needed revision' 'Heading1'
Add-P 'The earlier whitelist mixed eligibility with prompt selection. It permitted some preventive boundaries without a stated request but excluded other comparable preventive material; it also excluded supporter-oriented material without separately testing whether its communication principles could be adapted. Therefore, 22 should be described as the reference subset used in the first batch, not the exhaustive set of relevant entries.'
Add-P 'All 22 original entries remain eligible and selected. This review adds 98 eligible entries, of which 31 enter the working prompt pack. No entry is deleted from the source corpus, and this is not a second semantic deduplication.'
Add-P 'Screening rules' 'Heading1'
Add-P 'D - Direct: the stated relationship or current cue supports the action now, including standing privacy boundaries that do not require a prior request.'
Add-P 'C - Conditional: a clear availability condition, plausible preventive trigger, or explicit adviser-role adaptation is needed. The advice must not assert that the trigger occurred. Eligibility does not mean this detail belongs in every short response.'
Add-P 'N - Outside scope: the item requires a different event stage, specific unprovided story, third-party intervention, population, or jurisdiction. Examples include payment recovery, investment operations, blackmail response, and military-identity narratives. These remain in the broader corpus for other scenarios.'
Add-P 'Boundary cases are recorded individually in document 07. A broad source category is not itself an exclusion rule. General precautions are separated from detailed new incidents; preserved messages or a conditional report do not require a prior financial loss.'
Add-P 'Scenario coverage and experimental control' 'Heading1'
$tableRows=@(foreach($m in $maps){@{cells=@($m.scenario_id,($m.urgency+' / '+$m.financial_cue+' / '+$m.emotional_intensity),[string]$m.direct_ids.Count,[string]$m.conditional_ids.Count,'168','53')}})
Add-Table @('Scenario','Urgency / money / emotion','D','C','N','Prompt entries') $tableRows @(1000,3500,1100,1100,1100,1560)
Add-P 'The same ordered 53-entry reference block is supplied to all eight versions. Only the teacher-provided scenario and its condition metadata change. This avoids mechanically varying reference availability with the manipulated factors; it does not guarantee equal output quality or content.'
Add-P 'High urgency concerns staying online tonight, not an immediate payment deadline. High emotional intensity describes what Alex says, not what the recipient feels. No version establishes fraud, a payment already made, blackmail, or account compromise.'
Add-P 'Selecting 53 from 120' 'Heading1'
Add-P 'The working pack covers money boundaries, relationship pace and pressure, verification and its limits, privacy, platform use, digital links, future meeting safety, trusted support, conditional escalation, and adviser delivery. Selection prioritizes proximity to the present decision and complementary coverage. The remaining 67 entries have separate prompt-omission reasons; they are not labeled inapplicable merely because they are omitted.'
Add-P 'Two retained reserve entries are represented by related working-pack entries (ADV0121 by ADV0021; ADV0125 by ADV0003). They remain distinct corpus records; this is not a claim that their meanings are identical. Of 11 conditionally adaptable delivery principles, three enter the pack and are explicitly marked as adviser-tone guidance.'
Add-P 'Status of existing materials' 'Heading1'
Add-P 'Documents 03, 04 and 05 describe or contain the existing 40-response batch, generated using the original 19-22 references per scenario. Their outputs and review annotations are preserved. Reviewing that batch remains useful for wording and scenario checks, but it does not validate this revised reference pack or any future outputs.'
Add-P 'Before final generation, researchers should adjudicate the screening boundaries and proposed pack, especially conditional items and adviser-role adaptations, and record any changes. The prepared S01-S08 prompts have not been executed. Human survey writers remain a separate sample writing their own advice without this corpus; the comparison must disclose that information-access difference.'
Add-P 'Selected reference entries' 'Heading1'
Add-P 'Original English paraphrases are preserved below. Guards and screening rationales are researcher annotations, not source quotations. D/C status describes eligibility; the same entries are available to every scenario.'
foreach($e in $pack){Add-P ($e.advice_id+' | '+$e.screening.domain+' | '+(Class-Label $e)) 'Heading2';Add-P $e.advice_en;Add-P ('Use guard: '+$e.screening.use_guard) 'Small';Add-P ('Selection: '+$e.screening.eligibility_reason) 'Small';if($e.screening.domain-eq'delivery'){Add-P $e.screening.role 'Small'};Add-P ('Sources: '+($e.source_ids-join', ')+' | Locators: '+(($e.provenance|ForEach-Object{$_.source_id+': '+$_.locator})-join'; ')) 'Small'}
$selectedSourceIds=@($pack.source_ids|Sort-Object -Unique);Add-EnglishSources @($sources|Where-Object{$selectedSourceIds-contains$_.id})
$doc2text=Finish-Doc
New-Doc '07 - Alex Corpus Screening - 288 Decisions.docx' $true
Add-P 'Alex Corpus Screening: 288 Decisions' 'Title'
Add-P 'Item-level audit | 24 September 2026 | Version 2.0 | Researcher validation pending' 'Subtitle'
Add-P 'All 288 original paraphrases and source links are retained. This audit distinguishes eligibility from selection into a short working reference pack. It records 2,304 scenario-entry decisions: D = direct; C = conditional; N = outside scope. D in at least one scenario: 32 entries; conditional only: 88; N throughout: 168. Prompt pack: 53; eligible reserve: 67.'
Add-P 'S01-S08 follow the teacher-original 2 x 2 x 2 order. Money is present in S03/S04/S07/S08; high expressed emotion in S02/S04/S06/S08; high urgency in S05-S08. All scenarios share the same proposed 53-entry reference pack. Adviser-delivery items require explicit role adaptation. Read document 02 for the screening boundary and implementation plan.'
Add-P 'This is an AI-assisted review, not independent human validation, a new source fact-check, or a new semantic deduplication. A reserve decision does not mean the original advice is invalid. The original 40-response batch is unchanged and did not use this revised pack.'
$auditRows=@(foreach($e in $rows){$status=if($e.screening.in_prompt_pack){'SELECTED'}elseif($e.screening.eligible){'ELIGIBLE RESERVE'}else{'OUTSIDE SCOPE'};@{cells=@(@($e.advice_id,('Sources: '+($e.source_ids-join', '))),$e.advice_en,@((Class-Label $e),$e.screening.eligibility_reason),@($status,$e.screening.prompt_selection_reason,$(if($e.screening.eligible){'Guard: '+$e.screening.use_guard}else{'Not supplied to the Alex model prompts.'})))}})
Add-Table @('ID / sources','Original corpus advice','Eligibility and reason','Prompt decision and use guard') $auditRows @(1100,3500,3950,4410)
Add-EnglishSources $sources
$doc7text=Finish-Doc
foreach($e in $rows){if(!$doc7text.Contains($e.advice_en)){throw ('Audit text missing '+$e.advice_id)}}
foreach($e in $pack){if(!$doc2text.Contains($e.advice_en)){throw ('Selected text missing '+$e.advice_id)}}
Write-Json 'document_checks.json' @($script:checks)
Write-Json 'build_checks.json' @{all_288_original_advice_texts_in_audit=$true;all_53_selected_texts_in_reference_doc=$true;scenario_entry_decisions=$matrix.Count;all_eligible_reserves_have_separate_reasons=$true;new_generation_performed=$false;visual_render_verified=$false;visual_render_limitation='LibreOffice is unavailable; OOXML structure, text coverage and table geometry checked.'}
$summary|ConvertTo-Json -Depth 8
