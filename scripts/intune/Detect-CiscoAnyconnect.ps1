# Detect Cisco AnyConnect / Cisco Secure Client (OR logic)
# Intune: exit 0 = installed, exit 1 = not installed

$roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)})
$rel = @(
  'Cisco\Cisco AnyConnect Secure Mobility Client\vpnagent.exe',
  'Cisco\Cisco Secure Client\vpnagent.exe'
)

$paths = foreach ($r in $roots) { foreach ($p in $rel) { Join-Path -Path $r -ChildPath $p } }

$found = $paths | Where-Object { Test-Path $_ -PathType Leaf } | Select-Object -First 1

if ($found) {
  Write-Host "Detected: $found"
  exit 0
} else {
  Write-Host "Not detected (checked:`n$($paths -join [Environment]::NewLine))"
  exit 1
}