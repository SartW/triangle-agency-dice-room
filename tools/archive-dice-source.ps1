param([switch]$Payload)
$ErrorActionPreference='Stop'
$taskRoot=[IO.Path]::GetFullPath($PSScriptRoot)
if((Split-Path $taskRoot -Leaf) -eq 'tools'){$taskRoot=Split-Path $taskRoot -Parent}
$projectRoot=Join-Path $taskRoot 'site\triangle-agency-dice-room'
$activeRoot=Join-Path $projectRoot 'cloudbase'
$archiveRoot=Join-Path $taskRoot 'archives'
$archivePath=Join-Path $archiveRoot 'triangle-agency-dice-room-2026-10-10.zip'
$entries=[Collections.Generic.List[object]]::new()
$activeFiles=Get-ChildItem -LiteralPath $activeRoot -File -Force
$activeFiles+=Get-ChildItem -LiteralPath (Join-Path $activeRoot 'src') -File -Recurse
$activeFiles+=Get-ChildItem -LiteralPath (Join-Path $activeRoot 'public') -File -Recurse
foreach($file in $activeFiles) {
  if($file.Name -like '*.tsbuildinfo' -or $file.Name -like '.env*'){continue}
  $relative=[IO.Path]::GetRelativePath($activeRoot,$file.FullName).Replace('\','/')
  $entries.Add([pscustomobject]@{path="cloudbase/$relative";source=$file.FullName})
}
$legacyFiles=& git -C $projectRoot ls-files
if($LASTEXITCODE -ne 0){throw 'Unable to enumerate original tracked source'}
foreach($relative in $legacyFiles) {
  if($relative.StartsWith('.openai/') -or $relative -like '.env*'){continue}
  $full=Join-Path $projectRoot $relative
  if(Test-Path -LiteralPath $full -PathType Leaf){$entries.Add([pscustomobject]@{path="legacy-sites/$relative";source=$full})}
}
$entries.Add([pscustomobject]@{path='README.md';source=(Join-Path $activeRoot 'README.md')})
$entries.Add([pscustomobject]@{path='tools/archive-dice-source.ps1';source=$PSCommandPath})
$manifest=@()
foreach($item in $entries) {
  $bytes=[IO.File]::ReadAllBytes($item.source)
  $sha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
  $manifest+="$sha  $($item.path)"
}
$manifestText=($manifest -join "`n")+"`n"
if(!(Test-Path -LiteralPath $archiveRoot)){New-Item -ItemType Directory -Path $archiveRoot | Out-Null}
if(Test-Path -LiteralPath $archivePath){throw 'Archive already exists; do not overwrite a verified backup'}
$zip=[IO.Compression.ZipFile]::Open($archivePath,[IO.Compression.ZipArchiveMode]::Create)
try {
  foreach($item in $entries) {
    [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$item.source,$item.path,[IO.Compression.CompressionLevel]::Optimal) | Out-Null
  }
  $entry=$zip.CreateEntry('MANIFEST.sha256')
  $writer=[IO.StreamWriter]::new($entry.Open(),[Text.UTF8Encoding]::new($false))
  try{$writer.Write($manifestText)}finally{$writer.Dispose()}
}finally{$zip.Dispose()}
# Reopen and verify every entry against original bytes before claiming success.
$zip=[IO.Compression.ZipFile]::OpenRead($archivePath)
try {
  foreach($item in $entries) {
    $entry=$zip.GetEntry($item.path)
    if(!$entry){throw "Missing archive entry: $($item.path)"}
    $stream=$entry.Open()
    try{$archived=[Security.Cryptography.SHA256]::HashData($stream)}finally{$stream.Dispose()}
    $original=[Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($item.source))
    if([Convert]::ToHexString($archived) -ne [Convert]::ToHexString($original)){throw "Hash mismatch: $($item.path)"}
  }
}finally{$zip.Dispose()}
if($Payload) {
  $tree=@()
  foreach($item in $entries){$tree+=[pscustomobject]@{path=$item.path;mode='100644';type='blob';content=[Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($item.source))}}
  $tree+=[pscustomobject]@{path='MANIFEST.sha256';mode='100644';type='blob';content=$manifestText}
  [pscustomobject]@{archivePath=$archivePath;archiveSha256=(Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash;files=$entries.Count;tree=$tree} | ConvertTo-Json -Depth 5 -Compress
} else {
  [pscustomobject]@{Archive=$archivePath;Files=$entries.Count;Bytes=(Get-Item -LiteralPath $archivePath).Length;SHA256=(Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash}
}
