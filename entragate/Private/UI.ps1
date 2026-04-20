# ── Private/UI.ps1 · Shared UI helpers for EntraGate ──

function Show-GateBanner {
  <# .SYNOPSIS  Display the EntraGate ASCII banner. #>
  $r = "`e[0m"; $c = "`e[38;5;51m"; $g = "`e[38;5;46m"; $d = "`e[38;5;240m"

  @(
    "${c}╔══════════════════════════════════════════════════════════════════╗${r}"
    "${c}║${r}                                                                  ${c}║${r}"
    "${c}║${r}   ${g} ██████╗  █████╗ ████████╗███████╗${r}                            ${c}║${r}"
    "${c}║${r}   ${g}██╔════╝ ██╔══██╗╚══██╔══╝██╔════╝${r}                            ${c}║${r}"
    "${c}║${r}   ${g}██║  ███╗███████║   ██║   █████╗  ${r}  ${d}//${r} ${c}EntraGate${r}             ${c}║${r}"
    "${c}║${r}   ${g}██║   ██║██╔══██║   ██║   ██╔══╝  ${r}  ${d}Governance & Access${r}    ${c}║${r}"
    "${c}║${r}   ${g}╚██████╔╝██║  ██║   ██║   ███████╗${r}  ${d}Terminal for Entra${r}     ${c}║${r}"
    "${c}║${r}   ${g} ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝${r}                            ${c}║${r}"
    "${c}║${r}                                                                  ${c}║${r}"
    "${c}╚══════════════════════════════════════════════════════════════════╝${r}"
  ) | ForEach-Object { Write-Host $_ }
}

function Show-GateSessionBar {
  <# .SYNOPSIS  Display account/tenant info bar. #>
  param([string]$Account, [string]$TenantName, [string]$TenantId)
  $c = "`e[38;5;51m"; $d = "`e[38;5;240m"; $r = "`e[0m"
  $tidShort = if ($TenantId.Length -gt 12) { "$($TenantId.Substring(0,8))..." } else { $TenantId }
  @(
    "${c}╠══════════════════════════════════════════════════════════════════╣${r}"
    "${c}║${r}  ${d}Account:${r}  $($Account.PadRight(52))  ${c}║${r}"
    "${c}║${r}  ${d}Tenant :${r}  $TenantName ${d}($tidShort)${r}$(' ' * [math]::Max(0, 42 - $TenantName.Length - $tidShort.Length))  ${c}║${r}"
    "${c}╚══════════════════════════════════════════════════════════════════╝${r}"
  ) | ForEach-Object { Write-Host $_ }
}

function Write-Cyber {
  <# .SYNOPSIS  Tagged console output: [OK], [ERR], [WARN], [AUTH], [INFO] #>
  param(
    [string]$Text,
    [ValidateSet('OK','ERR','WARN','AUTH','INFO','SKIP')]
    [string]$Tag = 'INFO',
    [string]$Color = 'Cyan'
  )
  $tagColor = switch ($Tag) {
    'OK'   { 'Green' }
    'ERR'  { 'Red' }
    'WARN' { 'Yellow' }
    'AUTH' { 'Magenta' }
    'SKIP' { 'DarkYellow' }
    default { 'DarkCyan' }
  }
  Write-Host "[" -NoNewline -ForegroundColor DarkGray
  Write-Host $Tag -NoNewline -ForegroundColor $tagColor
  Write-Host "] " -NoNewline -ForegroundColor DarkGray
  Write-Host $Text -ForegroundColor $Color
}

function Test-GateGridAvailable {
  <# .SYNOPSIS  Check if ConsoleGuiTools is available. #>
  if (Get-Command Out-ConsoleGridView -ErrorAction SilentlyContinue) { return $true }
  try {
    Import-Module Microsoft.PowerShell.ConsoleGuiTools -ErrorAction Stop | Out-Null
    return $true
  } catch { return $false }
}

function Select-GateItems {
  <#
  .SYNOPSIS  Unified item selector — ConsoleGridView with fallback to numbered list.
  .PARAMETER Rows        Array of objects to choose from.
  .PARAMETER ShowCols    Column names to display.
  .PARAMETER Title       Grid/menu title.
  .PARAMETER Multi       Allow multiple selection.
  .PARAMETER Transforms  Hashtable of { ColumnName = { param($val, $row) ... } } for display prettification.
  #>
  param(
    [array]    $Rows,
    [string[]] $ShowCols,
    [string]   $Title,
    [switch]   $Multi,
    [hashtable]$Transforms = @{}
  )
  if (-not $Rows -or $Rows.Count -eq 0) { return @() }

  $hasGrid = Test-GateGridAvailable

  if ($hasGrid) {
    $pairs = foreach ($r in $Rows) {
      $o = [ordered]@{}
      if ($r.IsSeparator) {
        $label = " $($r.Name) "
        $pad   = [math]::Max(0, 56 - $label.Length)
        foreach ($c in $ShowCols) {
          if ($c -eq $ShowCols[0]) { $o[$c] = "$([string]('━' * 4))$label$([string]('━' * $pad))" }
          else { $o[$c] = '' }
        }
      } else {
        foreach ($c in $ShowCols) {
          $val = $r.$c
          if ($Transforms.ContainsKey($c)) { $val = & $Transforms[$c] $val $r }
          $o[$c] = $val
        }
      }
      [pscustomobject]@{ Display = [pscustomobject]$o; Original = $r }
    }
    $displayList = $pairs | ForEach-Object { $_.Display }
    $mode = if ($Multi) { 'Multiple' } else { 'Single' }
    $sel = $displayList | Out-ConsoleGridView -Title $Title -OutputMode $mode
    if (-not $sel) { return @() }
    $picked = foreach ($s in $sel) {
      ($pairs | Where-Object { [object]::ReferenceEquals($_.Display, $s) } | Select-Object -First 1).Original
    }
    return @($picked | Where-Object { -not $_.IsSeparator })
  }

  # Fallback: numbered list
  Write-Host ""
  Write-Host $Title -ForegroundColor Cyan
  $i = 1
  foreach ($r in $Rows) {
    if ($r.IsSeparator) {
      Write-Host "  ━━━━ $($r.Name) ━━━━" -ForegroundColor DarkCyan
      continue
    }
    $vals = ($ShowCols | ForEach-Object {
      $val = $r.$_
      if ($Transforms.ContainsKey($_)) { $val = & $Transforms[$_] $val $r }
      $val
    }) -join '  │  '
    Write-Host ("  [{0,3}] {1}" -f $i, $vals)
    $r | Add-Member -NotePropertyName __Index -NotePropertyValue $i -Force
    $i++
  }
  $prompt = if ($Multi) { "Numbers (comma-separated, 'all'), Enter to cancel" } else { "Number, Enter to cancel" }
  $ans = Read-Host $prompt
  if ([string]::IsNullOrWhiteSpace($ans)) { return @() }
  if ($ans -ieq 'all') { return @($Rows | Where-Object { -not $_.IsSeparator }) }
  $idx = $ans -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
  return @($Rows | Where-Object { $idx -contains $_.__Index })
}
