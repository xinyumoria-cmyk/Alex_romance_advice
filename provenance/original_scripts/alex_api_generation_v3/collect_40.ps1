$ErrorActionPreference='Stop'
$project=(Get-Location).Path
$batch=Join-Path $project 'alex_api_generation_v3'
. ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $project 'alex_direct_generation/docx_helpers.ps1'),[Text.Encoding]::UTF8)))
$protocol=Get-Content -LiteralPath (Join-Path $batch 'protocol_40.json') -Raw -Encoding UTF8|ConvertFrom-Json
$records=@(Get-ChildItem -LiteralPath (Join-Path $batch 'records') -Filter '*.json'|ForEach-Object{Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8|ConvertFrom-Json}|Sort-Object scenario_id,replicate)
if($records.Count-ne40){throw 'Expected forty completed responses'}
$baseline=Get-Content -LiteralPath (Join-Path $batch 'first_ten_baseline.json') -Raw -Encoding UTF8|ConvertFrom-Json
foreach($entry in $baseline.PSObject.Properties){if((Get-FileHash -LiteralPath (Join-Path $batch $entry.Name)).Hash-ne$entry.Value){throw ('Original ten-response artifact changed: '+$entry.Name)}}
foreach($entry in $protocol.inputs.PSObject.Properties){if((Get-FileHash -LiteralPath (Join-Path $batch $entry.Name)).Hash-ne$entry.Value){throw 'Frozen input changed'}}
$reviews=@(Import-Csv -LiteralPath (Join-Path $batch 'context_review_40.tsv') -Delimiter "`t" -Encoding UTF8)
if($reviews.Count-ne40-or@($reviews.task_id|Sort-Object -Unique).Count-ne40){throw 'Expected 40 contextual review records'}
$pattern="\b[\w]+(?:['\u2019\-\u2010\u2011][\w]+)*\b"
foreach($item in $records){
 if((Get-FileHash -LiteralPath (Join-Path $batch ('responses/'+$item.task_id+'.txt'))).Hash-ne$item.response_sha256){throw 'Raw hash mismatch'}
 $raw=Get-Content -LiteralPath (Join-Path $batch ('raw/'+$item.task_id+'.response.json')) -Raw -Encoding UTF8|ConvertFrom-Json
 if($raw.model-ne'gpt-6-astra'){throw 'Returned model differs from requested model'}
 $messageText=(@($raw.output|Where-Object{$_.type-eq'message'}|ForEach-Object{$_.content}|Where-Object{$_.type-eq'output_text'}|ForEach-Object{$_.text})-join"`n`n")
 if($messageText-cne$item.advice-or$raw.status-ne'completed'){throw 'API output mismatch'}
 $request=Get-Content -LiteralPath (Join-Path $batch ('requests/'+$item.task_id+'.json')) -Raw -Encoding UTF8|ConvertFrom-Json
 if($request.model-ne'gpt-6-astra'-or$request.reasoning.effort-ne'medium'-or$request.store-ne$false-or$request.max_output_tokens-ne8192){throw 'Settings mismatch'}
 if($request.PSObject.Properties.Name -contains 'previous_response_id'-or$request.PSObject.Properties.Name -contains 'tools'){throw 'Unexpected history or tools'}
 if($request.input-cne[IO.File]::ReadAllText((Join-Path $batch ('prompts/'+$item.scenario_id+'.txt')),[Text.Encoding]::UTF8)){throw 'Prompt mismatch'}
 if($request.instructions-cne[IO.File]::ReadAllText((Join-Path $batch 'generation_instructions.txt'),[Text.Encoding]::UTF8)){throw 'Instructions mismatch'}
 $item|Add-Member -NotePropertyName checked_word_count -NotePropertyValue ([regex]::Matches($item.advice,$pattern).Count)
 $item|Add-Member -NotePropertyName contextual_review -NotePropertyValue @($reviews|Where-Object{$_.task_id-eq$item.task_id})[0]
}
$inputTotal=($records.usage.input_tokens|Measure-Object -Sum).Sum
$outputTotal=($records.usage.output_tokens|Measure-Object -Sum).Sum
$new=@($records|Where-Object{$_.scenario_id-notin@('S01','S02')})
$flags=@($reviews|Where-Object{$_.status-ne'no_clear_issue'})
$check=[ordered]@{completed=40;new_responses=30;per_scenario=@($records|Group-Object scenario_id|Select-Object Name,Count);minimum_words=($records.checked_word_count|Measure-Object -Minimum).Minimum;maximum_words=($records.checked_word_count|Measure-Object -Maximum).Maximum;length_failures=@($records|Where-Object{$_.checked_word_count-lt120-or$_.checked_word_count-gt180}|Select-Object task_id,checked_word_count);format_failures=@($records|Where-Object{$_.paragraph_count-notin@(2,3)}|Select-Object task_id,paragraph_count);unique_response_ids=@($records.response_id|Sort-Object -Unique).Count;unique_text_hashes=@($records.response_sha256|Sort-Object -Unique).Count;input_tokens=$inputTotal;output_tokens=$outputTotal;total_tokens=($inputTotal+$outputTotal);new_input_tokens=($new.usage.input_tokens|Measure-Object -Sum).Sum;new_output_tokens=($new.usage.output_tokens|Measure-Object -Sum).Sum;cached_input_tokens=($records.usage.input_tokens_details.cached_tokens|Measure-Object -Sum).Sum;cache_write_tokens=($records.usage.input_tokens_details.cache_write_tokens|Measure-Object -Sum).Sum;reasoning_tokens=($records.usage.output_tokens_details.reasoning_tokens|Measure-Object -Sum).Sum;first_ten_artifacts_unchanged=$true;human_review_pending=$true;contextual_flags=$flags;visual_qa=$false}
if($check.unique_response_ids-ne40-or$check.unique_text_hashes-ne40-or@($check.per_scenario|Where-Object{$_.Count-ne5}).Count){throw 'Batch structure mismatch'}
[IO.File]::WriteAllLines((Join-Path $batch 'generated_advice_40.jsonl'),[string[]]@($records|ForEach-Object{ConvertTo-Json -InputObject $_ -Depth 15 -Compress}),$utf)
$docName='10 - Alex GPT-6 API Advice - 40 Responses - Reference v3.docx'
if(Test-Path -LiteralPath (Join-Path $out $docName)){throw 'Refusing to overwrite existing Word file'}
New-Doc $docName
Add-P 'Alex API Advice: 40 Responses' 'Title'
Add-P 'Eight scenarios | Five responses each | Reference v3 | 30 September 2026' 'Subtitle'
$rows=@(
 @{cells=@('Model and settings','Requested and returned: gpt-6-astra. OpenAI Responses API; reasoning effort medium; max_output_tokens 8192; store false. Temperature and top_p omitted.')},
 @{cells=@('Inputs and calls','Same confirmed 60-entry reference pack and v3 instructions. Forty independent calls; no prior conversations or outputs supplied, no tools. S01-S02 retained from the first ten-response batch; S03-S08 added without changing settings.')},
 @{cells=@('Output checks',($check.minimum_words.ToString()+'-'+$check.maximum_words+' words; '+$check.length_failures.Count+' outside 120-180 words; '+$check.format_failures.Count+' outside two or three paragraphs. All raw wording retained.'))},
 @{cells=@('Human review','Pending. Two priority factual paraphrases (S05-01, S05-02), six other paraphrase checks, and thirteen optional boundary-wording checks are listed at the end. Optional checks are not established errors. This is not independent human validation.')},
 @{cells=@('Token usage',('All 40: '+$inputTotal+' input and '+$outputTotal+' output tokens. Added 30: '+$check.new_input_tokens+' input and '+$check.new_output_tokens+' output tokens. Counts are returned by the API.'))},
 @{cells=@('Research interpretation','Reference-supported AI advice compared with independently written, unaided human advice. The reference pack is supplied context, not model parameter training.')}
)
Add-Table @('Item','Record') $rows @(2400,6960)
Add-P 'Outputs within a scenario can be similar in actions and wording. Separate calls do not establish five distinct advice strategies. Raw responses and reproducibility records are retained in alex_api_generation_v3; the historical CLI batch and the first ten-response Word file remain unchanged.'
foreach($sid in @('S01','S02','S03','S04','S05','S06','S07','S08')){
 Add-Break;Add-P ($sid+' | Scenario') 'Heading1'
 $prompt=[IO.File]::ReadAllText((Join-Path $batch ('prompts/'+$sid+'.txt')),[Text.Encoding]::UTF8)
 $scenario=($prompt-split'\r?\n\r?\nQUESTION\r?\n',2)[0]-replace'^SCENARIO\r?\n',''
 Add-Text $scenario 'Scenario'
 Add-P 'I am not sure what to think. What should I do? What risks should I be aware of?' 'Scenario'
 foreach($item in @($records|Where-Object{$_.scenario_id-eq$sid})){
  Add-P ($item.task_id+' | '+$item.checked_word_count+' words') 'Heading2'
  foreach($para in ($item.advice-split'\n\s*\n')){Add-P $para 'Advice'}
 }
}
Add-Break;Add-P 'Human review notes' 'Heading1'
Add-P 'Distinguish factual paraphrase concerns from proposed boundary wording. Some statements broaden the original scenario; others are preventive advice rather than factual claims. Preserve the raw output and record researcher decisions separately. Previous approvals of other batches do not apply automatically.'
foreach($group in @($flags|Group-Object note)){Add-P (($group.Group.task_id-join', ')+': '+$group.Name) 'Small'}
$docText=Finish-Doc
foreach($item in $records){foreach($para in ($item.advice-split'\n\s*\n')){if(!$docText.Contains($para)){throw 'Missing raw paragraph in Word'}}}
$check.word_document=$docName
$check.docx_sha256=(Get-FileHash -LiteralPath $docPath).Hash
[IO.File]::WriteAllText((Join-Path $batch 'checks_40.json'),(ConvertTo-Json -InputObject $check -Depth 15),$utf)
$check|ConvertTo-Json -Depth 8
