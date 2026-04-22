# ── Public/Invoke-GatePim.ps1 · PIM Activation (Directory + Groups + Azure Resources) ──

# ── Module-private helpers ────────────────────────────────────────────────────

function Resolve-GateScopeName {
  param([string]$DirectoryScopeId)
  if ([string]::IsNullOrEmpty($DirectoryScopeId) -or $DirectoryScopeId -eq '/') {
    $name = Get-GateTenantName
    return if ($name) { "Tenant — $name" } else { 'Tenant' }
  }
  if ($DirectoryScopeId -match '/administrativeUnits/(?<id>[0-9a-fA-F-]+)') {
    return "AU: $($Matches.id)"
  }
  return $DirectoryScopeId
}

function Get-GateDirRoleMaxIso {
  param([string]$RoleDefinitionId)
  try {
    $assign = Get-MgPolicyRoleManagementPolicyAssignment `
                -Filter "scopeId eq '/' and scopeType eq 'DirectoryRole'" `
                -ExpandProperty "policy(`$expand=rules)" -All
    $durs = @()
    foreach ($a in $assign) {
      if ($a.RoleDefinitionId -and $a.RoleDefinitionId -ne $RoleDefinitionId) { continue }
      foreach ($r in $a.Policy.Rules) {
        if ($r.'@odata.type' -eq '#microsoft.graph.unifiedRoleManagementPolicyExpirationRule' -and
            $r.Target.Caller -eq 'EndUser' -and $r.Target.Level -eq 'Assignment' -and $r.MaximumDuration) {
          $durs += $r.MaximumDuration
        }
      }
    }
    if ($durs.Count -gt 0) { return ($durs | Sort-Object { Get-MinFromIso $_ } -Descending | Select-Object -First 1) }
  } catch {}
  return $null
}

function Get-GateGroupMaxIso {
  param([string]$GroupId, [ValidateSet('member','owner')][string]$AccessId)
  try {
    $assign = Get-MgPolicyRoleManagementPolicyAssignment `
                -Filter "scopeType eq 'Group'" `
                -ExpandProperty "policy(`$expand=rules)" -All
    $durs = @()
    foreach ($a in $assign) {
      if ($a.ScopeId -and $a.ScopeId -ne $GroupId) { continue }
      if ($a.RoleDefinitionId -and $a.RoleDefinitionId -ne $AccessId) { continue }
      foreach ($r in $a.Policy.Rules) {
        if ($r.'@odata.type' -eq '#microsoft.graph.unifiedRoleManagementPolicyExpirationRule' -and
            $r.Target.Caller -eq 'EndUser' -and $r.Target.Level -eq 'Assignment' -and $r.MaximumDuration) {
          $durs += $r.MaximumDuration
        }
      }
    }
    if ($durs.Count -gt 0) { return ($durs | Sort-Object { Get-MinFromIso $_ } -Descending | Select-Object -First 1) }
  } catch {}
  return $null
}

# ── Data fetchers ─────────────────────────────────────────────────────────────

function Get-GateDirEligibleRows {
  $meId = Get-GateUserId
  $defs = @{}
  Get-MgRoleManagementDirectoryRoleDefinition -All | ForEach-Object { $defs[$_.Id] = $_ }
  $eligible = Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance -Filter "principalId eq '$meId'" -All
  $active   = Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance  -Filter "principalId eq '$meId'" -All
  $activeSet = @{}
  foreach ($a in $active) { $activeSet["$($a.RoleDefinitionId)|$($a.DirectoryScopeId)"] = 1 }

  $rows = foreach ($e in $eligible) {
    $name = if ($defs[$e.RoleDefinitionId]) { $defs[$e.RoleDefinitionId].DisplayName } else { $e.RoleDefinitionId }
    [pscustomobject]@{
      Category               = 'Directory'
      Name                   = $name
      Scope                  = Resolve-GateScopeName $e.DirectoryScopeId
      ActiveNow              = $activeSet.ContainsKey("$($e.RoleDefinitionId)|$($e.DirectoryScopeId)")
      Dir_RoleDefinitionId   = $e.RoleDefinitionId
      Dir_ScopeId            = if ([string]::IsNullOrEmpty($e.DirectoryScopeId)) { '/' } else { $e.DirectoryScopeId }
      Dir_EligibilitySchedId = $e.RoleEligibilityScheduleId
      IsSeparator            = $false
    }
  }
  return @($rows | Sort-Object ActiveNow, Name)
}

