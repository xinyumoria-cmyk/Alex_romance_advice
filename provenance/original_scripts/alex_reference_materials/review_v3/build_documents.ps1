$ErrorActionPreference='Stop'
$root=(Get-Location).Path
. ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $root 'alex_direct_generation/docx_helpers.ps1'),[Text.Encoding]::UTF8)))
$dir=Join-Path $root 'alex_reference_materials/review_v3';$out=Join-Path $dir 'staged_docs';[IO.Directory]::CreateDirectory($out)|Out-Null
$entries=Lines 'alex_reference_materials/review_v3/advice_screening_288.jsonl'
$pack=@($entries|Where-Object{$_.screening.in_prompt_pack});$reserve=@($entries|Where-Object{$_.screening.eligible-and!$_.screening.in_prompt_pack})
$summary=Load 'alex_reference_materials/review_v3/summary.json';$sources=Load 'romance_scam_corpus/sources.json'
function Source-Directory($ids,[bool]$newPage=$true){if($newPage){Add-Break};Add-P 'Source directory' 'Heading1';Add-P 'Source metadata and locators are retained from the original collection. Entries are AI-normalized, source-grounded English paraphrases, not verbatim quotations. This selection revision did not re-fetch the source pages.';foreach($s in @($sources|Where-Object{$_.id-in$ids})){Add-P ($s.id+' | '+$s.org+' | '+$s.title) 'SourceHeading' $true;Add-Link $s.url $s.url 'Small';Add-P ('Jurisdiction: '+$s.jurisdiction+' | Originally accessed: '+$s.accessed_on) 'Small'}}
function Class-Text($e){switch($e.screening.rule){'D'{'Direct in all eight versions'};'C'{'Conditional in all eight versions'};'MONEY'{'Direct when money is requested; conditional otherwise'};'EMOTION'{'Direct for high expressed emotion; conditional otherwise'};'N'{'Outside the current Alex scope'}}}
function Section-End($landscape){$size=if($landscape){'<w:pgSz w:w="15840" w:h="12240" w:orient="landscape"/>'}else{'<w:pgSz w:w="12240" w:h="15840"/>'};[void]$script:body.Append('<w:p><w:pPr><w:pStyle w:val="Spacer"/><w:sectPr><w:footerReference w:type="default" r:id="footer"/><w:type w:val="nextPage"/>'+$size+'<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708"/></w:sectPr></w:pPr></w:p>')}
New-Doc '02 - Alex Reference Selection - Revised.docx'
Add-P 'Alex Reference Selection' 'Title'
Add-P 'Functional selection review | 30 September 2026 | Version 3.0' 'Subtitle'
Add-P '288 corpus entries retained; 120 remain eligible for Alex and 168 remain outside scope. The reviewed common reference pack contains 60 entries; 60 eligible entries remain in reserve. The previous eligibility classifications are carried forward; all 120 eligible entries received a new item-level selection comparison.'
Add-P 'Why the selection changed' 'Heading1'
Add-P 'The v2 audit found that selection reasons largely repeated eligibility reasons. This revision records each entry''s concrete function, comparison IDs and separate inclusion or reserve rationale. A category being represented is not treated as proof that all functions within it are covered.'
Add-P 'Ten entries were added: ADV0071, ADV0079, ADV0111, ADV0121, ADV0140, ADV0155, ADV0157, ADV0158, ADV0182 and ADV0269. They add verification safeguards, explicit credential/private-information boundaries, meeting communication and exit precautions, or a distinct digital-access boundary.'
Add-P 'Three entries moved to reserve: ADV0059, ADV0162 and ADV0200. All eleven supporter/adviser delivery principles now follow the same role rule. They remain eligible for explicit adaptation in other work; none is supplied as a recipient reference in this pack. Supportive tone remains part of the common writing instructions.'
Add-P 'Selection rules and stopping point' 'Heading1'
foreach($p in $summary.selection_rules.PSObject.Properties){Add-P ($p.Name+' - '+$p.Value) 'Small'}
Add-P 'All 120 eligible entries were reviewed. The pack retains entries assigned S1-S3 and reserves R1-R4, including necessary companions to selected checks. No fixed quota, numerical score, input-token ceiling or empirically optimal count was imposed. The 120-180-word limit applies to generated advice, not reference input. These remain qualitative judgments; an independent reviewer may reasonably change individual decisions.'
Add-P 'Timing, controls and interpretation' 'Heading1'
Add-P 'This is an AI-assisted methodological revision performed after the v2 pilot batch and before the v3 batch. No Survey 2 participant ratings were consulted in this revision. It is not retrospectively preregistered and does not constitute independent researcher adjudication. Researchers should confirm functional coverage and boundary decisions before formal use.'
Add-P 'The same ordered 60-entry reference block and applicability guards are supplied to all eight original teacher scenarios. Only the original scenario and its factor metadata vary. High urgency concerns conversation tonight, not an immediate payment deadline; expressed attachment belongs to Alex, not necessarily the recipient. No scenario establishes fraud, a prior payment or an account compromise.'
Add-P 'The 08 response document must use the v3 batch generated from these frozen inputs. Earlier v1 and v2 outputs and human annotations remain historical; a previous wording approval does not validate newly generated text. This is reference-supported prompting, not parameter fine-tuning. The main human comparison involves unaided ordinary adults, so differences cannot be attributed solely to intrinsic AI versus human ability.'
Add-P 'Document 07 provides the complete 288-entry audit, including all 60 reserves and their distinct reasons. The original paraphrases and source provenance have not been rewritten. The 168 original outside-scope decisions were not re-adjudicated in this selection-only revision.'
Section-End $false
Add-P 'Selected reference entries' 'Heading1'
$rows=@(foreach($e in $pack){@{cells=@(@($e.advice_id,$e.screening.domain,$e.screening.decision_rule),@($e.advice_en,('Function: '+$e.screening.function)),@((Class-Text $e),('Comparison: '+($e.screening.comparison_ids-join', ')),('Decision: '+$e.screening.prompt_selection_reason),('Use guard: '+$e.screening.use_guard)),@(($e.source_ids-join', '),(($e.provenance|ForEach-Object{$_.source_id+': '+$_.locator})-join'; ')))}})
Add-Table @('ID / domain / rule','Original advice and concrete function','Applicability, comparative rationale and guard','Sources / locators') $rows @(1100,3300,5860,2700)
Section-End $true
Source-Directory @($pack.source_ids|Sort-Object -Unique) $false
$text=Finish-Doc;foreach($e in $pack){if(!$text.Contains($e.advice_en)-or!$text.Contains($e.screening.prompt_selection_reason)){throw 'Selected document missing source text or rationale'}}

