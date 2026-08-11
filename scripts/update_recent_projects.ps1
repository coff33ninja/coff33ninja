[CmdletBinding()]
param(
    [int]$Count = 10,
    [string]$ReadmePath = "README.md",
    [string]$User = $env:RECENT_PROJECTS_USER
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($env:RECENT_PROJECTS_COUNT) { $Count = [int]$env:RECENT_PROJECTS_COUNT }
if (-not $User) { $User = if ($env:GITHUB_REPOSITORY_OWNER) { $env:GITHUB_REPOSITORY_OWNER } else { "coff33ninja" } }

$headers = @{
    "User-Agent"           = "$User-readme-bot"
    "Accept"               = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
}
if ($env:GITHUB_TOKEN) { $headers["Authorization"] = "Bearer $env:GITHUB_TOKEN" }

$uri = "https://api.github.com/users/$User/repos?per_page=100&sort=pushed&direction=desc"
try {
    $repos = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
}
catch {
    Write-Host "Failed to fetch repositories. Leaving README unchanged."
    exit 0
}

$excludeName = ""
if ($env:GITHUB_REPOSITORY) { $excludeName = ($env:GITHUB_REPOSITORY -split "/")[1] }

$filtered = $repos | Where-Object {
    -not $_.fork -and -not $_.archived -and -not $_.disabled -and
    ($excludeName -eq "" -or $_.name -ne $excludeName)
}

$top = $filtered | Select-Object -First $Count
$readme = Get-Content -Raw -Path $ReadmePath

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("<!--START_SECTION:recent_projects-->")
$lines.Add('<table role="table">')
$lines.Add('<tbody>')

$cards = New-Object System.Collections.Generic.List[object]
foreach ($repo in $top) {
    $desc = $repo.description
    if ([string]::IsNullOrWhiteSpace($desc)) { $desc = "—" }
    $desc = $desc.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
    $lang = $repo.language
    if ([string]::IsNullOrWhiteSpace($lang)) {
        try {
            $langs = Invoke-RestMethod -Uri "https://api.github.com/repos/$User/$($repo.name)/languages" -Headers $headers -Method Get
            if ($langs.PSObject.Properties.Count -gt 0) {
                $lang = ($langs.PSObject.Properties | Sort-Object Value -Descending | Select-Object -First 1).Name
            }
        }
        catch { }
    }
    if ([string]::IsNullOrWhiteSpace($lang)) { $lang = "—" }
    $updated = [DateTimeOffset]::Parse($repo.pushed_at).ToString("yyyy-MM-dd", [CultureInfo]::InvariantCulture)
    $repoName = $repo.name
    $repoUrl = $repo.html_url

    $cardLines = New-Object System.Collections.Generic.List[string]
    $cardLines.Add('<td align="center" width="300">')
    $cardLines.Add('<a href="' + $repoUrl + '">')
    $cardLines.Add('<b>' + $repoName + '</b>')
    $cardLines.Add('</a>')
    $cardLines.Add('<br>')
    $cardLines.Add('<sub>' + $desc + '</sub>')
    $cardLines.Add('<br>')
    $cardLines.Add('<sub><code>' + $lang + '</code> · ' + $updated + '</sub>')
    $cardLines.Add('</td>')

    $cards.Add(($cardLines -join "`n"))
}

for ($i = 0; $i -lt $cards.Count; $i += 2) {
    $lines.Add('<tr>')
    $lines.Add($cards[$i])
    if ($i + 1 -lt $cards.Count) { $lines.Add($cards[$i + 1]) }
    $lines.Add('</tr>')
}

$lines.Add('</tbody>')
$lines.Add('</table>')
$lines.Add("<!--END_SECTION:recent_projects-->")

$blockText = $lines -join "`r`n"
$pattern = "(?s)<!--START_SECTION:recent_projects-->.*?<!--END_SECTION:recent_projects-->"

if ($readme -match $pattern) {
    $readme = [regex]::Replace($readme, $pattern, [System.Text.RegularExpressions.MatchEvaluator] { $blockText })
}
else {
    $readme = $readme.TrimEnd() + "`r`n`r`n## Last 10 Repos`r`n`r`n" + $blockText + "`r`n"
}

Set-Content -Path $ReadmePath -Value $readme -Encoding utf8 -NoNewline
Write-Host "README updated with $($top.Count) recent projects."
