[CmdletBinding()]
param(
    [int]$Count = 3,
    [string]$ReadmePath = "README.md",
    [string]$User = $env:RECENT_PROJECTS_USER
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($env:RECENT_PROJECTS_COUNT) {
    $Count = [int]$env:RECENT_PROJECTS_COUNT
}

if (-not $User) {
    if ($env:GITHUB_REPOSITORY_OWNER) {
        $User = $env:GITHUB_REPOSITORY_OWNER
    } else {
        $User = "coff33ninja"
    }
}

$headers = @{
    "User-Agent" = "$User-readme-bot"
    "Accept" = "application/vnd.github+json"
}

if ($env:GITHUB_TOKEN) {
    $headers["Authorization"] = "Bearer $env:GITHUB_TOKEN"
}

$uri = "https://api.github.com/users/$User/repos?per_page=100&sort=pushed&direction=desc"
$repos = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get

$excludeName = ""
if ($env:GITHUB_REPOSITORY) {
    $excludeName = ($env:GITHUB_REPOSITORY -split "/")[1]
}

$filtered = $repos | Where-Object {
    -not $_.fork -and
    -not $_.archived -and
    -not $_.disabled -and
    ($excludeName -eq "" -or $_.name -ne $excludeName)
}

$top = $filtered | Select-Object -First $Count

$lines = New-Object System.Collections.Generic.List[string]
foreach ($repo in $top) {
    $desc = $repo.description
    if ([string]::IsNullOrWhiteSpace($desc)) {
        $desc = "No description yet."
    }
    $updated = [DateTime]::Parse($repo.pushed_at).ToString("yyyy-MM-dd")
    $lines.Add("- [$($repo.name)]($($repo.html_url)) - $desc (updated $updated)")
}

if ($lines.Count -eq 0) {
    $lines.Add("- No active public repositories found.")
}

$readme = Get-Content -Raw -Path $ReadmePath
$newline = if ($readme -match "`r`n") { "`r`n" } else { "`n" }

$blockLines = New-Object System.Collections.Generic.List[string]
$blockLines.Add("<!--START_SECTION:recent_projects-->")
$blockLines.AddRange($lines)
$blockLines.Add("<!--END_SECTION:recent_projects-->")
$blockText = $blockLines -join $newline

$pattern = "(?s)<!--START_SECTION:recent_projects-->.*?<!--END_SECTION:recent_projects-->"
if ($readme -match $pattern) {
    $readme = [regex]::Replace(
        $readme,
        $pattern,
        [System.Text.RegularExpressions.MatchEvaluator]{ $blockText }
    )
} else {
    $readme = $readme.TrimEnd() + $newline + $newline + "## Recently Active" + $newline + $newline + $blockText + $newline
}

Set-Content -Path $ReadmePath -Value $readme -Encoding utf8 -NoNewline