function Get-GateDirActiveRows {
  $meId = Get-GateUserId
  $defs = @{}
  Get-MgRoleManagementDirectoryRoleDefinition -All | ForEach-Object { $defs[$_.Id] = $_ }
  $act = Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance -Filter "principalId eq '$meId'" -All

  $rows = foreach ($a in $act) {
    $name    = if ($defs[$a.RoleDefinitionId]) { $defs[$a.RoleDefinitionId].DisplayName } else { $a.RoleDefinitionId }
    $ends    = $a.EndDateTime
    $minLeft = if ($ends) { [math]::Round([math]::Max(0, ([datetimeoffset]$ends).UtcDateTime.Subtract([datetime]::UtcNow).TotalMinutes)) } else { $null }
    [pscustomobject]@{
      Category             = 'Directory'
      Name                 = $name
      Scope                = Resolve-GateScopeName $a.DirectoryScopeId
      Ends                 = $ends
      MinutesLeft          = $minLeft
      ActiveNow            = $true
      Dir_RoleDefinitionId = $a.RoleDefinitionId
      Dir_ScopeId          = if ([string]::IsNullOrEmpty($a.DirectoryScopeId)) { '/' } else { $a.DirectoryScopeId }
      IsSeparator          = $false
    }
  }
  return @($rows | Sort-Object MinutesLeft, Name)
}

function Get-GateGroupEligibleRows {
  $meId = Get-GateUserId
  $elig = Get-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleInstance -Filter "principalId eq '$meId'" -All
  $act  = Get-MgIdentityGovernancePrivilegedAccessGroupAssignmentScheduleInstance  -Filter "principalId eq '$meId'" -All

  $gmap = @{}
  foreach ($gid in ($elig | Select-Object -ExpandProperty GroupId -Unique)) {
    try { $gmap[$gid] = (Get-MgGroup -GroupId $gid).DisplayName } catch { $gmap[$gid] = $gid }
  }
  $actSet = @{}
  foreach ($a in $act) { $actSet["$($a.GroupId)|$($a.AccessId)"] = 1 }

  $rows = foreach ($e in $elig) {
    [pscustomobject]@{
      Category       = 'Groups'
      Name           = $gmap[$e.GroupId]
      Scope          = $e.AccessId
      ActiveNow      = $actSet.ContainsKey("$($e.GroupId)|$($e.AccessId)")
      Group_GroupId  = $e.GroupId
      Group_AccessId = $e.AccessId
      IsSeparator    = $false
    }
  }
  return @($rows | Sort-Object ActiveNow, Name, Scope)
}

function Get-GateGroupActiveRows {
  $meId = Get-GateUserId
  $list = Get-MgIdentityGovernancePrivilegedAccessGroupAssignmentScheduleInstance -Filter "principalId eq '$meId'" -All

  $gmap = @{}
  foreach ($gid in ($list | Select-Object -ExpandProperty GroupId -Unique)) {
    try { $gmap[$gid] = (Get-MgGroup -GroupId $gid).DisplayName } catch { $gmap[$gid] = $gid }
  }

  $rows = foreach ($a in $list) {
    $ends    = $a.EndDateTime
    $minLeft = if ($ends) { [math]::Round([math]::Max(0, ([datetimeoffset]$ends).UtcDateTime.Subtract([datetime]::UtcNow).TotalMinutes)) } else { $null }
    [pscustomobject]@{
      Category       = 'Groups'
      Name           = $gmap[$a.GroupId]
      Scope          = $a.AccessId
      Ends           = $ends
      MinutesLeft    = $minLeft
      ActiveNow      = $true
      Group_GroupId  = $a.GroupId
      Group_AccessId = $a.AccessId
      IsSeparator    = $false
    }
  }
  return @($rows | Sort-Object MinutesLeft, Name, Scope)
}

function Get-GateAzScopes {
  param([string[]]$AzureScopes)
  if ($AzureScopes -and $AzureScopes.Count -gt 0) { return $AzureScopes }
  try {
    return @(Get-AzSubscription -ErrorAction Stop | ForEach-Object { "/subscriptions/$($_.Id)" })
  } catch {
    Write-Warning "Could not enumerate subscriptions: $($_.Exception.Message)"
    return @()
  }
}

