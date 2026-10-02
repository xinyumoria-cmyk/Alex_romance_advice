param([switch]$AllowPartial)
$ErrorActionPreference='Stop'
$project=(Get-Location).Path;$batch=Join-Path $project 'alex_direct_generation_v3';$utf=[Text.UTF8Encoding]::new($false)
$protocol=Get-Content -LiteralPath (Join-Path $batch 'protocol.json') -Raw -Encoding UTF8|ConvertFrom-Json
$scenarios=if($protocol.scenarios.PSObject.Properties.Name-contains'value'){@($protocol.scenarios.value)}else{@($protocol.scenarios)}
if($scenarios.Count-ne8-or@($scenarios.scenario_id|Sort-Object -Unique).Count-ne8){throw 'Expected eight scenario records'}
$contextReview=@{}
$contextPath=Join-Path $batch 'checks/context_review.tsv'
if(Test-Path -LiteralPath $contextPath){foreach($review in (Import-Csv -LiteralPath $contextPath -Delimiter '|' -Encoding UTF8)){if($contextReview.ContainsKey($review.task_id)){throw 'Duplicate contextual review ID'};$contextReview[$review.task_id]=$review}}
$resolutions=@();$resolutionPath=Join-Path $batch 'checks/review_resolutions.json'
if(Test-Path -LiteralPath $resolutionPath){$resolutions=Get-Content -LiteralPath $resolutionPath -Raw -Encoding UTF8|ConvertFrom-Json;foreach($resolution in $resolutions){if($resolution.status-eq'user_confirmed'-and$contextReview.ContainsKey($resolution.task_id)){$contextReview[$resolution.task_id].status='user_confirmed';$contextReview[$resolution.task_id].note=$resolution.note}}}
function Save($name,$obj){[IO.File]::WriteAllText((Join-Path $batch $name),(ConvertTo-Json -InputObject $obj -Depth 30),$utf)}
$items=[Collections.Generic.List[object]]::new();$missing=[Collections.Generic.List[string]]::new()
$wordPattern="\b[\w]+(?:['\u2019\-\u2010\u2011][\w]+)*\b"
foreach($task in $protocol.tasks){
 $rp=Join-Path $batch ('records/'+$task.task_id+'.json')
 if(!(Test-Path -LiteralPath $rp)){$missing.Add($task.task_id);continue}
 $record=Get-Content -LiteralPath $rp -Raw -Encoding UTF8|ConvertFrom-Json
 if($record.status-ne'completed'){throw ('Unresolved nonempty result: '+$task.task_id)}
 $path=Join-Path $batch $record.response_file;$content=[IO.File]::ReadAllText($path,$utf)
 if((Get-FileHash -LiteralPath $path).Hash-ne$record.response_sha256){throw 'Raw output changed'}
 $events=@(Get-Content -LiteralPath (Join-Path $batch ('raw/'+$task.task_id+'-attempt'+$record.attempt+'.events.jsonl')) -Encoding UTF8|Where-Object{$_}|ForEach-Object{$_|ConvertFrom-Json})
 $messages=@($events|Where-Object{$_.type-eq'item.completed'-and$_.item.type-eq'agent_message'})
 if($messages.Count-ne1-or$messages[0].item.text.Trim()-cne$content.Trim()){throw 'Raw output/event mismatch'}
 if(@($record.unexpected_tool_events).Count-ne0){throw 'Unexpected model tool usage'}
 if($record.requested_model-ne$protocol.model_requested-or$record.reasoning_effort-ne$protocol.reasoning_effort){throw 'Generation setting mismatch'}
 $wc=[regex]::Matches($content,$wordPattern).Count
 $paras=@($content.Trim()-split'(?:\r?\n\s*){2,}'|Where-Object{$_.Trim()})
 $flags=[Collections.Generic.List[string]]::new()
 if($wc-lt120-or$wc-gt180){$flags.Add('Length outside 120-180 words')}
 if($paras.Count-notin@(2,3)-or$content-match'(?m)^\s*(?:#{1,6}\s|[-*]\s|\d+[.)]\s)'){$flags.Add('Paragraph/list format needs review')}
 if($content-match'(?i)\b(GPT|Codex|NVIDIA|ADV\d{4}|research study|language model)\b'){$flags.Add('Possible source/study disclosure')}
 if($content-match'(?i)\b(screen.?shar\w*|passport|identity document|ID photo|bank statement|repayment agreement)\b'){$flags.Add('Document or verification phrase: inspect context')}
 if($content-match'(?i)\b(already (sent|paid|transferred)|military|parcel|investment|crypto|police|law enforcement)\b'){$flags.Add('Scenario-specific phrase: inspect context')}
 $items.Add([ordered]@{task_id=$task.task_id;scenario_id=$task.scenario_id;replicate=$task.replicate;text=$content;paragraphs=$paras;word_count=$wc;paragraph_count=$paras.Count;automated_flags=@($flags);raw_sha256=$record.response_sha256;thread_id=$record.thread_id;model_requested=$record.requested_model;reasoning_effort=$record.reasoning_effort;interface='Codex CLI';reference_version='3.0';reference_count=60;editing='none';human_review='pending';semantic_review='Not established by keyword checks';usage=$record.usage;started_utc=$record.started_utc;ended_utc=$record.ended_utc})
}
if(@($items.thread_id|Sort-Object -Unique).Count-ne$items.Count){throw 'Repeated session ID'}
$sorted=@($items|Sort-Object { $_.scenario_id },{ [int]$_.replicate })
$jsonlName=if($missing.Count){'partial_advice.jsonl'}else{'generated_advice.jsonl'}
[IO.File]::WriteAllLines((Join-Path $batch $jsonlName),[string[]]@($sorted|ForEach-Object{ConvertTo-Json -InputObject $_ -Depth 20 -Compress}),$utf)
$baseline=Get-Content -LiteralPath (Join-Path $batch 'checks/existing_files_before.json') -Raw -Encoding UTF8|ConvertFrom-Json
foreach($entry in $baseline){if((Get-FileHash -LiteralPath (Join-Path $project $entry.path)).Hash-ne$entry.sha256){throw ('Pre-existing file changed: '+$entry.path)}}
$check=[ordered]@{completed=$items.Count;expected=40;missing=@($missing);unique_sessions=@($items.thread_id|Sort-Object -Unique).Count;unique_raw_hashes=@($items.raw_sha256|Sort-Object -Unique).Count;minimum_words=($items.word_count|Measure-Object -Minimum).Minimum;maximum_words=($items.word_count|Measure-Object -Maximum).Maximum;length_failures=@($items|Where-Object{$_.word_count-lt120-or$_.word_count-gt180}).Count;items_flagged=@($items|Where-Object{$_.automated_flags.Count}).Count;original_files_preserved=$true;protected_files=$baseline.Count;independent_human_validation=$false;semantic_validation='Keyword checks identify candidates for contextual review; they do not establish semantic correctness';items=@($items|ForEach-Object{@{task_id=$_.task_id;word_count=$_.word_count;paragraph_count=$_.paragraph_count;flags=$_.automated_flags}})}
Save 'checks/automated_checks.json' $check
Save 'checks/context_review_summary.json' @{reviewer='Codex assistant contextual reading; individual user decisions recorded separately';reviewed_count=$contextReview.Count;flags=@($contextReview.Values|Where-Object{$_.status-notin@('no_clear_issue','user_confirmed')});resolutions=@($resolutions);criteria='Scenario facts; distinction between conversational and payment urgency; future money conditions; expressed emotion attributed to Alex; no fraud verdict, unsafe verification, or unreported loss; proportionality';editing='None; all raw outputs retained'}
if($missing.Count){if(!$AllowPartial){throw ('Batch incomplete: '+$items.Count+'/40. No Word response document created.')};$check|ConvertTo-Json -Depth 5;return}
$docName='08 - Alex GPT-6 Advice - 40 Responses - Reference v3.docx'
$docPath=Join-Path (Join-Path $project 'Word versions') $docName
if(Test-Path -LiteralPath $docPath){throw 'New batch Word file already exists; refusing overwrite'}
. ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $project 'alex_direct_generation/docx_helpers.ps1'),[Text.Encoding]::UTF8)))
New-Doc $docName
Add-P 'Alex Advice: 40 Responses' 'Title'
Add-P 'Function-reviewed 60-entry reference pack | Batch v3 | Unedited first responses' 'Subtitle'
Add-P 'This batch uses the revised common reference pack. Each of the eight original Alex scenarios receives five independent first responses. The original v1 and v2 batches and their review records are preserved separately. This v3 batch replaces the active 08 document after a 30 September functional selection review; previous human wording approvals do not transfer to these new texts.'
$methodRows=@(
 @{cells=@('Requested model / interface',($protocol.model_requested+' / Codex CLI with ChatGPT account login'))},
 @{cells=@('Reference input','Same ordered 60-entry pack in all scenarios; entry-specific use guards; no parameter fine-tuning')},
 @{cells=@('Session design','40 fresh sessions; one completed first response each; no previous outputs or editing feedback')},
 @{cells=@('Recorded settings',('Reasoning effort: '+$protocol.reasoning_effort+'. Temperature, top_p and sampling seed not set; serving snapshot not independently verified.'))},
 @{cells=@('Requested format','English; 120-180 words; two or three paragraphs')},
 @{cells=@('Observed word counts',([string]$check.minimum_words+'-'+[string]$check.maximum_words+'; '+[string]$check.length_failures+' outside the requested range'))},
 @{cells=@('Review status',([string]$check.items_flagged+' outputs have automated flags; human review pending. Flags require context and are not findings of error.'))},
 @{cells=@('AI contextual reading',([string]$contextReview.Count+' responses read against scenario facts and use guards; '+[string]@($contextReview.Values|Where-Object{$_.status-notin@('no_clear_issue','user_confirmed')}).Count+' open flags; '+[string]@($contextReview.Values|Where-Object{$_.status-eq'user_confirmed'}).Count+' wording decisions confirmed by the user. This is not full-batch independent human validation.'))},
 @{cells=@('Output policy','All first completed outputs retained, including flagged items; no silent rewriting or replacement')}
)
Add-Table @('Item','Recorded method / result') $methodRows @(2400,6960)
Add-P 'The corpus was supplied to AI only. Human survey writers produce their own advice without this reference pack. This information-access difference should be disclosed when reporting the comparison.'
foreach($scenario in $scenarios){
 Add-Break;Add-P ($scenario.scenario_id+' | Alex scenario') 'Heading1'
 Add-P ('Urgency: '+$scenario.urgency+' | Financial cue: '+$scenario.financial_cue+' | Emotional intensity: '+$scenario.emotional_intensity) 'Small'
 Add-Text $scenario.scenario_text 'Scenario';Add-P $scenario.question 'Scenario'
 foreach($item in @($sorted|Where-Object{$_.scenario_id-eq$scenario.scenario_id})){
  Add-P ($item.task_id+' | '+$item.word_count+' words') 'Heading2'
  foreach($paragraph in $item.paragraphs){Add-P $paragraph 'Advice'}
  if($item.automated_flags.Count){Add-P ('Automated keyword/format flag: '+($item.automated_flags-join'; ')) 'Small';if($contextReview.ContainsKey($item.task_id)-and$contextReview[$item.task_id].status-eq'no_clear_issue'){Add-P ('AI contextual reading: '+$contextReview[$item.task_id].note+' Independent human review remains pending.') 'Small'}}
  if($contextReview.ContainsKey($item.task_id)-and$contextReview[$item.task_id].status-ne'no_clear_issue'){Add-P $contextReview[$item.task_id].note 'Small'}
 }
}
Add-Break;Add-P 'Generation record' 'Heading1'
Add-P ('Frozen batch: '+$protocol.batch_id+'. Raw responses, CLI events, per-session records, input hashes and automated checks are stored in alex_direct_generation_v3. The frozen generation instructions and scenario prompts are available there for reproduction.')
Add-P 'The exact serving snapshot and all service-side settings cannot be independently verified from these CLI event logs. Fresh-session controls reduce previous-conversation exposure but do not imply that every element of runtime context was independently audited.'
Add-Link 'OpenAI documentation: non-interactive Codex execution' 'https://learn.chatgpt.com/docs/non-interactive-mode' 'Small'
$docText=Finish-Doc
foreach($item in $sorted){foreach($paragraph in $item.paragraphs){if(!$docText.Contains($paragraph)){throw ('Missing Word text: '+$item.task_id)}}}
Save 'checks/word_checks.json' @{all_40_raw_texts_present=$true;word_document=$docName;font='Times New Roman';xml_and_table_geometry_checked=$true;visual_render_verified=$false;visual_review_status='Pending; check LibreOffice availability before delivery';sha256=(Get-FileHash -LiteralPath $docPath).Hash}
Save 'generation_status.json' @{status='generated_and_structurally_checked';completed=40;expected=40;word_document=$docName;human_review='pending';updated_utc=[DateTime]::UtcNow.ToString('o')}
$check|ConvertTo-Json -Depth 6
