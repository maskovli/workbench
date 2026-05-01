$UpdateSession = New-Object -ComObject Microsoft.Update.Session

$UpdateSearcher = $UpdateSession.CreateUpdateSearcher()

$SearchResult = $UpdateSearcher.Search("IsInstalled=0")

if ($SearchResult.Updates.Count -eq 0) {
    Write-Output "All updates are installed."
    exit 0
}
else {
    $UpdateCount = $SearchResult.Updates.Count
    Write-Output "There are $UpdateCount updates available."
    exit 1
}
