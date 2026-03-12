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

$readme = Get-Content -Raw -Path $ReadmePath
$newline = if ($readme -match "`r`n") { "`r`n" } else { "`n" }

$blockLines = New-Object System.Collections.Generic.List[string]
$blockLines.Add("<!--START_SECTION:recent_projects-->")
$blockLines.Add("<div align=""center"">")
$blockLines.Add("")
$blockLines.Add("<table>")

$cards = New-Object System.Collections.Generic.List[string]
foreach ($repo in $top) {
    $cardUrl = "https://github-readme-stats.vercel.app/api/pin/?username=$User&repo=$($repo.name)&theme=tokyonight&hide_border=true"
    $cards.Add("<a href=""$($repo.html_url)""><img src=""$cardUrl"" /></a>")
}

if ($cards.Count -eq 0) {
    $blockLines.Add("  <tr>")
    $blockLines.Add("    <td>No active public repositories found.</td>")
    $blockLines.Add("  </tr>")
} else {
    $cols = 2
    for ($i = 0; $i -lt $cards.Count; $i += $cols) {
        $blockLines.Add("  <tr>")
        for ($j = 0; $j -lt $cols; $j++) {
            $index = $i + $j
            if ($index -lt $cards.Count) {
                $blockLines.Add("    <td>$($cards[$index])</td>")
            } else {
                $blockLines.Add("    <td></td>")
            }
        }
        $blockLines.Add("  </tr>")
    }
}

$blockLines.Add("</table>")
$blockLines.Add("")
$blockLines.Add("</div>")
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
