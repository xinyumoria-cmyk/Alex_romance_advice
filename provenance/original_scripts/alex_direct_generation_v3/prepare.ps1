$ErrorActionPreference='Stop'
$project=(Get-Location).Path;$batch=Join-Path $project 'alex_direct_generation_v3';$source=Join-Path $project 'alex_reference_materials/review_v3';$utf=[Text.UTF8Encoding]::new($false)
function Save($name,$obj){[IO.File]::WriteAllText((Join-Path $batch $name),(ConvertTo-Json -InputObject $obj -Depth 30),$utf)}
if(Test-Path -LiteralPath (Join-Path $batch 'protocol.json')){throw 'Batch inputs already frozen; preparation will not overwrite them'}
foreach($sub in @('prompts','raw','records','responses','checks','frozen_references')){[void][IO.Directory]::CreateDirectory((Join-Path $batch $sub))}
$old=Get-Content -LiteralPath (Join-Path $project 'alex_direct_generation/protocol.json') -Raw -Encoding UTF8|ConvertFrom-Json
$maps=Get-Content -LiteralPath (Join-Path $source 'scenario_reference_map.json') -Raw -Encoding UTF8|ConvertFrom-Json
$sourceProtocol=Get-Content -LiteralPath (Join-Path $source 'protocol.json') -Raw -Encoding UTF8|ConvertFrom-Json
$pack=@(Get-Content -LiteralPath (Join-Path $source 'prompt_pack_60.jsonl') -Encoding UTF8|Where-Object{$_}|ForEach-Object{$_|ConvertFrom-Json})
if($pack.Count-ne60-or$maps.Count-ne8){throw 'Reference or scenario count mismatch'}
if((Get-FileHash -LiteralPath (Join-Path $source 'prompt_pack_60.jsonl')).Hash-ne$sourceProtocol.reference_pack_sha256){throw 'Reference pack changed since its recorded protocol; inspect before generating'}
$baseline=@(foreach($relative in @('alex_direct_generation','alex_direct_generation_v2','alex_reference_materials/review_v2','romance_scam_corpus','Scenarios for AI models_3.docx','analysis_work/before_selection_revision_2026-09-30')){Get-ChildItem -LiteralPath (Join-Path $project $relative) -File -Recurse|ForEach-Object{@{path=$_.FullName.Substring($project.Length+1);sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}}})
Save 'checks/existing_files_before.json' $baseline
Copy-Item -LiteralPath (Join-Path $source 'generation_instructions.txt') -Destination (Join-Path $batch 'generation_instructions.txt')
foreach($name in @('prompt_pack_60.jsonl','scenario_reference_map.json','protocol.json')){Copy-Item -LiteralPath (Join-Path $source $name) -Destination (Join-Path $batch ('frozen_references/'+$name))}
$common=$null
foreach($m in $maps){
 $src=Join-Path $source ('prompts/'+$m.scenario_id+'.txt');$expected=@($sourceProtocol.prompts|Where-Object{$_.scenario_id-eq$m.scenario_id})[0]
 if((Get-FileHash -LiteralPath $src).Hash-ne$expected.sha256){throw ('Scenario prompt changed: '+$m.scenario_id)}
 if(($m.prompt_reference_ids-join',')-ne($pack.advice_id-join',')){throw 'Reference IDs differ between scenarios'}
 $text=[IO.File]::ReadAllText($src,$utf);$marker='REFERENCE MATERIALS (60 entries; common to all eight scenarios)';$idx=$text.IndexOf($marker);if($idx-lt0){throw 'Reference marker missing'};$block=$text.Substring($idx)
 if($null-eq$common){$common=$block}elseif($common-cne$block){throw 'Reference blocks differ'}
 Copy-Item -LiteralPath $src -Destination (Join-Path $batch ('prompts/'+$m.scenario_id+'.txt'))
}
$tasks=[Collections.Generic.List[object]]::new()
for($rep=1;$rep-le5;$rep++){foreach($m in $maps){$tasks.Add([ordered]@{task_id=('V3-'+$m.scenario_id+'-'+$rep.ToString('00'));scenario_id=$m.scenario_id;replicate=$rep;prompt_file=('prompts/'+$m.scenario_id+'.txt');prompt_sha256=(Get-FileHash -LiteralPath (Join-Path $batch ('prompts/'+$m.scenario_id+'.txt'))).Hash})}}
$rng=[Random]::new(20260930);$order=@($tasks);for($i=$order.Count-1;$i-gt0;$i--){$j=$rng.Next($i+1);$swap=$order[$i];$order[$i]=$order[$j];$order[$j]=$swap}
$p=[ordered]@{batch_id='alex-reference-v3-2026-09-30';frozen_at_utc=[DateTime]::UtcNow.ToString('o');authorization='User authorized implementation and replacement of the revised selection results on 2026-09-30; regenerate because the reference pack changed; archive the previous batch';model_requested=$old.model_requested;interface='Codex CLI';auth_plan='ChatGPT account login; no API key supplied or required by this runner';reasoning_effort=$old.reasoning_effort;temperature='not set';top_p='not set';seed='not set';serving_snapshot='not independently available from ordinary CLI event logs';instructions_file='generation_instructions.txt';instructions_sha256=(Get-FileHash -LiteralPath (Join-Path $batch 'generation_instructions.txt')).Hash;reference_count=60;reference_pack_sha256=(Get-FileHash -LiteralPath (Join-Path $batch 'frozen_references/prompt_pack_60.jsonl')).Hash;generation_design='Eight teacher-original scenarios; five independent fresh sessions per scenario; first complete output retained; no resume, fork, previous responses or revision feedback';output_requirements='English; 120-180 words; two or three short paragraphs; advice only';context_controls='Empty temporary working directory; user configuration ignored; project documents disabled; ephemeral fresh sessions; memory, tools, apps, plugins and multi-agent features disabled. CLI and service context cannot be fully independently audited.';retention_policy='Keep all complete outputs, including those failing length or content checks; do not silently edit, replace or choose among outputs';retry_policy='Retry only an empty-output transient transport failure, at most three attempts; retain all logs; stop on nonempty incomplete output or access/model failure';order_seed=20260930;order_seed_note='Only randomizes task scheduling, not model sampling';human_validation='Pending; user authorization to generate does not constitute independent validation of the screening';fine_tuning=$false;word_document='Word versions/08 - Alex GPT-6 Advice - 40 Responses - Reference v3.docx';scenarios=$maps;tasks=$order}
Save 'protocol.json' $p
Save 'generation_status.json' @{status='prepared_waiting_for_cli_login';completed=0;expected=40;checked_utc=[DateTime]::UtcNow.ToString('o');old_batch_preserved=$true}
'Frozen 40 tasks, eight scenario prompts and the common 60-entry reference pack; no model calls made.'
