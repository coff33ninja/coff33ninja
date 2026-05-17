[CmdletBinding()]
param(
    [string]$ReadmePath = "README.md",
    [string]$User = $env:RECENT_PROJECTS_USER,
    [int]$Count = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($env:RECENT_PROJECTS_COUNT) { $Count = [int]$env:RECENT_PROJECTS_COUNT }
if (-not $User) { $User = if ($env:GITHUB_REPOSITORY_OWNER) { $env:GITHUB_REPOSITORY_OWNER } else { "coff33ninja" } }

$headers = @{
    "User-Agent" = "$User-readme-bot"
    "Accept" = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
}
if ($env:GITHUB_TOKEN) { $headers["Authorization"] = "Bearer $env:GITHUB_TOKEN" }

$uri = "https://api.github.com/users/$User/events?per_page=100"
try {
    $events = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
} catch {
    Write-Host "Failed to fetch events. Leaving README unchanged."
    exit 0
}

$filtered = $events | Where-Object {
    $_.type -in @("PushEvent", "CreateEvent", "ReleaseEvent")
}

$top = $filtered | Select-Object -First $Count
$readme = Get-Content -Raw -Path $ReadmePath

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("<!--START_SECTION:activity-->")

if ($top.Count -eq 0) {
    $lines.Add("No recent activity.")
} else {
    $i = 1
    foreach ($event in $top) {
        switch ($event.type) {
            "PushEvent" {
                $repo = $event.repo.name
                $url = "https://github.com/$repo"
                $lines.Add("$i. 🚀 Pushed to [$repo]($url)")
            }
            "CreateEvent" {
                $repo = $event.repo.name
                $url = "https://github.com/$repo"
                if ($event.payload.ref_type -eq "repository") {
                    $lines.Add("$i. 🆕 Created [$repo]($url)")
                } elseif ($event.payload.ref_type -eq "branch") {
                    $branch = $event.payload.ref
                    $lines.Add("$i. 🌱 Created branch [$branch]($url/tree/$branch) in [$repo]($url)")
                } elseif ($event.payload.ref_type -eq "tag") {
                    $tag = $event.payload.ref
                    $lines.Add("$i. 🏷️ Created tag [$tag]($url/releases/tag/$tag) in [$repo]($url)")
                } else {
                    $lines.Add("$i. 🆕 Created $($event.payload.ref_type) in [$repo]($url)")
                }
            }
            "ReleaseEvent" {
                $repo = $event.repo.name
                $url = "https://github.com/$repo"
                $release = $event.payload.release
                $tag = $release.tag_name
                $releaseUrl = $release.html_url
                $lines.Add("$i. 🏷️ Published release [$tag]($releaseUrl) in [$repo]($url)")
            }
        }
        $i++
    }
}

$lines.Add("")
$lines.Add("<!--END_SECTION:activity-->")

$blockText = $lines -join "`r`n"
$pattern = "(?s)<!--START_SECTION:activity-->.*?<!--END_SECTION:activity-->"

if ($readme -match $pattern) {
    $readme = [regex]::Replace($readme, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ $blockText })
} else {
    $readme = $readme.TrimEnd() + "`r`n`r`n## Recent Activity`r`n`r`n" + $blockText + "`r`n"
}

Set-Content -Path $ReadmePath -Value $readme -Encoding utf8 -NoNewline
Write-Host "README updated with $($top.Count) recent activity events."