New-Doc '07 - Alex Corpus Screening - 288 Decisions.docx' $true
Add-P 'Alex Corpus Screening: 288 Decisions' 'Title'
Add-P 'Eligibility and functional selection | 30 September 2026 | Version 3.0' 'Subtitle'
Add-P 'Original corpus: 288. Eligibility carried forward from v2: 120 eligible (32 direct in at least one scenario; 88 conditional-only), 168 outside scope. New functional selection: 60 selected and 60 reserve. The corpus texts and sources are unchanged.'
Add-P 'For all 120 eligible entries the final column records a concrete function, comparison IDs, decision code and comparative reason. Related entries are not necessarily duplicates; a reserve function is not claimed fully covered unless the reason identifies it as an implementation or alternative. The 168 outside-scope entries retain their earlier eligibility decisions and were not re-adjudicated here.'
foreach($p in $summary.selection_rules.PSObject.Properties){Add-P ($p.Name+' - '+$p.Value) 'Small'}
Add-P 'S01-S08 retain the teacher''s eight original scenarios. Financial requests occur in S03/S04/S07/S08; high expressed emotion in S02/S04/S06/S08; high conversational urgency in S05-S08. All eight prompts receive the identical selected pack. The 288 x 8 applicability matrix remains available in the machine-readable records.'
Add-P 'AI-assisted revision, not independent human sign-off. This review occurred after v2 generation; it is not a claim of advance preregistration or optimal selection. Study participants must not see these internal reference IDs or screening codes.'
$rows=@(foreach($e in $entries){$s=$e.screening;$status=if($s.in_prompt_pack){'SELECTED'}elseif($s.eligible){'ELIGIBLE RESERVE'}else{'OUTSIDE SCOPE - carried forward'};$detail=if($s.eligible){@(($status+' | '+$s.decision_rule),('Function: '+$s.function),('Comparison: '+($s.comparison_ids-join', ')),('Decision: '+$s.prompt_selection_reason),('Guard: '+$s.use_guard))}else{@($status,$s.prompt_selection_reason)};@{cells=@(@($e.advice_id,('Sources: '+($e.source_ids-join', '))),$e.advice_en,@((Class-Text $e),$s.eligibility_reason),$detail)}})
Add-Table @('ID / sources','Original corpus advice','Eligibility retained from v2','Current functional selection decision') $rows @(1100,3000,3000,5860)
Source-Directory @($sources.id)
$text=Finish-Doc;foreach($e in $entries){if(!$text.Contains($e.advice_en)){throw 'Full audit missing original corpus text'}}
foreach($e in @($entries|Where-Object{$_.screening.eligible})){if(!$text.Contains($e.screening.prompt_selection_reason)){throw 'Missing comparative rationale'}}
[IO.File]::WriteAllText((Join-Path $dir 'document_checks.json'),(ConvertTo-Json -InputObject @{documents=$script:checks;selected_rows=60;all_eligible_decisions=120;full_audit_rows=288;original_advice_and_provenance_preserved=$true;selected_document_has_landscape_table_section=$true;font='Times New Roman';visual_render_verified=$false;visual_limitation='LibreOffice is not installed; structural XML and table geometry checked'} -Depth 12),$utf)
'Staged English Times New Roman documents 02 and 07; all 120 comparative reasons and 288 original texts verified.'