function Get-GateAzEligibleRows {
  param([string]$TenantId, [string[]]$AzureScopes)
  Connect-GateAzure -TenantId $TenantId
  $meId = Get-GateUserId
  $rows = @()
  foreach ($scope in (Get-GateAzScopes -AzureScopes $AzureScopes)) {
    try {
      $eligible = Get-AzRoleEligibilityScheduleInstance  -Scope $scope -Filter "asTarget()" -ErrorAction Stop
      $active   = Get-AzRoleAssignmentScheduleInstance   -Scope $scope -Filter "asTarget()" -ErrorAction SilentlyContinue
      $activeSet = @{}
      foreach ($a in $active) { $activeSet["$($a.RoleDefinitionId)|$($a.Scope)"] = 1 }
      foreach ($e in $eligible) {
        if ($e.PrincipalId -ne $meId) { continue }
        $rows += [pscustomobject]@{
          Category                           = 'AzureResources'
          Name                               = $e.RoleDefinitionDisplayName
          Scope                              = ($e.ScopeDisplayName ?? $e.Scope)
          ActiveNow                          = $activeSet.ContainsKey("$($e.RoleDefinitionId)|$($e.Scope)")
          Az_RoleDefinitionId                = $e.RoleDefinitionId
          Az_Scope                           = $e.Scope
          Az_LinkedRoleEligibilityScheduleId = $e.RoleEligibilityScheduleId
          IsSeparator                        = $false
        }
      }
    } catch { Write-Warning "Az eligibility fetch failed for $scope : $($_.Exception.Message)" }
  }
  return @($rows | Sort-Object ActiveNow, Name, Scope)
}

function Get-GateAzActiveRows {
  param([string]$TenantId, [string[]]$AzureScopes)
  Connect-GateAzure -TenantId $TenantId
  $meId = Get-GateUserId
  $rows = @()
  foreach ($scope in (Get-GateAzScopes -AzureScopes $AzureScopes)) {
    try {
      $act = Get-AzRoleAssignmentScheduleInstance -Scope $scope -Filter "asTarget()" -ErrorAction Stop
      foreach ($a in $act) {
        if ($a.PrincipalId -ne $meId) { continue }
        $ends    = $a.EndDateTime
        $minLeft = if ($ends) { [math]::Round([math]::Max(0, ([datetimeoffset]$ends).UtcDateTime.Subtract([datetime]::UtcNow).TotalMinutes)) } else { $null }
        $rows += [pscustomobject]@{
          Category                           = 'AzureResources'
          Name                               = $a.RoleDefinitionDisplayName
          Scope                              = ($a.ScopeDisplayName ?? $a.Scope)
          Ends                               = $ends
          MinutesLeft                        = $minLeft
          ActiveNow                          = $true
          Az_RoleDefinitionId                = $a.RoleDefinitionId
          Az_Scope                           = $a.Scope
          Az_LinkedRoleEligibilityScheduleId = $a.LinkedRoleEligibilityScheduleId
          IsSeparator                        = $false
        }
      }
    } catch { Write-Warning "Az active fetch failed for $scope : $($_.Exception.Message)" }
  }
  return @($rows | Sort-Object MinutesLeft, Name, Scope)
}

# ── Activate / Deactivate helpers ─────────────────────────────────────────────

function Invoke-GatePimActivateDir {
  param([pscustomobject]$Item, [string]$Iso, [string]$Justification, [string]$TicketSystem, [string]$TicketNumber)
  $max = Get-GateDirRoleMaxIso -RoleDefinitionId $Item.Dir_RoleDefinitionId
  if ($max -and (Get-MinFromIso $Iso) -gt (Get-MinFromIso $max)) {
    Write-Cyber "Requested $Iso exceeds policy max $max — Entra may cap it." 'WARN' 'Yellow'
  }
  $body = @{
    action           = 'selfActivate'
    principalId      = (Get-GateUserId)
    roleDefinitionId = $Item.Dir_RoleDefinitionId
    directoryScopeId = $Item.Dir_ScopeId
    justification    = $Justification
    scheduleInfo     = @{
      startDateTime = ([DateTime]::UtcNow.ToString('o'))
      expiration    = @{ type = 'AfterDuration'; duration = $Iso }
    }
  }
  if ($Item.Dir_EligibilitySchedId) { $body.activatedUsing = $Item.Dir_EligibilitySchedId }
  if ($TicketSystem -or $TicketNumber) {
    $body.ticketInfo = @{ ticketSystem = ($TicketSystem ?? 'N/A'); ticketNumber = $TicketNumber }
  }
  $req = New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest -BodyParameter $body -ErrorAction Stop
  Write-Cyber "Activated Directory: $($Item.Name) ($($Item.Scope))" 'OK' 'Green'
  [pscustomobject]@{ Category=$Item.Category; Role=$Item.Name; Scope=$Item.Scope; Status=($req.Status ?? 'Sent'); RequestId=$req.Id; Requested=$Iso }
}

