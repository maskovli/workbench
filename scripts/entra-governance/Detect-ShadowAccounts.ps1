#requires -Version 7.0
#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Detect potential “shadow” accounts and/or find users by specific phone/email.

.DESCRIPTION
  Collects per-user identifiers:
    - UPN, mail, otherMails, proxyAddresses
    - mobilePhone, businessPhones
    - identities (emailAddress / phoneNumber / UPN)
    - authentication methods: Email & Phone (MFA/SSPR)
  Outputs:
    - ShadowCandidates_*.csv : user pairs with collision reason, similarity & score
    - Duplicates_*.csv       : identifiers used by >1 user (email/phone)
    - Matches_*.csv          : results of -Phone/-PhonePartial/-Email lookups
    - UserInventory_*.csv    : (optional) per-user identifier inventory

.PARAMETER UserQuery
  Seed one or more names / UPNs / emails to pivot around (optional).

.PARAMETER SelectWithGrid
  Show a grid to pick among matched seed users.

.PARAMETER AllUsers
  Scan whole tenant (ignores UserQuery selection priority).

.PARAMETER Phone
  One or more exact phone numbers (accepts +NN…, 00NN…, or just digits).

.PARAMETER PhonePartial
  One or more digit sequences to search for inside normalized numbers (min 4 digits).

.PARAMETER Email
  One or more exact emails to match.

.PARAMETER NameSimilarityThreshold
  Add risk points when DisplayNames are similar (0..1). Default 0 (off).

.PARAMETER ExportInventory
  Also export per-user inventory CSV.

.PARAMETER TenantId
  Verified domain (e.g., spirhed.onmicrosoft.com) or tenant GUID.

.PARAMETER OutputDir
  Output directory (default: current dir).

.NOTES
  Requires Microsoft.Graph PS SDK:
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
  Scopes used: User.Read, Directory.Read.All, UserAuthenticationMethod.Read.All
#>

