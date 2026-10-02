$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root=(Get-Location).Path
$batch=Join-Path $root 'alex_api_generation_v3'
$path=Join-Path $root 'Word versions/10 - Alex GPT-6 API Advice - 40 Responses - Reference v3.docx'
$utf=[Text.UTF8Encoding]::new($false)
$backup=Join-Path $batch ('document_backups/'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff'))
[void][IO.Directory]::CreateDirectory($backup)
Copy-Item -LiteralPath $path -Destination (Join-Path $backup ([IO.Path]::GetFileName($path)))
function ReadParts($p){
 $parts=@{};$z=[IO.Compression.ZipFile]::OpenRead($p)
 try{foreach($e in $z.Entries){$r=[IO.StreamReader]::new($e.Open());$parts[$e.FullName]=$r.ReadToEnd();$r.Dispose()}}finally{$z.Dispose()}
 return $parts
}
$before=ReadParts $path
[xml]$doc=$before['word/document.xml']
$ns=[Xml.XmlNamespaceManager]::new($doc.NameTable);$ns.AddNamespace('w','http://schemas.openxmlformats.org/wordprocessingml/2006/main')
$adviceBefore=@($doc.SelectNodes('//w:p[w:pPr/w:pStyle[@w:val="Advice"]]',$ns)|ForEach-Object{$_.OuterXml})
$mapping=[ordered]@{
 'Human review'='Output provenance and observations'
 'Pending. Two priority factual paraphrases (S05-01, S05-02), six other paraphrase checks, and thirteen optional boundary-wording checks are listed at the end. Optional checks are not established errors. This is not independent human validation.'='All 40 advice texts are unedited GPT-6 Astra API outputs generated from researcher-supplied scenarios, instructions and references. The notes at the end are separate Codex-assisted observations, not advice content, independent human validation, or instructions to revise, exclude or regenerate responses.'
 'Human review notes'='Researcher-only observations (not stimulus content)'
 'Distinguish factual paraphrase concerns from proposed boundary wording. Some statements broaden the original scenario; others are preventive advice rather than factual claims. Preserve the raw output and record researcher decisions separately. Previous approvals of other batches do not apply automatically.'='These Codex-assisted observations describe model behavior; they are not validated error ratings. All 40 advice texts remain unchanged and retained. Do not show these notes to survey evaluators. Observations alone do not trigger editing, exclusion or regeneration. Any exclusions require prospectively specified criteria applied consistently to AI and human advice; these notes do not establish such criteria.'
 'The advice proposes a boundary about not being the only or sole support. This is a suggested boundary, not an explicit assertion that Alex lacks other support. Review its proportionality; it is not classified as an established scenario error.'='The advice proposes a boundary about not being the only or sole support. This is preventive advice rather than an explicit claim that Alex lacks other support. It is recorded as an interpretive observation, not an established error or a reason to change the output.'
 'Priority: the opening states that Alex says the recipient is their only support. The scenario only says the recipient is the only person Alex feels comfortable talking to right now. This factual paraphrase broadens the scenario; resolve before use as a final stimulus.'='The opening attributes an only-support statement to Alex. The scenario states only that the recipient is the person Alex feels comfortable talking to right now. The broader paraphrase is a feature of the original model output, retained unchanged; this observation does not require correction or exclusion.'
 'Check the opening paraphrase of exclusive confidant or person available to talk. It weakens or omits the original comfort and right-now qualifications. Decide whether the wording broadens the scenario; no automatic approval from earlier batches.'='The opening paraphrase weakens or omits the original comfort or right-now qualifications. This possible change in scope is recorded as a property of the original model wording, not an instruction to revise or remove the response.'
 'The opening retains tonight and comfort but substitutes source of support for person comfortable talking to. Review whether that broadens the intended conversational meaning.'='The opening retains tonight and comfort but substitutes source of support for person comfortable talking to. This may broaden the conversational meaning; the original wording is retained without editing or exclusion.'
}
$changes=0
foreach($pair in $mapping.GetEnumerator()){
 $matches=@($doc.SelectNodes('//w:t',$ns)|Where-Object{if($pair.Key-eq'Human review'){$_.InnerText-ceq$pair.Key}else{$_.InnerText.Contains($pair.Key)}})
 if($matches.Count-ne1){throw ('Expected one note match: '+$pair.Key)}
 $matches[0].InnerText=$matches[0].InnerText.Replace($pair.Key,$pair.Value)
 $changes++
}
$adviceAfter=@($doc.SelectNodes('//w:p[w:pPr/w:pStyle[@w:val="Advice"]]',$ns)|ForEach-Object{$_.OuterXml})
if(($adviceBefore-join"`n")-cne($adviceAfter-join"`n")){throw 'Advice paragraph XML changed'}
$z=[IO.Compression.ZipFile]::Open($path,[IO.Compression.ZipArchiveMode]::Update)
try{$e=$z.GetEntry('word/document.xml');$e.Delete();$e=$z.CreateEntry('word/document.xml');$writer=[IO.StreamWriter]::new($e.Open(),$utf);$writer.Write($doc.OuterXml);$writer.Dispose()}finally{$z.Dispose()}
$after=ReadParts $path
foreach($name in $before.Keys){if($name-ne'word/document.xml'-and$before[$name]-cne$after[$name]){throw ('Unexpected package change: '+$name)}}
[xml]$verified=$after['word/document.xml']
$vns=[Xml.XmlNamespaceManager]::new($verified.NameTable);$vns.AddNamespace('w','http://schemas.openxmlformats.org/wordprocessingml/2006/main')
$allText=($verified.SelectNodes('//w:t',$vns)|ForEach-Object{$_.InnerText})-join"`n"
$records=@(Get-ChildItem -LiteralPath (Join-Path $batch 'records') -Filter '*.json'|ForEach-Object{Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8|ConvertFrom-Json})
if($records.Count-ne40){throw 'Expected 40 records'}
foreach($item in $records){
 if((Get-FileHash -LiteralPath (Join-Path $batch ('responses/'+$item.task_id+'.txt'))).Hash-ne$item.response_sha256){throw 'Raw API file changed'}
 foreach($para in ($item.advice-split'\n\s*\n')){if(!$allText.Contains($para)){throw ('Missing API paragraph: '+$item.task_id)}}
}
if($allText-match'Priority:|resolve before use as a final stimulus|Human review notes'){throw 'Superseded instruction remains'}
if(!(Test-Path -LiteralPath (Join-Path $batch 'API_DISABLED.json'))){throw 'API disable marker missing'}
$audit=[ordered]@{modified_utc=[DateTime]::UtcNow.ToString('o');document=$path;note_replacements=$changes;advice_texts_verified_against_raw_api=40;advice_paragraph_xml_unchanged=$true;other_docx_parts_unchanged=$true;api_remains_disabled=$true;backup=$backup;docx_sha256=(Get-FileHash -LiteralPath $path).Hash;visual_qa=$false;visual_qa_limitation='LibreOffice and rendering dependencies unavailable; structure and exact output text verified.';scope='Document commentary only. Historical API responses, review logs, parameters and generation records are unchanged.'}
[IO.File]::WriteAllText((Join-Path $batch 'word_note_clarification.json'),($audit|ConvertTo-Json -Depth 8),$utf)
$checks=Get-Content -LiteralPath (Join-Path $batch 'checks_40.json') -Raw -Encoding UTF8|ConvertFrom-Json
$checks.docx_sha256=$audit.docx_sha256
$checks|Add-Member -NotePropertyName document_note_clarification -NotePropertyValue 'word_note_clarification.json' -Force
[IO.File]::WriteAllText((Join-Path $batch 'checks_40.json'),($checks|ConvertTo-Json -Depth 15),$utf)
$audit|ConvertTo-Json -Depth 8