function Invoke-GatePimDeactivateDir {
  param([pscustomobject]$Item, [string]$Justification)
  $body = @{
    action           = 'selfDeactivate'
    principalId      = (Get-GateUserId)
    roleDefinitionId = $Item.Dir_RoleDefinitionId
    directoryScopeId = $Item.Dir_ScopeId
    justification    = ($Justification ?? 'Deactivate via EntraGate')
  }
  $req = New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest -BodyParameter $body -ErrorAction Stop
  Write-Cyber "Deactivated Directory: $($Item.Name) ($($Item.Scope))" 'OK' 'Green'
  [pscustomobject]@{ Category=$Item.Category; Role=$Item.Name; Scope=$Item.Scope; Status=($req.Status ?? 'Sent'); RequestId=$req.Id }
}

function Invoke-GatePimActivateGroup {
  param([pscustomobject]$Item, [string]$Iso, [string]$Justification, [string]$TicketSystem, [string]$TicketNumber)
  $max = Get-GateGroupMaxIso -GroupId $Item.Group_GroupId -AccessId $Item.Group_AccessId
  if ($max -and (Get-MinFromIso $Iso) -gt (Get-MinFromIso $max)) {
    Write-Cyber "Requested $Iso exceeds policy max $max — Entra may cap it." 'WARN' 'Yellow'
  }
  $body = @{
    accessId      = $Item.Group_AccessId
    action        = 'selfActivate'
    principalId   = (Get-GateUserId)
    groupId       = $Item.Group_GroupId
    justification = $Justification
    scheduleInfo  = @{
      startDateTime = ([DateTime]::UtcNow.ToString('o'))
      expiration    = @{ type = 'afterDuration'; duration = $Iso }
    }
  }
  if ($TicketSystem -or $TicketNumber) {
    $body.ticketInfo = @{ ticketSystem = ($TicketSystem ?? 'N/A'); ticketNumber = $TicketNumber }
  }
  $req = New-MgIdentityGovernancePrivilegedAccessGroupAssignmentScheduleRequest -BodyParameter $body -ErrorAction Stop
  Write-Cyber "Activated Group: $($Item.Name) [$($Item.Scope)]" 'OK' 'Green'
  [pscustomobject]@{ Category=$Item.Category; Role=$Item.Name; Scope=$Item.Scope; Status=($req.Status ?? 'Sent'); RequestId=$req.Id; Requested=$Iso }
}

function Invoke-GatePimDeactivateGroup {
  param([pscustomobject]$Item, [string]$Justification)
  $body = @{
    accessId      = $Item.Group_AccessId
    action        = 'selfDeactivate'
    principalId   = (Get-GateUserId)
    groupId       = $Item.Group_GroupId
    justification = ($Justification ?? 'Deactivate via EntraGate')
  }
  $req = New-MgIdentityGovernancePrivilegedAccessGroupAssignmentScheduleRequest -BodyParameter $body -ErrorAction Stop
  Write-Cyber "Deactivated Group: $($Item.Name) [$($Item.Scope)]" 'OK' 'Green'
  [pscustomobject]@{ Category=$Item.Category; Role=$Item.Name; Scope=$Item.Scope; Status=($req.Status ?? 'Sent'); RequestId=$req.Id }
}

