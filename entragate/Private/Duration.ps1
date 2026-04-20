# ── Private/Duration.ps1 · ISO 8601 duration helpers ──

function ConvertTo-IsoDuration {
  <# .SYNOPSIS  Convert human-friendly duration to ISO 8601. Supports: 90, 90m, 0.5h, 0,5h, 1h, 2h30m, 1d, 01:30:00, PT1H30M #>
  param([Parameter(Mandatory)][string]$Value)
  $s = $Value.Trim().ToLower() -replace ',', '.'
  if ([string]::IsNullOrWhiteSpace($s)) { return 'PT1H' }
  if ($s -match '^pt') { return $s.ToUpper() }
  if ($s -match '^\d{1,2}:\d{2}(:\d{2})?$') {
    $ts = [TimeSpan]::Parse($s)
    if ($ts.Days -gt 0) { return "P$($ts.Days)D" }
    $parts = @()
    if ($ts.Hours   -gt 0) { $parts += "$($ts.Hours)H" }
    if ($ts.Minutes -gt 0) { $parts += "$($ts.Minutes)M" }
    if ($ts.Seconds -gt 0 -or $parts.Count -eq 0) { $parts += "$($ts.Seconds)S" }
    return "PT$($parts -join '')"
  }
  $d=0;$h=0;$m=0
  if ($s -match '(\d+)\s*d') { $d = [int]$Matches[1] }
  if ($s -match '(\d+\.\d+)\s*h') {
    $frac = [double]$Matches[1]
    $h    = [int][math]::Floor($frac)
    $m   += [int][math]::Round(($frac - $h) * 60)
  } elseif ($s -match '(\d+)\s*h') {
    $h = [int]$Matches[1]
  }
  if ($s -match '(\d+)\s*m') {
    $mMatch = [regex]::Match($s, '(\d+)\s*m')
    if ($mMatch.Success) { $m += [int]$mMatch.Groups[1].Value }
  }
  if ($d -eq 0 -and $h -eq 0 -and $m -eq 0 -and $s -match '^\d+$') { $m = [int]$s }
  if ($d -eq 0 -and $h -eq 0 -and $m -eq 0) {
    throw "Invalid duration '$Value'. Examples: 30m, 0.5h, 1h, 1h30m, 2h, 1d, 01:30:00"
  }
  if ($d -gt 0) { return "P${d}D" }
  if ($m -ge 60) { $h += [int][math]::Floor($m / 60); $m = $m % 60 }
  $parts = @()
  if ($h -gt 0) { $parts += "${h}H" }
  if ($m -gt 0) { $parts += "${m}M" }
  return "PT$($parts -join '')"
}

function Get-MinFromIso {
  <# .SYNOPSIS  Convert ISO duration to minutes (approximate). #>
  param([string]$Iso)
  if (-not $Iso) { return 0 }
  if ($Iso -match '^P(\d+)D$') { return [int]$Matches[1] * 24 * 60 }
  $h = 0; $m = 0
  if ($Iso -match 'PT(\d+)H')      { $h = [int]$Matches[1] }
  if ($Iso -match 'PT\d*H?(\d+)M') { $m = [int]$Matches[1] }
  return ($h * 60 + $m)
}
