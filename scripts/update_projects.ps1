[CmdletBinding()]
param(
    [string]$ReadmePath = "README.md",
    [string]$User = $env:PROJECTS_USER,
    [int]$MaxPerCategory = 6
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($env:PROJECTS_MAX_PER_CATEGORY) {
    $MaxPerCategory = [int]$env:PROJECTS_MAX_PER_CATEGORY
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

$reposUri = "https://api.github.com/users/$User/repos?per_page=100&sort=pushed&direction=desc"
$repos = Invoke-RestMethod -Uri $reposUri -Headers $headers -Method Get

$excludeName = ""
if ($env:GITHUB_REPOSITORY) {
    $excludeName = ($env:GITHUB_REPOSITORY -split "/")[1]
}

function Get-ProfileMetadata {
    param([string]$ReadmeText)

    $match = [regex]::Match(
        $ReadmeText,
        "(?im)^\s*(?:<!--\s*)?PROFILE\s*:\s*(.+?)(?:\s*-->)?\s*$"
    )
    if (-not $match.Success) {
        return $null
    }

    $pairs = $match.Groups[1].Value -split "\s*[;|]\s*"
    $meta = @{}
    foreach ($pair in $pairs) {
        if ($pair -match "^\s*([^=]+?)\s*=\s*(.+?)\s*$") {
            $key = $Matches[1].Trim().ToLowerInvariant()
            $value = $Matches[2].Trim().Trim("`"").Trim("'")
            if ($key) {
                $meta[$key] = $value
            }
        }
    }
    if ($meta.Count -eq 0) {
        return $null
    }
    return $meta
}

function Limit-Text {
    param([string]$Text, [int]$Max = 140)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $Text
    }
    if ($Text.Length -le $Max) {
        return $Text
    }
    return ($Text.Substring(0, $Max - 3).TrimEnd() + "...")
}

$categoryOrder = New-Object System.Collections.Generic.List[string]
$categoryOrder.AddRange([string[]]@(
    "AI & ML",
    "Windows & Automation",
    "IoT & Hardware",
    "Mobile & Apps",
    "Tools & Templates",
    "Other"
))

$projects = New-Object System.Collections.Generic.List[object]

foreach ($repo in $repos) {
    if ($repo.fork -or $repo.archived -or $repo.disabled) {
        continue
    }
    if ($excludeName -and $repo.name -eq $excludeName) {
        continue
    }

    $readmeUri = "https://api.github.com/repos/$User/$($repo.name)/readme"
    $readmeText = $null
    try {
        $readmeText = Invoke-RestMethod -Uri $readmeUri -Headers ($headers + @{ "Accept" = "application/vnd.github.raw" }) -Method Get
    } catch {
        continue
    }

    $meta = Get-ProfileMetadata -ReadmeText $readmeText
    if (-not $meta) {
        continue
    }

    if ($meta.ContainsKey("show") -and $meta["show"].ToLowerInvariant() -eq "false") {
        continue
    }
    if ($meta.ContainsKey("include") -and $meta["include"].ToLowerInvariant() -eq "false") {
        continue
    }

    $status = ""
    if ($meta.ContainsKey("status")) {
        $status = $meta["status"].Trim()
        if ($status -match "^(archived|dropped|inactive)$") {
            continue
        }
    }

    $category = $meta["category"]
    if ([string]::IsNullOrWhiteSpace($category)) {
        $category = "Other"
    }

    if (-not $categoryOrder.Contains($category)) {
        $categoryOrder.Add($category)
    }

    $summary = $meta["summary"]
    if ([string]::IsNullOrWhiteSpace($summary)) {
        $summary = $repo.description
    }
    if ([string]::IsNullOrWhiteSpace($summary)) {
        $summary = "No description yet."
    }
    $summary = Limit-Text -Text $summary

    $projects.Add([pscustomobject]@{
        Name = $repo.name
        Url = $repo.html_url
        Category = $category
        Summary = $summary
        PushedAt = [DateTime]::Parse($repo.pushed_at)
        Status = $status
    })
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("<!--START_SECTION:projects_auto-->")

if ($projects.Count -eq 0) {
    $lines.Add("- Add a PROFILE line in repo READMEs to show projects here.")
} else {
    foreach ($category in $categoryOrder) {
        $items = $projects | Where-Object { $_.Category -eq $category } | Sort-Object -Property PushedAt -Descending
        if (-not $items) {
            continue
        }
        $lines.Add("### $category")
        $count = 0
        foreach ($item in $items) {
            if ($MaxPerCategory -gt 0 -and $count -ge $MaxPerCategory) {
                break
            }
            $statusLabel = ""
            if ($item.Status -and $item.Status -notmatch "^(active|stable)$") {
                $statusLabel = " (status: $($item.Status))"
            }
            $lines.Add("- [$($item.Name)]($($item.Url)) - $($item.Summary)$statusLabel")
            $count++
        }
        $lines.Add("")
    }
    if ($lines[$lines.Count - 1] -eq "") {
        $lines.RemoveAt($lines.Count - 1)
    }
}

$lines.Add("<!--END_SECTION:projects_auto-->")

$readme = Get-Content -Raw -Path $ReadmePath
$newline = if ($readme -match "`r`n") { "`r`n" } else { "`n" }
$blockText = $lines -join $newline
$pattern = "(?s)<!--START_SECTION:projects_auto-->.*?<!--END_SECTION:projects_auto-->"

if ($readme -match $pattern) {
    $readme = [regex]::Replace(
        $readme,
        $pattern,
        [System.Text.RegularExpressions.MatchEvaluator]{ $blockText }
    )
} else {
    $readme = $readme.TrimEnd() + $newline + $newline + "## Projects" + $newline + $newline + $blockText + $newline
}

Set-Content -Path $ReadmePath -Value $readme -Encoding utf8 -NoNewline