function Invoke-GatePimActivateAz {
  param([pscustomobject]$Item, [string]$Iso, [string]$Justification, [string]$TicketSystem, [string]$TicketNumber)
  $params = @{
    Name                      = [guid]::NewGuid().ToString()
    Scope                     = $Item.Az_Scope
    PrincipalId               = (Get-GateUserId)
    RoleDefinitionId          = $Item.Az_RoleDefinitionId
    RequestType               = 'SelfActivate'
    Justification             = $Justification
    ScheduleInfoStartDateTime = ([DateTime]::UtcNow.ToString('o'))
    ExpirationType            = 'AfterDuration'
    ExpirationDuration        = $Iso
  }
  if ($Item.Az_LinkedRoleEligibilityScheduleId) {
    $params.LinkedRoleEligibilityScheduleId = $Item.Az_LinkedRoleEligibilityScheduleId
  }
  if ($TicketSystem -or $TicketNumber) {
    $params.TicketSystem = ($TicketSystem ?? 'N/A')
    $params.TicketNumber = $TicketNumber
  }
  $req = New-AzRoleAssignmentScheduleRequest @params -ErrorAction Stop
  Write-Cyber "Activated AzureResources: $($Item.Name) ($($Item.Scope))" 'OK' 'Green'
  [pscustomobject]@{ Category=$Item.Category; Role=$Item.Name; Scope=$Item.Scope; Status=($req.Status ?? 'Sent'); RequestId=$req.Name; Requested=$Iso }
}

function Invoke-GatePimDeactivateAz {
  param([pscustomobject]$Item, [string]$Justification)
  $params = @{
    Name             = [guid]::NewGuid().ToString()
    Scope            = $Item.Az_Scope
    PrincipalId      = (Get-GateUserId)
    RoleDefinitionId = $Item.Az_RoleDefinitionId
    RequestType      = 'SelfDeactivate'
    Justification    = ($Justification ?? 'Deactivate via EntraGate')
  }
  if ($Item.Az_LinkedRoleEligibilityScheduleId) {
    $params.LinkedRoleEligibilityScheduleId = $Item.Az_LinkedRoleEligibilityScheduleId
  }
  $req = New-AzRoleAssignmentScheduleRequest @params -ErrorAction Stop
  Write-Cyber "Deactivated AzureResources: $($Item.Name) ($($Item.Scope))" 'OK' 'Green'
  [pscustomobject]@{ Category=$Item.Category; Role=$Item.Name; Scope=$Item.Scope; Status=($req.Status ?? 'Sent'); RequestId=$req.Name }
}

# ── Builders ──────────────────────────────────────────────────────────────────

function Build-GatePimEligible {
  param([bool]$IncDir, [bool]$IncGrp, [bool]$IncAz, [string]$TenantId, [string[]]$AzureScopes)
  $list = @()
  if ($IncDir) {
    $list += [pscustomobject]@{ Category=''; Name='Directory (Entra roles)'; Scope=''; ActiveNow=$false; IsSeparator=$true }
    $list += Get-GateDirEligibleRows
  }
  if ($IncGrp) {
    $list += [pscustomobject]@{ Category=''; Name='Groups (PIM for Groups)'; Scope=''; ActiveNow=$false; IsSeparator=$true }
    try { $list += Get-GateGroupEligibleRows } catch { Write-Warning "Group eligibility fetch failed: $($_.Exception.Message)" }
  }
  if ($IncAz) {
    $list += [pscustomobject]@{ Category=''; Name='Azure Resources'; Scope=''; ActiveNow=$false; IsSeparator=$true }
    try { $list += Get-GateAzEligibleRows -TenantId $TenantId -AzureScopes $AzureScopes } catch { Write-Warning "Azure eligibility fetch failed: $($_.Exception.Message)" }
  }
  return $list
}

function Build-GatePimActive {
  param([bool]$IncDir, [bool]$IncGrp, [bool]$IncAz, [string]$TenantId, [string[]]$AzureScopes)
  $list = @()
  if ($IncDir) {
    $list += [pscustomobject]@{ Category=''; Name='Directory (active)'; Scope=''; ActiveNow=$false; IsSeparator=$true }
    $list += Get-GateDirActiveRows
  }
  if ($IncGrp) {
    $list += [pscustomobject]@{ Category=''; Name='Groups (active)'; Scope=''; ActiveNow=$false; IsSeparator=$true }
    try { $list += Get-GateGroupActiveRows } catch { Write-Warning "Group active fetch failed: $($_.Exception.Message)" }
  }
  if ($IncAz) {
    $list += [pscustomobject]@{ Category=''; Name='Azure Resources (active)'; Scope=''; ActiveNow=$false; IsSeparator=$true }
    try { $list += Get-GateAzActiveRows -TenantId $TenantId -AzureScopes $AzureScopes } catch { Write-Warning "Azure active fetch failed: $($_.Exception.Message)" }
  }
  return $list
}

