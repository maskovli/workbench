//General Azure Resource Activations (Azure Resource Roles)
// Marius A. Skovli | Spirhed AS | https://spirhed.com
//03.10.2024
AuditLogs
| where Category == "ResourceManagement"  // Filter for Azure resource activations
| where OperationName in (
    "Add member to role completed (PIM activation)",
    "Add member to role requested (PIM activation)",
    "Remove member from role (PIM activation expired)"
)
| extend 
    User = tostring(parse_json(InitiatedBy.user).displayName),
    Role = tostring(parse_json(TargetResources[0]).displayName),
    RoleID = tostring(parse_json(TargetResources[0]).id),
    Justification = ResultDescription,
    ActivationTime = TimeGenerated
// Dynamically extract StartTime and ExpirationTime from AdditionalDetails
| mv-apply AD = parse_json(AdditionalDetails) on (
    where AD.key in ("StartTime", "EndTime", "ExpirationTime")
    | summarize DetailsMap = make_bag(pack(tostring(AD.key), tostring(AD.value)))
)
// Use the extracted values
| extend 
    StartTimeRaw = coalesce(DetailsMap.StartTime, DetailsMap.startTime),
    ExpirationTimeRaw = coalesce(DetailsMap.EndTime, DetailsMap.ExpirationTime, DetailsMap.endTime, DetailsMap.expirationTime)
// Convert to datetime
| extend
    StartTime = todatetime(StartTimeRaw),
    ExpirationTime = todatetime(ExpirationTimeRaw)
// Format dates and times
| extend
    FormattedStart = strcat("D: ", format_datetime(StartTime, 'dd.MM.yyyy'), " T: ", format_datetime(StartTime, 'HH.mm')),
    FormattedExpiration = strcat("D: ", format_datetime(ExpirationTime, 'dd.MM.yyyy'), " T: ", format_datetime(ExpirationTime, 'HH.mm'))
// Create ActivationRange and calculate RequestedHours
| extend
    ActivationRange = strcat(FormattedStart, " - ", FormattedExpiration),
    RequestedHours = datetime_diff('hour', ExpirationTime, StartTime)
// Project final columns
| project User, Role, RoleID, Justification, ActivationRange, RequestedHours, ActivationTime
| order by ActivationTime desc
