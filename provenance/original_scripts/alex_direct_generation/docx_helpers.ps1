$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root=(Get-Location).Path
function Convert-ToEnglish([string]$text){ return $text }
$out=Join-Path $root 'Word versions'
[void][IO.Directory]::CreateDirectory($out)
$utf=[Text.UTF8Encoding]::new($false)
$w='http://schemas.openxmlformats.org/wordprocessingml/2006/main'
$rns='http://schemas.openxmlformats.org/officeDocument/2006/relationships'
$scopeNames=@{core='Relationship-scam prevention and account protection';recovery='Post-scam harm limitation and recovery';support='Advice for friends, relatives and supporters';sextortion='Intimate images and blackmail';dating_safety='Dating-platform and meeting safety';investment='Relationship-based investment and cryptocurrency scams'}
$stageNames=@{prevention='Prevention';suspicion='Suspicion and verification';recovery='Harm limitation and recovery';support='Supporting others'}
$contextNames=@{romance_specific='Romance-scam-specific';dating_safety='Dating safety';adjacent_scam_or_recovery_mechanism='Related scam mechanisms or recovery support'}
$script:coverage=[Collections.Generic.List[object]]::new()
$script:checks=[Collections.Generic.List[object]]::new()
function Load($path){ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $root $path),[Text.Encoding]::UTF8))}
function Lines($path){@([IO.File]::ReadAllLines((Join-Path $root $path),[Text.Encoding]::UTF8) | Where-Object {$_} | ForEach-Object {ConvertFrom-Json -InputObject $_})}
function X([string]$s){[Security.SecurityElement]::Escape($s)}
function P([string]$s,[string]$style='Normal',[bool]$keep=$false){'<w:p><w:pPr><w:pStyle w:val="'+$style+'"/>'+$(if($keep){'<w:keepNext/>'})+'</w:pPr><w:r><w:t xml:space="preserve">'+(X $s)+'</w:t></w:r></w:p>'}
function New-Doc([string]$relative,[bool]$landscape=$false){
 $script:body=[Text.StringBuilder]::new();$script:links=[Collections.Generic.List[object]]::new()
 $script:docPath=Join-Path $out $relative;$script:land=$landscape
 $script:docRelative=$relative
 [void][IO.Directory]::CreateDirectory((Split-Path $script:docPath -Parent))
}
function Add-P([string]$s,[string]$style='Normal',[bool]$keep=$false){[void]$script:body.Append((P $s $style $keep))}
function Add-Break{[void]$script:body.Append('<w:p><w:r><w:br w:type="page"/></w:r></w:p>')}
function Add-Text([string]$text,[string]$style='Normal'){
 foreach($para in ($text -split '\r?\n\r?\n')){
  [void]$script:body.Append('<w:p><w:pPr><w:pStyle w:val="'+$style+'"/></w:pPr>')
  $lines=$para -split '\r?\n'
  for($i=0;$i -lt $lines.Count;$i++){if($i -gt 0){[void]$script:body.Append('<w:r><w:br/></w:r>')};[void]$script:body.Append('<w:r><w:t xml:space="preserve">'+(X $lines[$i])+'</w:t></w:r>')}
  [void]$script:body.Append('</w:p>')
 }
}
function Add-Link([string]$label,[string]$target,[string]$style='Normal'){
 $id='link'+($script:links.Count+1);$script:links.Add(@{id=$id;target=$target})
 [void]$script:body.Append('<w:p><w:pPr><w:pStyle w:val="'+$style+'"/></w:pPr><w:hyperlink r:id="'+$id+'"><w:r><w:rPr><w:color w:val="245580"/><w:u w:val="single"/></w:rPr><w:t xml:space="preserve">'+(X $label)+'</w:t></w:r></w:hyperlink></w:p>')
}
function Add-Table($headers,$records,$widths){
 $total=($widths | Measure-Object -Sum).Sum
 [void]$script:body.Append('<w:tbl><w:tblPr><w:tblW w:w="'+$total+'" w:type="dxa"/><w:tblInd w:w="120" w:type="dxa"/><w:tblLayout w:type="fixed"/><w:tblBorders>')
 foreach($edge in @('top','left','bottom','right','insideH','insideV')){[void]$script:body.Append('<w:'+$edge+' w:val="single" w:sz="4" w:color="B8B8B8"/>')}
 [void]$script:body.Append('</w:tblBorders><w:tblCellMar><w:top w:w="80" w:type="dxa"/><w:bottom w:w="80" w:type="dxa"/><w:left w:w="120" w:type="dxa"/><w:right w:w="120" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid>')
 foreach($width in $widths){[void]$script:body.Append('<w:gridCol w:w="'+$width+'"/>')}
 [void]$script:body.Append('</w:tblGrid>')
 $all=@(@{cells=$headers;header=$true})+@($records)
 foreach($row in $all){
  if($row.cells.Count -ne $widths.Count){throw 'Table column mismatch'}
  [void]$script:body.Append('<w:tr><w:trPr><w:cantSplit/>'+$(if($row.header){'<w:tblHeader/>'})+'</w:trPr>')
  for($i=0;$i -lt $widths.Count;$i++){
   [void]$script:body.Append('<w:tc><w:tcPr><w:tcW w:w="'+$widths[$i]+'" w:type="dxa"/><w:vAlign w:val="center"/>'+$(if($row.header){'<w:shd w:fill="E8EEF5"/>'})+'</w:tcPr>')
   foreach($text in @($row.cells[$i])){[void]$script:body.Append((P ([string]$text) $(if($row.header){'TableHeader'}else{'TableText'})))}
   [void]$script:body.Append('</w:tc>')
  }
  [void]$script:body.Append('</w:tr>')
 }
 [void]$script:body.Append('</w:tbl>')
 Add-P '' 'Spacer'
}
function Add-Sources($sources){
 Add-Break;Add-P 'Source directory' 'Heading1'
 Add-P 'IDs correspond to the corpus source and locator column. Links point to original public pages; L/P locators refer to retrieved text/PDF snapshots and may change with website updates. Access dates are not publication dates.'
 foreach($s in $sources){
  Add-P ($s.id+' | '+$s.org+' | '+$s.title) 'SourceHeading' $true
  Add-Link $s.url $s.url 'Small'
  Add-P ('Jurisdiction: '+$s.jurisdiction+'; Source type: '+$s.type+'; Accessed: '+$s.accessed_on+'; Context: '+$contextNames[$s.source_context]) 'Small'
 }
}
function Finish-Doc($sourceHtml=@()){
 $font='<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="Times New Roman" w:cs="Times New Roman"/>'
 $styles='<w:styles xmlns:w="'+$w+'"><w:docDefaults><w:rPrDefault><w:rPr>'+$font+'<w:sz w:val="22"/><w:lang w:val="en-US"/></w:rPr></w:rPrDefault></w:docDefaults>'
 # compact_reference_guide, with explicit font, table, monochrome and landscape overrides.
 $defs=@(@('Normal',22,0,120,300),@('Title',36,0,100,264),@('Subtitle',22,0,160,280),@('Heading1',32,360,200,300),@('Heading2',26,280,140,300),@('Heading3',24,200,100,300),@('TableText',20,0,60,264),@('TableHeader',20,0,60,264),@('Small',19,0,80,264),@('SourceHeading',22,120,60,264),@('Advice',22,0,120,280),@('Scenario',22,0,120,280),@('Footer',18,0,0,240),@('Spacer',4,0,0,240))
 foreach($def in $defs){
  $name=$def[0];$bold=if($name -in @('Title','TableHeader','Heading1','Heading2','Heading3','SourceHeading')){'<w:b/>'}else{''}
  $keep=if($name -in @('Title','Subtitle','Heading1','Heading2','Heading3','SourceHeading')){'<w:keepNext/><w:keepLines/>'}else{''}
  $styles+='<w:style w:type="paragraph" '+$(if($name -eq 'Normal'){'w:default="1" '})+'w:styleId="'+$name+'"><w:name w:val="'+$name+'"/><w:pPr>'+$keep+'<w:spacing w:before="'+$def[2]+'" w:after="'+$def[3]+'" w:line="'+$def[4]+'" w:lineRule="auto"/><w:widowControl/></w:pPr><w:rPr>'+$font+$bold+'<w:sz w:val="'+$def[1]+'"/><w:color w:val="000000"/></w:rPr></w:style>'
 }
 $styles+='</w:styles>'
 $size=if($script:land){'<w:pgSz w:w="15840" w:h="12240" w:orient="landscape"/>'}else{'<w:pgSz w:w="12240" w:h="15840"/>'}
 $doc='<w:document xmlns:w="'+$w+'" xmlns:r="'+$rns+'"><w:body>'+$script:body.ToString()+'<w:sectPr><w:footerReference w:type="default" r:id="footer"/>'+$size+'<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708"/></w:sectPr></w:body></w:document>'
 [xml]$englishDoc=$doc
 $englishNs=[Xml.XmlNamespaceManager]::new($englishDoc.NameTable);$englishNs.AddNamespace('w',$w)
 foreach($node in $englishDoc.SelectNodes('//w:t',$englishNs)){$node.InnerText=Convert-ToEnglish $node.InnerText}
 $doc=$englishDoc.OuterXml
 $rels='<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="styles" Type="'+$rns+'/styles" Target="styles.xml"/><Relationship Id="footer" Type="'+$rns+'/footer" Target="footer1.xml"/>'
 foreach($link in $script:links){$rels+='<Relationship Id="'+$link.id+'" Type="'+$rns+'/hyperlink" Target="'+(X $link.target)+'" TargetMode="External"/>'}
 $rels+='</Relationships>'
 $parts=@{}
 $parts['word/document.xml']=$doc;$parts['word/styles.xml']=$styles;$parts['word/_rels/document.xml.rels']=$rels
 $parts['word/footer1.xml']='<w:ftr xmlns:w="'+$w+'"><w:p><w:pPr><w:pStyle w:val="Footer"/><w:jc w:val="right"/></w:pPr><w:fldSimple w:instr="PAGE"><w:r><w:t>1</w:t></w:r></w:fldSimple></w:p></w:ftr>'
 $parts['[Content_Types].xml']='<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/></Types>'
 $parts['_rels/.rels']='<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="document" Type="'+$rns+'/officeDocument" Target="word/document.xml"/></Relationships>'
 $stream=[IO.File]::Open($script:docPath,[IO.FileMode]::Create);$zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create)
 try{foreach($key in $parts.Keys){[xml]$valid=$parts[$key];$entry=$zip.CreateEntry($key);$writer=[IO.StreamWriter]::new($entry.Open(),$utf);$writer.Write($parts[$key]);$writer.Dispose()}}finally{$zip.Dispose();$stream.Dispose()}
 [xml]$xml=$doc;$ns=[Xml.XmlNamespaceManager]::new($xml.NameTable);$ns.AddNamespace('w',$w)
 $alltext=($xml.SelectNodes('//w:t',$ns) | ForEach-Object {$_.InnerText}) -join "`n"
 if($alltext -match 'nvapi-[A-Za-z0-9_-]{20,}') {throw 'Credential found'}
 foreach($table in $xml.SelectNodes('//w:tbl',$ns)){
  $total=[int]$table.SelectSingleNode('./w:tblPr/w:tblW',$ns).GetAttribute('w',$w)
  $grid=@($table.SelectNodes('./w:tblGrid/w:gridCol',$ns) | ForEach-Object {[int]$_.GetAttribute('w',$w)})
  if(($grid | Measure-Object -Sum).Sum -ne $total){throw 'Table geometry mismatch'}
  foreach($tr in $table.SelectNodes('./w:tr',$ns)){$widths2=@($tr.SelectNodes('./w:tc/w:tcPr/w:tcW',$ns) | ForEach-Object {[int]$_.GetAttribute('w',$w)});if(($widths2 -join ',') -ne ($grid -join ',')){throw 'Cell geometry mismatch'}}
 }
 foreach($source in $sourceHtml){$script:coverage.Add(@{html=$source;docx=$script:docRelative})}
 $script:checks.Add(@{docx=$script:docRelative;xml_valid=$true;table_geometry=$true;hyperlinks=$script:links.Count;sha256=(Get-FileHash -LiteralPath $script:docPath -Algorithm SHA256).Hash})
 return $alltext
}