[CmdletBinding()]
param(
  [string[]]$UserQuery,
  [switch]  $SelectWithGrid,
  [switch]  $AllUsers,
  [string[]]$Phone,
  [string[]]$PhonePartial,
  [string[]]$Email,
  [ValidateRange(0.0,1.0)][double]$NameSimilarityThreshold = 0.0,
  [switch]  $ExportInventory,
  [string]  $TenantId,
  [ValidateNotNullOrEmpty()][string]$OutputDir = "."
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ---------------- Helpers ----------------
function Ensure-Module {
  param([Parameter(Mandatory)][string]$Name,[string]$MinVersion='0.0.1')
  if (-not (Get-Module -ListAvailable -Name $Name | Where-Object { $_.Version -ge [version]$MinVersion })) {
    Write-Host "Installing module $Name (CurrentUser)..." -ForegroundColor Yellow
    Install-Module $Name -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
  }
  Import-Module $Name -ErrorAction Stop | Out-Null
}
function Ensure-Grid {
  if (-not $SelectWithGrid) { return $false }
  try { Ensure-Module Microsoft.PowerShell.ConsoleGuiTools | Out-Null; return $true } catch { return $false }
}
function Resolve-OutputDir([string]$Path){
  try { return (Resolve-Path -Path $Path -ErrorAction Stop).Path }
  catch { New-Item -ItemType Directory -Path $Path -Force | Out-Null; return (Resolve-Path -Path $Path).Path }
}
function Normalize-Email([string]$e){ if([string]::IsNullOrWhiteSpace($e)){$null}else{$e.Trim().ToLower()} }
function Normalize-Phone([string]$p){
  if ([string]::IsNullOrWhiteSpace($p)){ return $null }
  $x = ($p -replace '[^\d\+]','')
  if ($x -match '^00(\d{6,})$'){ return "+$($matches[1])" }
  if ($x -match '^\d{8,}$'){ return "+$x" }
  if ($x -match '^\+\d{8,}$'){ return $x }
  return $null
}
function Digits([string]$p){ if ($p){ return ($p -replace '\D','') } else { '' } }

# Safe map adder: always keeps map[key] as an array of strings
function Add-ToMap {
  param(
    [Parameter(Mandatory)][hashtable]$Map,
    [Parameter(Mandatory)][string]$Key,
    [Parameter(Mandatory)][string]$Value
  )
  if (-not $Map.ContainsKey($Key)) { $Map[$Key] = @($Value); return }
  if ($Map[$Key] -isnot [System.Array]) { $Map[$Key] = @($Map[$Key]) }  # coerce any weird type
  $Map[$Key] = @($Map[$Key]) + @($Value)
}

# ---------------- Auth ----------------
$RequiredGraphScopes = @('User.Read','Directory.Read.All','UserAuthenticationMethod.Read.All')
function Ensure-GraphWithScopes {
  Ensure-Module Microsoft.Graph -MinVersion '2.15.0'
  Ensure-Module Microsoft.Graph.Authentication
  Ensure-Module Microsoft.Graph.Users

  $ctx = Get-MgContext -ErrorAction SilentlyContinue
  $needLogin = $true
  if ($ctx -and $ctx.Account){
    $missing = if ($ctx.Scopes) { $RequiredGraphScopes | Where-Object { $ctx.Scopes -notcontains $_ } } else { $RequiredGraphScopes }
    Write-Host "Existing Microsoft Graph session:" -ForegroundColor Cyan
    Write-Host ("  Account : {0}" -f $ctx.Account)
    Write-Host ("  Tenant  : {0}" -f $ctx.TenantId)
    if ($TenantId -and ($TenantId -ne $ctx.TenantId)){
      Write-Host ("Note: Requested tenant '{0}' differs from current session." -f $TenantId) -ForegroundColor Yellow
    }
    $ans = Read-Host "Use this session? [Y]es / [S]witch account"
    if ([string]::IsNullOrWhiteSpace($ans) -or $ans -match '^(y|yes)$'){
      if (-not $missing -or @($missing).Count -eq 0){
        try { Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me' -ErrorAction Stop | Out-Null; $needLogin=$false } catch { $needLogin=$true }
      }
    }
  }

  if ($needLogin){
    if (Get-Command Disconnect-MgGraph -ErrorAction SilentlyContinue){ Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null }
    if (Get-Command Clear-MgContext    -ErrorAction SilentlyContinue){ Clear-MgContext -Scope Process -Force -ErrorAction SilentlyContinue }

    $args = @{ Scopes=$RequiredGraphScopes; NoWelcome=$true }
    if ($TenantId){ $args.TenantId=$TenantId }

    Write-Host "Connecting to Microsoft Graph (Interactive)..." -ForegroundColor Yellow
    try {
      Connect-MgGraph @args | Out-Null
      Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me' -ErrorAction Stop | Out-Null
    } catch {
      Write-Warning ("Interactive failed: {0} -> Device Code..." -f $_.Exception.Message)
      Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
      Clear-MgContext -Scope Process -Force -ErrorAction SilentlyContinue
      $args.UseDeviceCode = $true
      Connect-MgGraph @args | Out-Null
      Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me' -ErrorAction Stop | Out-Null
    }

    if (Get-Command Select-MgProfile -ErrorAction SilentlyContinue) { Select-MgProfile -Name 'v1.0' }
  }
}

# ---------------- Discovery ----------------
function Find-Users {
  param([string[]]$Queries)
  $all = @()
  foreach($q in ($Queries ?? @())){
    $s = $q.Trim(); if (-not $s){ continue }
    foreach($st in @(
      ('"displayName:{0}"'       -f $s),
      ('"userPrincipalName:{0}"' -f $s),
      ('"mail:{0}"'              -f $s)
    )){
      try { $all += Get-MgUser -Search $st -ConsistencyLevel eventual -All -Property "id,displayName,userPrincipalName,mail" } catch {}
    }
    try { $all += Get-MgUser -Filter ("startsWith(displayName,'{0}')" -f $s.Replace("'","''")) -All -Property "id,displayName,userPrincipalName,mail" } catch {}
    try {
      if ($s -match '@' -or $s -match '^[0-9a-fA-F-]{36}$') {
        $u3 = Get-MgUser -UserId $s -Property "id,displayName,userPrincipalName,mail" -ErrorAction SilentlyContinue
        if ($u3){ $all += $u3 }
      }
    } catch {}
  }
  $all | Group-Object id | ForEach-Object { $_.Group | Select-Object -First 1 }
}
function Ensure-GridPick([array]$Users){
  $arr=@($Users)
  if ($arr.Count -le 1 -or -not (Ensure-Grid)){ return $arr }
  $proj = foreach($u in $arr){ [pscustomobject]@{DisplayName=$u.DisplayName;UPN=$u.UserPrincipalName;Mail=$u.Mail;__Ref=$u} }
  $sel = $proj | Out-ConsoleGridView -Title "Select seed user(s)" -OutputMode Multiple
  if (-not $sel){ return @() }
  @($sel | ForEach-Object { $_.__Ref })
}

function Get-AllUsers(){
  $props = "id,displayName,userPrincipalName,mail,otherMails,mobilePhone,businessPhones,identities,proxyAddresses,userType,createdDateTime"
  Get-MgUser -All -Property $props
}
function Get-AuthContactMethods([string]$userId){
  $emails=@(); $phones=@()
  try { $emails += Get-MgUserAuthenticationEmailMethod  -UserId $userId -All -ErrorAction Stop | ForEach-Object EmailAddress } catch {}
  try { $phones += Get-MgUserAuthenticationPhoneMethod  -UserId $userId -All -ErrorAction Stop | ForEach-Object PhoneNumber } catch {}
  [pscustomobject]@{ Emails=$emails; Phones=$phones }
}

# ---------------- Fuzzy ----------------
function JW-Similarity([string]$a,[string]$b){
  if ([string]::IsNullOrWhiteSpace($a) -or [string]::IsNullOrWhiteSpace($b)){ return 0.0 }
  $a=$a.ToLower(); $b=$b.ToLower(); if ($a -eq $b){ return 1.0 }
  $maxDist=[int]([Math]::Floor([Math]::Max($a.Length,$b.Length)/2))-1
  $matchA = New-Object bool[] $a.Length; $matchB = New-Object bool[] $b.Length
  $matches=0; $trans=0
  for($i=0;$i -lt $a.Length;$i++){
    $start=[Math]::Max(0,$i-$maxDist); $end=[Math]::Min($i+$maxDist+1,$b.Length)
    for($j=$start;$j -lt $end;$j++){
      if(-not $matchB[$j] -and $a[$i] -eq $b[$j]){ $matchA[$i]=$true; $matchB[$j]=$true; $matches++; break }
    }
  }
  if ($matches -eq 0){ return 0.0 }
  $k=0; for($i=0;$i -lt $a.Length;$i++){ if($matchA[$i]){ while(-not $matchB[$k]){$k++}; if($a[$i] -ne $b[$k]){$trans++}; $k++ } }
  $trans=[int]($trans/2)
  $m=[double]$matches
  $j = ($m/$a.Length + $m/$b.Length + ($m-$trans)/$m)/3.0
  $l=0; for($i=0;$i -lt [Math]::Min(4,[Math]::Min($a.Length,$b.Length));$i++){ if($a[$i] -eq $b[$i]){$l++} else {break}}
  return $j + 0.1*$l*(1-$j)
}
function Build-Score([bool]$sharedEmail,[bool]$sharedPhone,[double]$nameSim,[string]$typeA,[string]$typeB){
  $s=0; if ($sharedEmail){ $s+=70 }; if ($sharedPhone){ $s+=70 }
  if ($nameSim -ge [Math]::Max(0.8,$NameSimilarityThreshold)){ $s+=20 }
  if (($typeA -eq 'Guest' -and $typeB -eq 'Member') -or ($typeB -eq 'Guest' -and $typeA -eq 'Member')){ $s+=10 }
  if ($s -gt 100){ $s=100 }; return $s
}

# ---------------- MAIN ----------------
$sw = [System.Diagnostics.Stopwatch]::StartNew()
Ensure-GraphWithScopes
$outDir = Resolve-OutputDir $OutputDir

# seeds always initialised
$seeds = @()
if (-not $AllUsers -and $UserQuery){
  $hits = @(Find-Users -Queries $UserQuery)
  if (@($hits).Count -eq 0){ throw "No users matched your -UserQuery." }
  $seeds = @(Ensure-GridPick -Users $hits)
  if (@($seeds).Count -eq 0){ Write-Host "No selection. Exiting."; return }
  Write-Host ("Selected {0} seed user(s)." -f @($seeds).Count) -ForegroundColor Cyan
}

Write-Host "Reading users..." -ForegroundColor Yellow
$users = @(Get-AllUsers)

# search sets
$searchEmails = @(); foreach($e in @($Email)){ $n=Normalize-Email $e; if($n){ $searchEmails += $n } }
$searchPhones = @(); foreach($p in @($Phone)){ $n=Normalize-Phone $p; if($n){ $searchPhones += $n } }
$searchPhonePartials = @(); foreach($pp in @($PhonePartial)){ $d=Digits $pp; if($d.Length -ge 4){ $searchPhonePartials += $d } }

# inventories/maps
$invRows  = @()
$emailMap = @{}
$phoneMap = @{}
$byId     = @{}
$matches  = @()
$script:candRows = @()   # <— ensure script-scoped list

$idx=0
foreach($u in $users){
  $idx++
  Write-Progress -Activity "Collecting identifiers" -Status ("{0}/{1} {2}" -f $idx,$users.Count,$u.DisplayName) -PercentComplete ([int](100*$idx/$users.Count))

  $uEmails = @()
  $uPhones = @()

  foreach($v in @($u.UserPrincipalName,$u.Mail)){
    $n=Normalize-Email $v; if($n){ $uEmails += $n; Add-ToMap -Map $emailMap -Key $n -Value $u.Id }
  }
  foreach($v in @($u.OtherMails)){
    $n=Normalize-Email $v; if($n){ $uEmails += $n; Add-ToMap -Map $emailMap -Key $n -Value $u.Id }
  }
  foreach($v in @($u.ProxyAddresses)){
    $m = [regex]::Match($v, '^(?i)smtp:(.+)$')
    if ($m.Success) {
      $n = Normalize-Email $m.Groups[1].Value
      if($n){ $uEmails += $n; Add-ToMap -Map $emailMap -Key $n -Value $u.Id }
    }
  }

  foreach($v in @($u.MobilePhone)){
    $n=Normalize-Phone $v; if($n){ $uPhones += $n; Add-ToMap -Map $phoneMap -Key $n -Value $u.Id }
  }
  foreach($v in @($u.BusinessPhones)){
    foreach($z in @($v)){
      $n=Normalize-Phone $z; if($n){ $uPhones += $n; Add-ToMap -Map $phoneMap -Key $n -Value $u.Id }
    }
  }

  foreach($idn in @($u.Identities)){
    $iss=$idn.IssuerAssignedId
    switch ($idn.SignInType) {
      'emailAddress'       { $n=Normalize-Email $iss; if($n){ $uEmails += $n; Add-ToMap -Map $emailMap -Key $n -Value $u.Id } }
      'userPrincipalName'  { $n=Normalize-Email $iss; if($n){ $uEmails += $n; Add-ToMap -Map $emailMap -Key $n -Value $u.Id } }
      'phoneNumber'        { $n=Normalize-Phone $iss; if($n){ $uPhones += $n; Add-ToMap -Map $phoneMap -Key $n -Value $u.Id } }
      default { }
    }
  }

  $auth = Get-AuthContactMethods -UserId $u.Id
  foreach($v in $auth.Emails){
    $n=Normalize-Email $v; if($n){ $uEmails += $n; Add-ToMap -Map $emailMap -Key $n -Value $u.Id }
  }
  foreach($v in $auth.Phones){
    $n=Normalize-Phone $v; if($n){ $uPhones += $n; Add-ToMap -Map $phoneMap -Key $n -Value $u.Id }
  }

  $uEmails = @($uEmails | Select-Object -Unique)
  $uPhones = @($uPhones | Select-Object -Unique)

  if ($ExportInventory){
    $invRows += [pscustomobject]@{
      UserId=$u.Id; DisplayName=$u.DisplayName; UPN=$u.UserPrincipalName; Mail=$u.Mail; UserType=$u.UserType; CreatedDateTime=$u.CreatedDateTime
      Emails=($uEmails -join ';'); Phones=($uPhones -join ';')
    }
  }
  $byId[$u.Id] = [pscustomobject]@{ Id=$u.Id; DisplayName=$u.DisplayName; UPN=$u.UserPrincipalName; Type=$u.UserType }

  foreach($e in $uEmails){ if ($searchEmails -contains $e){
      $matches += [pscustomobject]@{ UserId=$u.Id; DisplayName=$u.DisplayName; UPN=$u.UserPrincipalName; Type='Email'; Value=$e; Source='User/Identity/Auth' }
  }}
  foreach($p in $uPhones){
    if ($searchPhones -contains $p){
      $matches += [pscustomobject]@{ UserId=$u.Id; DisplayName=$u.DisplayName; UPN=$u.UserPrincipalName; Type='Phone'; Value=$p; Source='User/Identity/Auth' }
    }
    foreach($pp in $searchPhonePartials){
      if ((Digits $p) -like "*$pp*"){
        $matches += [pscustomobject]@{ UserId=$u.Id; DisplayName=$u.DisplayName; UPN=$u.UserPrincipalName; Type='PhonePartial'; Value=$p; Source="Contains:$pp" }
      }
    }
  }
}

# shadow candidates
function Emit-Candidate([string]$a,[string]$b,[string]$reason,[string]$value,[double]$nameSim){
  if ($a -eq $b){ return }
  $ua=$byId[$a]; $ub=$byId[$b]
  $score = Build-Score ($reason -like 'Email*') ($reason -like 'Phone*') $nameSim $ua.Type $ub.Type
  $script:candRows += [pscustomobject]@{
    UserA_DisplayName=$ua.DisplayName; UserA_UPN=$ua.UPN; UserA_Id=$ua.Id; UserA_Type=$ua.Type
    UserB_DisplayName=$ub.DisplayName; UserB_UPN=$ub.UPN; UserB_Id=$ub.Id; UserB_Type=$ub.Type
    MatchReason=$reason; MatchValue=$value; NameSimilarity=[math]::Round($nameSim,3); RiskScore=$score
  }
}

# duplicates
$dupeRows = @()
foreach($e in $emailMap.Keys){
  $list=@($emailMap[$e] | Select-Object -Unique)
  if ($list.Count -gt 1){
    $dupeRows += [pscustomobject]@{ Type='Email'; Value=$e; Users=$list.Count }
    for($i=0;$i -lt $list.Count;$i++){ for($j=$i+1;$j -lt $list.Count;$j++){
      $nSim = if ($NameSimilarityThreshold -gt 0){ JW-Similarity $byId[$list[$i]].DisplayName $byId[$list[$j]].DisplayName } else { 0.0 }
      Emit-Candidate $list[$i] $list[$j] "EmailCollision" $e $nSim
    }}
  }
}
foreach($p in $phoneMap.Keys){
  $list=@($phoneMap[$p] | Select-Object -Unique)
  if ($list.Count -gt 1){
    $dupeRows += [pscustomobject]@{ Type='Phone'; Value=$p; Users=$list.Count }
    for($i=0;$i -lt $list.Count;$i++){ for($j=$i+1;$j -lt $list.Count;$j++){
      $nSim = if ($NameSimilarityThreshold -gt 0){ JW-Similarity $byId[$list[$i]].DisplayName $byId[$list[$j]].DisplayName } else { 0.0 }
      Emit-Candidate $list[$i] $list[$j] "PhoneCollision" $p $nSim
    }}
  }
}

# prioritise seeds
$seedIds = @($seeds | ForEach-Object { $_.Id })
if (-not $AllUsers -and @($seedIds).Count -gt 0){
  $script:candRows = @(
    $script:candRows | Where-Object { $seedIds -contains $_.UserA_Id -or $seedIds -contains $_.UserB_Id }
    $script:candRows | Where-Object { $seedIds -notcontains $_.UserA_Id -and $seedIds -notcontains $_.UserB_Id }
  )
  $matches = @(
    $matches | Where-Object { $seedIds -contains $_.UserId }
    $matches | Where-Object { $seedIds -notcontains $_.UserId }
  )
}

# ---------------- Export ----------------
$ts = (Get-Date).ToString("yyyyMMdd-HHmmss")
$base = Resolve-Path $outDir
$pathCand = Join-Path $base ("ShadowCandidates_{0}.csv" -f $ts)
$pathDup  = Join-Path $base ("Duplicates_{0}.csv" -f $ts)
$pathInv  = Join-Path $base ("UserInventory_{0}.csv" -f $ts)
$pathMat  = Join-Path $base ("Matches_{0}.csv" -f $ts)

$script:candRows | Sort-Object RiskScore -Descending | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $pathCand
$dupeRows        | Sort-Object Type,Value           | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $pathDup
if ($ExportInventory){ $invRows | Sort-Object DisplayName | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $pathInv }
$matches         | Sort-Object Type,Value,DisplayName | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $pathMat

$sw.Stop()
Write-Host ("Done in {0}s" -f [int]$sw.Elapsed.TotalSeconds) -ForegroundColor Green
Write-Host ("Shadow candidates : {0}" -f $pathCand)
Write-Host ("Duplicates        : {0}" -f $pathDup)
if ($ExportInventory){ Write-Host ("Inventory         : {0}" -f $pathInv) }
Write-Host ("Matches (lookup)  : {0}" -f $pathMat)
