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
$lines.Add("")
$lines.Add('<div align="center">')
$lines.Add('<div style="display:flex; flex-wrap:wrap; justify-content:center; gap:18px; margin-top:1rem; margin-bottom:1rem;">')

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

    $lines.Add('<a href="' + $repoUrl + '" style="text-decoration:none; color:inherit;">')
    $lines.Add('  <div style="border:1px solid #30363d; border-radius:16px; padding:18px; width:280px; min-height:150px; background-color:#0d1117; color:#c9d1d9;">')
    $lines.Add('    <h3 style="margin:0 0 10px 0; font-size:1rem;">' + $repoName + '</h3>')
    $lines.Add('    <p style="margin:0 0 12px 0; font-size:0.94rem; line-height:1.4; color:#8b949e;">' + $desc + '</p>')
    $lines.Add('    <div style="display:flex; justify-content:space-between; gap:8px; font-size:0.84rem; color:#8b949e;"><span>' + $lang + '</span><span>' + $updated + '</span></div>')
    $lines.Add('  </div>')
    $lines.Add('</a>')
}

$lines.Add('</div>')
$lines.Add('</div>')
$lines.Add("")
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
