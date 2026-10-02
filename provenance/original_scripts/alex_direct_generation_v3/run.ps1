param([int]$Limit=40)
$ErrorActionPreference='Stop'
$batch=if($PSScriptRoot){$PSScriptRoot}else{Join-Path (Get-Location).Path 'alex_direct_generation_v3'}
$utf=[Text.UTF8Encoding]::new($false)
function Save($name,$obj){[IO.File]::WriteAllText((Join-Path $batch $name),(ConvertTo-Json -InputObject $obj -Depth 30),$utf)}
function QuoteArg([string]$s){if($s-match'[\s"]'){return '"'+($s-replace'(\\*)"','$1$1\"'-replace'(\\+)$','$1$1')+'"'};return $s}
$protocol=Get-Content -LiteralPath (Join-Path $batch 'protocol.json') -Raw -Encoding UTF8|ConvertFrom-Json
$codex=(Get-Command codex -ErrorAction Stop).Source
$ErrorActionPreference='Continue';$login=(& $codex login status 2>&1|Out-String).Trim();$ErrorActionPreference='Stop'
if($login-notmatch'Logged in using ChatGPT'){Save 'generation_status.json' @{status='blocked_cli_login';completed=@(Get-ChildItem -LiteralPath (Join-Path $batch 'records') -Filter '*.json').Count;expected=40;checked_utc=[DateTime]::UtcNow.ToString('o');login_status=$login};throw 'Codex CLI is not logged in with ChatGPT. Run codex login, then resume this same batch.'}
Save ('checks/run-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff')+'.json') @{started_utc=[DateTime]::UtcNow.ToString('o');cli_version=(& $codex --version|Out-String).Trim();auth_status=$login;model_requested=$protocol.model_requested;reasoning_effort=$protocol.reasoning_effort;runner_sha256=(Get-FileHash -LiteralPath (Join-Path $batch 'run.ps1')).Hash}
$done=0
foreach($task in $protocol.tasks){
 $recordPath=Join-Path $batch ('records/'+$task.task_id+'.json')
 if(Test-Path -LiteralPath $recordPath){$existing=Get-Content -LiteralPath $recordPath -Raw -Encoding UTF8|ConvertFrom-Json;if($existing.status-eq'completed'){continue};throw ('Unresolved prior result '+$task.task_id)}
 if($done-ge$Limit){break}
 $promptPath=Join-Path $batch $task.prompt_file;$instructionsPath=Join-Path $batch $protocol.instructions_file
 if((Get-FileHash -LiteralPath $promptPath).Hash-ne$task.prompt_sha256-or(Get-FileHash -LiteralPath $instructionsPath).Hash-ne$protocol.instructions_sha256){throw 'Frozen input changed'}
 for($attempt=1;$attempt-le3;$attempt++){
  $prefix=Join-Path $batch ('raw/'+$task.task_id+'-attempt'+$attempt)
  if(Test-Path -LiteralPath ($prefix+'.launch.json')){throw ('Existing attempt found; retain and resolve '+$task.task_id)}
  $cwd=Join-Path ([IO.Path]::GetTempPath()) ('alex-v3-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($cwd)
  $outputPath=Join-Path $batch ('responses/'+$task.task_id+'.txt');if(Test-Path -LiteralPath $outputPath){throw 'Refusing to overwrite a raw response'}
  $argv=@('exec','--ignore-user-config','--ephemeral','--skip-git-repo-check','--sandbox','read-only','--model',$protocol.model_requested,'--cd',$cwd,'--json','--color','never','--output-last-message',$outputPath,'-c',('model_reasoning_effort="'+$protocol.reasoning_effort+'"'),'-c','model_provider="openai"','-c','approval_policy="never"','-c','web_search="disabled"','-c','project_doc_max_bytes=0','-c','personality="none"','-c',('model_instructions_file="'+($instructionsPath-replace'\\','/')+'"'))
  foreach($feature in @('memories','multi_agent','multi_agent_v2','apps','plugins','hooks','shell_tool','unified_exec','browser_use','browser_use_external','computer_use','image_generation','view_image','skill_search','workspace_dependencies')){$argv+=@('--disable',$feature)}
  $argv+='-'
  $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=$codex;$psi.Arguments=($argv|ForEach-Object{QuoteArg $_})-join' ';$psi.WorkingDirectory=$cwd;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.StandardOutputEncoding=$utf;$psi.StandardErrorEncoding=$utf
  foreach($name in @('OPENAI_API_KEY','CODEX_API_KEY','CODEX_ACCESS_TOKEN','CODEX_THREAD_ID')){[void]$psi.EnvironmentVariables.Remove($name)}
  $started=[DateTime]::UtcNow.ToString('o');$p=[Diagnostics.Process]::new();$p.StartInfo=$psi;if(!$p.Start()){throw 'Unable to start Codex'}
  Save ('raw/'+$task.task_id+'-attempt'+$attempt+'.launch.json') @{task_id=$task.task_id;attempt=$attempt;started_utc=$started;pid=$p.Id;arguments=$argv;cwd=$cwd;prompt_sha256=$task.prompt_sha256}
  $outTask=$p.StandardOutput.ReadToEndAsync();$errTask=$p.StandardError.ReadToEndAsync();$p.StandardInput.Write([IO.File]::ReadAllText($promptPath,$utf));$p.StandardInput.Close()
  while(!$p.WaitForExit(30000)){Write-Output ('Waiting for '+$task.task_id+'; first response still running.')}
  $stdout=$outTask.Result;$stderr=$errTask.Result;$code=$p.ExitCode;$p.Dispose()
  [IO.File]::WriteAllText(($prefix+'.events.jsonl'),$stdout,$utf);[IO.File]::WriteAllText(($prefix+'.stderr.txt'),$stderr,$utf)
  $events=@(foreach($line in ($stdout-split'\r?\n')){if($line.Trim()){try{$line|ConvertFrom-Json}catch{}}})
  $complete=@($events|Where-Object{$_.type-eq'turn.completed'}).Count-gt0;$thread=@($events|Where-Object{$_.type-eq'thread.started'}|Select-Object -First 1)
  $tools=@($events|Where-Object{$_.type-eq'item.completed'-and$_.item.type-notin@('agent_message','reasoning')})
  $messages=@($events|Where-Object{$_.type-eq'item.completed'-and$_.item.type-eq'agent_message'})
  $content=if(Test-Path -LiteralPath $outputPath){[IO.File]::ReadAllText($outputPath,$utf)}else{''}
  $status=if($content.Trim()-and$complete-and$code-eq0-and$tools.Count-eq0-and$messages.Count-eq1-and$messages[0].item.text.Trim()-ceq$content.Trim()){'completed'}elseif($content.Trim()){'nonempty_requires_resolution'}else{'no_output_failure'}
  $result=[ordered]@{task_id=$task.task_id;scenario_id=$task.scenario_id;replicate=$task.replicate;attempt=$attempt;status=$status;started_utc=$started;ended_utc=[DateTime]::UtcNow.ToString('o');exit_code=$code;thread_id=$(if($thread.Count){$thread[0].thread_id}else{$null});turn_completed=$complete;unexpected_tool_events=$tools;requested_model=$protocol.model_requested;serving_snapshot=$null;reasoning_effort=$protocol.reasoning_effort;response_file=('responses/'+$task.task_id+'.txt');response_sha256=$(if($content){(Get-FileHash -LiteralPath $outputPath).Hash}else{$null});usage=@($events|Where-Object{$_.type-eq'turn.completed'}|ForEach-Object{$_.usage})}
  Save ('raw/'+$task.task_id+'-attempt'+$attempt+'.result.json') $result
  if($status-eq'completed'){Save ('records/'+$task.task_id+'.json') $result;$done++;$count=@(Get-ChildItem -LiteralPath (Join-Path $batch 'records') -Filter '*.json').Count;Save 'generation_status.json' @{status=$(if($count-eq40){'generation_complete_checks_pending'}else{'in_progress'});completed=$count;expected=40;updated_utc=[DateTime]::UtcNow.ToString('o')};Write-Output ('Completed '+$task.task_id+'; batch '+$count+'/40');break}
  if($content.Trim()){Save ('records/'+$task.task_id+'.json') $result;throw ('Nonempty output retained for resolution: '+$task.task_id)}
  $errorText=$stderr+"`n"+$stdout
  if($errorText-match'(?i)unauthorized|authentication|not supported|does not exist|not found|permission|401|403|login|sign.in'){throw ('Access or model failure; see retained logs for '+$task.task_id)}
  if($attempt-eq3-or$errorText-notmatch'(?i)429|50[0234]|timed?.?out|temporar|connection|transport|stream disconnected'){throw ('Generation failed; see retained logs for '+$task.task_id)}
  if(Test-Path -LiteralPath $outputPath){$resolved=(Resolve-Path -LiteralPath $outputPath).Path;$destination=[IO.Path]::GetFullPath($prefix+'.empty-response.txt');$allowed=[IO.Path]::GetFullPath($batch).TrimEnd('\')+'\';if(!$resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)-or!$destination.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Retry archive outside batch'};Move-Item -LiteralPath $resolved -Destination $destination}
  Start-Sleep -Seconds (3*$attempt)
 }
}
'Runner finished; completed records: '+@(Get-ChildItem -LiteralPath (Join-Path $batch 'records') -Filter '*.json').Count+'/40'
