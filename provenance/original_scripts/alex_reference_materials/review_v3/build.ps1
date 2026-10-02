$ErrorActionPreference='Stop'
$root=(Get-Location).Path;$dir=Join-Path $root 'alex_reference_materials/review_v3';$utf=[Text.UTF8Encoding]::new($false)
function Save($name,$value){[IO.File]::WriteAllText((Join-Path $dir $name),(ConvertTo-Json -InputObject $value -Depth 35),$utf)}
function JsonLines($path){@(Get-Content -LiteralPath $path -Encoding UTF8|Where-Object{$_}|ForEach-Object{$_|ConvertFrom-Json})}
function SaveLines($name,$values){[IO.File]::WriteAllLines((Join-Path $dir $name),[string[]]@($values|ForEach-Object{ConvertTo-Json -InputObject $_ -Depth 35 -Compress}),$utf)}
$old=JsonLines 'alex_reference_materials/review_v2/advice_screening_288.jsonl'
$decisions=@(Import-Csv -LiteralPath (Join-Path $dir 'functional_review.tsv') -Delimiter '|' -Encoding UTF8)
$eligibleIds=@($old|Where-Object{$_.screening.eligible}|ForEach-Object{$_.advice_id})
if($decisions.Count-ne120-or@($decisions.id|Sort-Object -Unique).Count-ne120-or@(Compare-Object @($eligibleIds|Sort-Object) @($decisions.id|Sort-Object)).Count){throw 'Functional matrix must cover all 120 eligible IDs exactly once'}
$index=@{};foreach($d in $decisions){$index[$d.id]=$d;if(!$d.function-or!$d.comparative_reason-or$d.decision-notin@('S1','S2','S3','R1','R2','R3','R4')){throw 'Invalid functional decision'}}
$all=@(foreach($entry in $old){
 $previous=$entry.screening|ConvertTo-Json -Depth 15|ConvertFrom-Json
 $entry|Add-Member NoteProperty previous_screening_v2 $previous -Force
 $s=$entry.screening;$s.version='3.0';$s.review_date='2026-09-30';$s.reviewer='AI-assisted functional review; independent researcher adjudication pending'
 if($s.eligible){$d=$index[$entry.advice_id];$selected=$d.decision.StartsWith('S');$s.in_prompt_pack=$selected;$s.prompt_decision=if($selected){'use'}else{'reserve'};$s.prompt_selection_reason=$d.comparative_reason
  $s|Add-Member NoteProperty function $d.function -Force;$s|Add-Member NoteProperty decision_rule $d.decision -Force
  $s|Add-Member NoteProperty comparison_ids @($d.related_ids-split',') -Force
  $s|Add-Member NoteProperty eligibility_review_status 'Carried forward from v2; this revision re-evaluates prompt selection, not the full 288-entry eligibility boundary' -Force
 }else{$s.in_prompt_pack=$false;$s.prompt_decision='out';$s.prompt_selection_reason='Original v2 eligibility exclusion retained; not re-adjudicated by this selection-only revision.'}
 $entry
})
$pool=@($all|Where-Object{$_.screening.eligible});$pack=@($pool|Where-Object{$_.screening.in_prompt_pack});$reserve=@($pool|Where-Object{!$_.screening.in_prompt_pack});$count=$pack.Count
foreach($d in $decisions){foreach($id in ($d.related_ids-split',')){if(!$index.ContainsKey($id)){throw ('Unknown comparison ID '+$id)}};if($d.decision-eq'R1'-and!@(($d.related_ids-split',')|Where-Object{$_-in$pack.advice_id}).Count){throw 'Implementation reserve lacks selected comparator'}}
$pairs=@(@('ADV0005','ADV0240'),@('ADV0153','ADV0241'),@('ADV0137','ADV0182'),@('ADV0137','ADV0257'),@('ADV0021','ADV0121'),@('ADV0154','ADV0158'),@('ADV0070','ADV0269'))
foreach($pair in $pairs){if(@($pair|Where-Object{$_-notin$pack.advice_id}).Count){throw 'Required complementary pair incomplete'}}
if(@($pack|Where-Object{$_.screening.domain-eq'delivery'}).Count){throw 'Role rule violated'}
$added=@($pack|Where-Object{!$_.previous_screening_v2.in_prompt_pack}|ForEach-Object{$_.advice_id});$removed=@($reserve|Where-Object{$_.previous_screening_v2.in_prompt_pack}|ForEach-Object{$_.advice_id})
$packName='prompt_pack_'+$count+'.jsonl'
SaveLines 'advice_screening_288.jsonl' $all;SaveLines 'applicable_pool_120.jsonl' $pool;SaveLines $packName $pack
SaveLines 'eligible_reserve.jsonl' $reserve
$matrix=@(foreach($e in $all){foreach($p in $e.screening.scenario_classification.PSObject.Properties){[ordered]@{advice_id=$e.advice_id;scenario_id=$p.Name;classification=$p.Value;eligibility_reason=$e.screening.eligibility_reason;use_guard=$e.screening.use_guard;in_prompt_pack=$e.screening.in_prompt_pack;selection_reason=$e.screening.prompt_selection_reason}}})
SaveLines 'scenario_applicability_2304.jsonl' $matrix
$rawMaps=Get-Content 'alex_reference_materials/review_v2/scenario_reference_map.json' -Raw -Encoding UTF8|ConvertFrom-Json
$maps=if($rawMaps.PSObject.Properties.Name-contains'value'){@($rawMaps.value)}else{@($rawMaps)}
foreach($m in $maps){$m.prompt_reference_count=$count;$m.prompt_reference_ids=@($pack.advice_id)}
Save 'scenario_reference_map.json' $maps
$instructions=[IO.File]::ReadAllText((Join-Path $root 'alex_reference_materials/review_v2/generation_instructions.txt'),$utf)
$instructions=$instructions.Replace('Revised reference protocol (v2):','Revised reference protocol (v3):').Replace('Items marked ADVISER DELIVERY PRINCIPLE inform your tone only; do not tell the recipient to act as a supporter of another victim. ','')
[IO.File]::WriteAllText((Join-Path $dir 'generation_instructions.txt'),$instructions,$utf)
$refBlock=@(foreach($e in $pack){'['+$e.advice_id+"] RECIPIENT ADVICE REFERENCE`n"+$e.advice_en+"`nApplicability guard: "+$e.screening.use_guard})-join"`n`n"
[IO.Directory]::CreateDirectory((Join-Path $dir 'prompts'))|Out-Null
$promptHashes=@(foreach($m in $maps){$text="SCENARIO`n"+$m.scenario_text+"`n`nQUESTION`n"+$m.question+"`n`nCONDITION METADATA`nurgency="+$m.urgency+'; financial_cue='+$m.financial_cue+'; emotional_intensity='+$m.emotional_intensity+"`n`nREFERENCE MATERIALS ($count entries; common to all eight scenarios)`n"+$refBlock;$path=Join-Path $dir ('prompts/'+$m.scenario_id+'.txt');[IO.File]::WriteAllText($path,$text,$utf);[ordered]@{scenario_id=$m.scenario_id;sha256=(Get-FileHash -LiteralPath $path).Hash;word_count=[regex]::Matches($text,'\S+').Count}})
$rules=[ordered]@{
 S1='Selected: directly supports a decision arising from the stated relationship or manipulated cue.'
 S2='Selected: adds a distinct recipient action, exposure boundary or operational function tied to that decision, ongoing messaging, identity checking or the contemplated first meeting.'
 S3='Selected: supplies an enabling precaution, interpretation limit or response to a proposed check/action; check and caveat share the same availability condition.'
 R1='Reserve: a narrower implementation or alternative wording of selected actions. Record the comparator and residual distinction; this is not semantic duplicate deletion.'
 R2='Reserve: a distinct background configuration, broad educational, service-selection or general in-person task outside the defined relationship/checking/meeting decision functions. Not claimed fully covered.'
 R3='Reserve: requires an additional transaction role, event, person, baseline, population or downstream administrative task not stated or needed for a selected action. Not claimed fully covered.'
 R4='Reserve: supporter/adviser delivery principle. All eleven follow the same role rule; supportive tone remains a generation instruction.'
}
$summary=[ordered]@{version='3.0';date='2026-09-30';corpus_count=288;eligible_count=120;outside_scope=168;selected_count=$count;reserve_count=$reserve.Count;added_ids=$added;removed_ids=$removed;decision_counts=@($decisions|Group-Object decision|ForEach-Object{@{rule=$_.Name;count=$_.Count}});selection_rules=$rules;selected_domains=@($pack|Group-Object{$_.screening.domain}|ForEach-Object{@{domain=$_.Name;count=$_.Count}});original_22_retained=@($pack|Where-Object{$_.screening.in_original_22}).Count;independent_human_adjudication=$false;eligibility_reassessed=$false;source_reverification=$false;generation_status='Prepared for a new batch; old 08 remains v2 until replacement generation completes';target_count='None; count is the result of explicit item-level judgments, not an optimized quota';review_timing='Post-v2 methodological revision informed by prior pilot development; before v3 generation. No Survey 2 participant ratings consulted in this revision. Not retrospectively preregistered.'}
Save 'summary.json' $summary
Save 'protocol.json' ([ordered]@{version='3.0';prepared_on='2026-09-30';status='AI-assisted review complete; independent researcher adjudication pending; new generation authorized by user';reference_count=$count;pack_file=$packName;reference_pack_sha256=(Get-FileHash (Join-Path $dir $packName)).Hash;functional_review_sha256=(Get-FileHash (Join-Path $dir 'functional_review.tsv')).Hash;corpus_sha256=(Get-FileHash 'romance_scam_corpus/advice_corpus.jsonl').Hash;teacher_sha256=(Get-FileHash 'Scenarios for AI models_3.docx').Hash;prompts=$promptHashes;fine_tuning=$false;selection_method='Purposeful functional selection with explicit complementary checks and individually documented reserve decisions; qualitative researcher judgments remain necessary';selection_rules=$rules;stopping_rule='Review every eligible item once; retain all judged S1/S2/S3 functions and their necessary companions; reserve R1/R2/R3/R4. No count target or claimed mathematical optimum.';human_validation='Pending; this AI-assisted revision is not an independent researcher sign-off';legacy_batch='The September 27 v2 batch used 53 references and is not relabeled as v3';human_writers='Unaided ordinary adults; main comparison is reference-supported AI versus unaided human advice, not equal information or intrinsic ability'} )
Save 'checks.json' @{eligible_ids_complete=$true;unique_decisions=120;selected=$count;reserve=$reserve.Count;complementary_pairs_complete=$true;all_delivery_in_reserve=$true;matrix_entries=$matrix.Count;original_paraphrases_preserved=$true;independent_human_review=$false}
[IO.File]::WriteAllText((Join-Path $dir 'README.md'),"# Current Alex reference selection: v3`n`nPrepared 30 September 2026. 288 corpus entries unchanged; the prior eligibility boundary is retained (120 eligible, 168 outside scope). Functional selection: $count included, $($reserve.Count) reserve. All 120 eligible entries have an explicit function, rule, comparative rationale and related IDs in functional_review.tsv.`n`nThis is AI-assisted review, not independent expert adjudication. It was performed after v2 pilot generation and before the v3 batch. The count is not an optimum or a preregistered quota. None of the original source paraphrases was rewritten. All eleven supporter-delivery principles are reserved consistently. Complementary verification limitations and meeting exit precautions are included.`n`nThe active pack is $packName. Frozen v2 materials remain unchanged in review_v2 and alex_direct_generation_v2. New outputs belong in alex_direct_generation_v3. Do not relabel an old batch as generated from this pack.`n",$utf)
$summary|ConvertTo-Json -Depth 7