# ── Public function ───────────────────────────────────────────────────────────

function Invoke-GatePim {
  <#
  .SYNOPSIS
    Activate or deactivate PIM roles — Directory, Groups, and Azure Resources.
  .DESCRIPTION
    EntraGate-integrated PIM activation. Uses shared auth (Connect-GateGraph /
    Connect-GateAzure), shared UI (Select-GateItems / Write-Cyber), and shared
    duration parsing (ConvertTo-IsoDuration).
  .EXAMPLE
    Invoke-GatePim
    Invoke-GatePim -PimAction Deactivate
    Invoke-GatePim -PimAction ListActive
    Invoke-GatePim -PimAction Activate -Target Directory -Duration 2h -Justification "Change #1234"
  #>
  [CmdletBinding()]
  param(
    [ValidateSet('Activate','Deactivate','ListEligible','ListActive')]
    [string] $PimAction = 'Activate',

    [ValidateSet('Auto','Directory','Groups','AzureResources')]
    [string] $Target = 'Auto',

    [string]   $TenantId,
    [string]   $Duration,
    [string]   $Justification,
    [string]   $TicketSystem,
    [string]   $TicketNumber,
    [string[]] $Roles,
    [string[]] $AzureScopes
  )

  if (-not $script:GateSession.GraphConnected) {
    Connect-GateGraph -TenantId $TenantId
  }

  $IncDir = $true; $IncGrp = $true; $IncAz = $true
  switch ($Target) {
    'Directory'      { $IncGrp = $false; $IncAz = $false }
    'Groups'         { $IncDir = $false; $IncAz = $false }
    'AzureResources' { $IncDir = $false; $IncGrp = $false }
  }

  $transforms = @{
    Category  = { param($val) switch ($val) { 'Directory' {'◆ DIR'} 'Groups' {'◆ GRP'} 'AzureResources' {'◆ AZR'} default {$val} } }
    ActiveNow = { param($val) if ($val) { '● LIVE' } else { '·' } }
  }

  switch ($PimAction) {

    'ListEligible' {
      $rows = (Build-GatePimEligible -IncDir $IncDir -IncGrp $IncGrp -IncAz $IncAz -TenantId $TenantId -AzureScopes $AzureScopes) |
              Where-Object { -not $_.IsSeparator }
      if ($Roles) { $rows = $rows | Where-Object { $Roles -contains $_.Name } }
      if (-not $rows) { Write-Cyber "No eligible roles found." 'WARN' 'Yellow'; return }
      $rows | Select-Object Category, Name, Scope, ActiveNow | Format-Table -AutoSize
    }

    'ListActive' {
      $rows = (Build-GatePimActive -IncDir $IncDir -IncGrp $IncGrp -IncAz $IncAz -TenantId $TenantId -AzureScopes $AzureScopes) |
              Where-Object { -not $_.IsSeparator }
      if (-not $rows) { Write-Cyber "No active roles." 'WARN' 'Yellow'; return }
      $rows | Select-Object Category, Name, Scope, MinutesLeft, Ends | Format-Table -AutoSize
    }

    'Activate' {
      $combined     = Build-GatePimEligible -IncDir $IncDir -IncGrp $IncGrp -IncAz $IncAz -TenantId $TenantId -AzureScopes $AzureScopes
      $eligibleOnly = $combined | Where-Object { -not $_.IsSeparator }
      if ($Roles) {
        $combined     = $combined     | Where-Object { $_.IsSeparator -or ($Roles -contains $_.Name) }
        $eligibleOnly = $eligibleOnly | Where-Object { $Roles -contains $_.Name }
      }
      if (-not $eligibleOnly -or $eligibleOnly.Count -eq 0) {
        Write-Cyber "No eligible roles found." 'WARN' 'Yellow'; return
      }

      $picked = if ($Roles) {
        $eligibleOnly
      } else {
        Select-GateItems -Rows $combined -ShowCols 'Category','Name','Scope','ActiveNow' `
          -Title '╸ ENTRA::PIM ╺ select roles to ACTIVATE ╺╺╺ space=toggle  enter=confirm  esc=cancel' `
          -Multi -Transforms $transforms
      }
      if (-not $picked -or $picked.Count -eq 0) { Write-Cyber "Nothing selected." 'INFO' 'DarkGray'; return }

      $rawDur = if ($Duration) { $Duration } else { Read-Host "Duration (e.g. 30m, 1h, 2h30m)" }
      $iso    = ConvertTo-IsoDuration $rawDur

      if (-not $Justification) { $Justification = Read-Host "Justification" }
      if ([string]::IsNullOrWhiteSpace($Justification)) { throw "Justification cannot be empty." }

      if (-not $TicketSystem -and -not $TicketNumber) {
        if ((Read-Host "Requires ticket number? (y/N)") -match '^(y|j)') {
          $TicketSystem = Read-Host "Ticket system"
          $TicketNumber = Read-Host "Ticket number"
        }
      }

      $summary = @()
      foreach ($item in $picked) {
        if ($item.ActiveNow) {
          Write-Cyber "$($item.Name) ($($item.Scope)) already active — skipping." 'SKIP' 'Yellow'
          continue
        }
        try {
          $row = switch ($item.Category) {
            'Directory'      { Invoke-GatePimActivateDir   -Item $item -Iso $iso -Justification $Justification -TicketSystem $TicketSystem -TicketNumber $TicketNumber }
            'Groups'         { Invoke-GatePimActivateGroup -Item $item -Iso $iso -Justification $Justification -TicketSystem $TicketSystem -TicketNumber $TicketNumber }
            'AzureResources' { Invoke-GatePimActivateAz   -Item $item -Iso $iso -Justification $Justification -TicketSystem $TicketSystem -TicketNumber $TicketNumber }
          }
          if ($row) { $summary += $row }
        } catch {
          $summary += [pscustomobject]@{ Category=$item.Category; Role=$item.Name; Scope=$item.Scope; Status='Error'; RequestId=$null; Requested=$iso; Error=$_.Exception.Message }
          Write-Cyber "$($item.Category): $($item.Name) → $($_.Exception.Message)" 'ERR' 'Red'
        }
      }
      if ($summary.Count -gt 0) {
        Write-Host ""
        $summary | Format-Table Category, Role, Scope, Status, Requested, RequestId -AutoSize
      }
    }

    'Deactivate' {
      $combined   = Build-GatePimActive -IncDir $IncDir -IncGrp $IncGrp -IncAz $IncAz -TenantId $TenantId -AzureScopes $AzureScopes
      $activeOnly = $combined | Where-Object { -not $_.IsSeparator }
      if ($Roles) {
        $combined   = $combined   | Where-Object { $_.IsSeparator -or ($Roles -contains $_.Name) }
        $activeOnly = $activeOnly | Where-Object { $Roles -contains $_.Name }
      }
      if (-not $activeOnly -or $activeOnly.Count -eq 0) {
        Write-Cyber "No active roles to deactivate." 'WARN' 'Yellow'; return
      }

      $picked = Select-GateItems -Rows $combined -ShowCols 'Category','Name','Scope','MinutesLeft' `
        -Title '╸ ENTRA::PIM ╺ select roles to DEACTIVATE ╺╺╺ space=toggle  enter=confirm  esc=cancel' `
        -Multi -Transforms $transforms
      if (-not $picked -or $picked.Count -eq 0) { Write-Cyber "Nothing selected." 'INFO' 'DarkGray'; return }

      if (-not $Justification) { $Justification = Read-Host "Justification (optional, Enter to skip)" }

      $summary = @()
      foreach ($item in $picked) {
        try {
          $row = switch ($item.Category) {
            'Directory'      { Invoke-GatePimDeactivateDir   -Item $item -Justification $Justification }
            'Groups'         { Invoke-GatePimDeactivateGroup -Item $item -Justification $Justification }
            'AzureResources' { Invoke-GatePimDeactivateAz   -Item $item -Justification $Justification }
          }
          if ($row) { $summary += $row }
        } catch {
          $summary += [pscustomobject]@{ Category=$item.Category; Role=$item.Name; Scope=$item.Scope; Status='Error'; RequestId=$null; Error=$_.Exception.Message }
          Write-Cyber "$($item.Category): $($item.Name) → $($_.Exception.Message)" 'ERR' 'Red'
        }
      }
      if ($summary.Count -gt 0) {
        Write-Host ""
        $summary | Format-Table Category, Role, Scope, Status, RequestId -AutoSize
      }
    }
  }
}
