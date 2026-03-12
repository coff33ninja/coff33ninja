[CmdletBinding()]
param(
    [int]$Count = 3,
    [string]$ReadmePath = "README.md",
    [string]$User = $env:RECENT_PROJECTS_USER,
    [int]$Columns = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($env:RECENT_PROJECTS_COUNT) {
    $Count = [int]$env:RECENT_PROJECTS_COUNT
}

if ($env:RECENT_PROJECTS_COLS) {
    $Columns = [int]$env:RECENT_PROJECTS_COLS
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
    "X-GitHub-Api-Version" = "2022-11-28"
}

if ($env:GITHUB_TOKEN) {
    $headers["Authorization"] = "Bearer $env:GITHUB_TOKEN"
}

$uri = "https://api.github.com/users/$User/repos?per_page=100&sort=pushed&direction=desc"
try {
    $repos = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
} catch {
    Write-Host "Failed to fetch repositories. Leaving README unchanged."
    exit 0
}

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

function Get-Grade {
    param([int]$Score)
    if ($Score -ge 85) { return "A" }
    if ($Score -ge 70) { return "B" }
    if ($Score -ge 55) { return "C" }
    if ($Score -ge 40) { return "D" }
    return "E"
}

function Escape-Xml {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    return [System.Security.SecurityElement]::Escape($Text)
}

function Add-Category {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Label
    )
    if (-not $List.Contains($Label)) {
        $List.Add($Label)
    }
}

function Get-Categories {
    param(
        [string]$Name,
        [string]$Description,
        [string]$Language
    )
    $text = (($Name + " " + $Description).ToLowerInvariant())
    $cats = New-Object System.Collections.Generic.List[string]

    if ($text -match "\bai\b|\bml\b|llm|chatbot|model") { Add-Category -List $cats -Label "🧠 AI" }
    if ($text -match "vrm|avatar|aura") { Add-Category -List $cats -Label "🎭 Avatar" }
    if ($text -match "osint|intel|dark web|recon") { Add-Category -List $cats -Label "🕵️ OSINT" }
    if ($text -match "automation|optimizer|powershell|windows|system|setup|batch") { Add-Category -List $cats -Label "🛠 Windows" }
    if ($text -match "iot|esp32|arduino|matrix|home automation") { Add-Category -List $cats -Label "🔌 IoT" }
    if ($text -match "discord|bot") { Add-Category -List $cats -Label "💬 Discord" }
    if ($text -match "remote|lan|network|ssh|agent") { Add-Category -List $cats -Label "🌐 Network" }
    if ($text -match "template|starter|boilerplate|scaffold") { Add-Category -List $cats -Label "🧰 Templates" }
    if ($text -match "web|frontend|react|node") { Add-Category -List $cats -Label "🌐 Web" }

    if ($Language -eq "Dart" -or $text -match "flutter|android") { Add-Category -List $cats -Label "📱 Mobile" }
    if ($Language -eq "Go") { Add-Category -List $cats -Label "⚙️ Go" }
    if ($Language -eq "Kotlin") { Add-Category -List $cats -Label "📱 Kotlin" }

    if ($cats.Count -eq 0) {
        $cats.Add("🧪 Experimental")
    }

    return $cats
}

$readme = Get-Content -Raw -Path $ReadmePath
$newline = if ($readme -match "`r`n") { "`r`n" } else { "`n" }

$statSource = $filtered
$totalRepos = $statSource.Count
$totalStars = ($statSource | Measure-Object -Property stargazers_count -Sum).Sum
$totalForks = ($statSource | Measure-Object -Property forks_count -Sum).Sum
$activeThreshold = (Get-Date).AddDays(-30)
$active30 = ($statSource | Where-Object { [DateTime]::Parse($_.pushed_at) -ge $activeThreshold }).Count
$topLanguages = $statSource |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_.language) } |
    Group-Object -Property language |
    Sort-Object -Property Count -Descending |
    Select-Object -First 6
$topLanguageCodes = $topLanguages | ForEach-Object { "<kbd>$($_.Name)</kbd>" }
if (-not $topLanguageCodes -or $topLanguageCodes.Count -eq 0) {
    $topLanguageCodes = @("<kbd>Unknown</kbd>")
}
$latest = $statSource | Sort-Object -Property pushed_at -Descending | Select-Object -First 1
$latestName = if ($latest) { Limit-Text -Text $latest.name -Max 18 } else { "None" }
$latestLabel = "<kbd>$latestName</kbd>"

$activityScore = if ($totalRepos -gt 0) { [math]::Round(($active30 / $totalRepos) * 100) } else { 0 }
$grade = Get-Grade -Score $activityScore
$gradeLabel = "$grade"

$languageColors = @{
    "Python" = "#3776AB"
    "JavaScript" = "#F7DF1E"
    "TypeScript" = "#3178C6"
    "PowerShell" = "#5391FE"
    "Go" = "#00ADD8"
    "Kotlin" = "#7F52FF"
    "Dart" = "#0175C2"
    "C++" = "#00599C"
    "Batchfile" = "#C1F12E"
}

$langTotal = ($topLanguages | Measure-Object -Property Count -Sum).Sum
if (-not $langTotal -or $langTotal -eq 0) { $langTotal = 1 }

$bars = New-Object System.Text.StringBuilder
$barX = 470
$barY = 86
$barWidth = 260
$barHeight = 8
$rowGap = 24
$i = 0
foreach ($lang in $topLanguages) {
    $percent = [math]::Round(($lang.Count / $langTotal) * 100, 1)
    $fill = [math]::Round($barWidth * ($percent / 100))
    $color = if ($languageColors.ContainsKey($lang.Name)) { $languageColors[$lang.Name] } else { "#6b7280" }
    $y = $barY + ($i * $rowGap)
    $labelY = $y - 2
    $bars.AppendLine("<circle cx=""$barX"" cy=""$labelY"" r=""4"" fill=""$color"" />") | Out-Null
    $bars.AppendLine("<text x=""$($barX + 10)"" y=""$labelY"" fill=""#cbd5f5"" font-size=""12"" font-family=""Segoe UI, Roboto, sans-serif"">$($lang.Name)</text>") | Out-Null
    $bars.AppendLine("<text x=""$($barX + 200)"" y=""$labelY"" fill=""#7fa0ff"" font-size=""12"" font-family=""Segoe UI, Roboto, sans-serif"">$percent%</text>") | Out-Null
    $bars.AppendLine("<rect x=""$barX"" y=""$($y + 6)"" width=""$barWidth"" height=""$barHeight"" rx=""4"" fill=""#1f2535"" />") | Out-Null
    $bars.AppendLine("<rect x=""$barX"" y=""$($y + 6)"" width=""$fill"" height=""$barHeight"" rx=""4"" fill=""$color"" />") | Out-Null
    $i++
}

$circumference = [math]::Round(2 * [math]::PI * 38, 2)
$dash = [math]::Round(($activityScore / 100) * $circumference, 2)

$svg = @"
<svg xmlns="http://www.w3.org/2000/svg" width="900" height="260" viewBox="0 0 900 260">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#0b0f19"/>
      <stop offset="100%" stop-color="#151a28"/>
    </linearGradient>
  </defs>
  <rect x="0" y="0" width="900" height="260" rx="18" fill="url(#bg)" stroke="#242b3d" />
  <text x="28" y="36" fill="#9fb3ff" font-size="18" font-weight="600" font-family="Segoe UI, Roboto, sans-serif">Profile Snapshot</text>

  <text x="28" y="72" fill="#9fb3ff" font-size="12" font-family="Segoe UI, Roboto, sans-serif">Public Repos</text>
  <text x="170" y="72" fill="#e5edff" font-size="14" font-weight="600" font-family="Segoe UI, Roboto, sans-serif">$totalRepos</text>

  <text x="28" y="98" fill="#9fb3ff" font-size="12" font-family="Segoe UI, Roboto, sans-serif">Active (30d)</text>
  <text x="170" y="98" fill="#e5edff" font-size="14" font-weight="600" font-family="Segoe UI, Roboto, sans-serif">$active30</text>

  <text x="28" y="124" fill="#9fb3ff" font-size="12" font-family="Segoe UI, Roboto, sans-serif">Stars</text>
  <text x="170" y="124" fill="#e5edff" font-size="14" font-weight="600" font-family="Segoe UI, Roboto, sans-serif">$totalStars</text>

  <text x="28" y="150" fill="#9fb3ff" font-size="12" font-family="Segoe UI, Roboto, sans-serif">Forks</text>
  <text x="170" y="150" fill="#e5edff" font-size="14" font-weight="600" font-family="Segoe UI, Roboto, sans-serif">$totalForks</text>

  <text x="28" y="176" fill="#9fb3ff" font-size="12" font-family="Segoe UI, Roboto, sans-serif">Latest Push</text>
  <text x="170" y="176" fill="#e5edff" font-size="14" font-weight="600" font-family="Segoe UI, Roboto, sans-serif">$latestName</text>

  <text x="470" y="66" fill="#9fb3ff" font-size="12" font-family="Segoe UI, Roboto, sans-serif">Top Languages</text>
  $bars

  <circle cx="820" cy="110" r="38" fill="none" stroke="#1f2535" stroke-width="8" />
  <circle cx="820" cy="110" r="38" fill="none" stroke="#6ea8ff" stroke-width="8" stroke-linecap="round"
          stroke-dasharray="$dash $circumference" transform="rotate(-90 820 110)" />
  <text x="820" y="116" text-anchor="middle" fill="#e5edff" font-size="20" font-weight="700" font-family="Segoe UI, Roboto, sans-serif">$gradeLabel</text>
  <text x="820" y="136" text-anchor="middle" fill="#9fb3ff" font-size="11" font-family="Segoe UI, Roboto, sans-serif">$activityScore% active</text>
</svg>
"@

$readmeDir = Split-Path -Parent $ReadmePath
if ([string]::IsNullOrWhiteSpace($readmeDir)) {
    $readmeDir = (Get-Location).Path
}
$assetsDir = Join-Path $readmeDir "assets"
if (-not (Test-Path $assetsDir)) {
    New-Item -ItemType Directory -Path $assetsDir | Out-Null
}
$svgPath = Join-Path $assetsDir "profile-stats.svg"
Set-Content -Path $svgPath -Value $svg -Encoding utf8

$statsLines = New-Object System.Collections.Generic.List[string]
$statsLines.Add("<!--START_SECTION:profile_stats-->")
$statsLines.Add("<div align=""center"">")
$statsLines.Add("<img src=""assets/profile-stats.svg"" width=""100%"" alt=""Profile stats"" />")
$statsLines.Add("</div>")
$statsLines.Add("<!--END_SECTION:profile_stats-->")
$statsBlockText = $statsLines -join $newline
$statsPattern = "(?s)<!--START_SECTION:profile_stats-->.*?<!--END_SECTION:profile_stats-->"

if ($readme -match $statsPattern) {
    $readme = [regex]::Replace(
        $readme,
        $statsPattern,
        [System.Text.RegularExpressions.MatchEvaluator]{ $statsBlockText }
    )
} else {
    $readme = $readme.TrimEnd() + $newline + $newline + "## Profile Stats" + $newline + $newline + $statsBlockText + $newline
}

$cards = New-Object System.Collections.Generic.List[object]
foreach ($repo in $top) {
    $desc = $repo.description
    if ([string]::IsNullOrWhiteSpace($desc)) {
        $desc = "No description yet."
    }
    $desc = Limit-Text -Text $desc -Max 90
    $language = $repo.language
    if ([string]::IsNullOrWhiteSpace($language)) {
        $language = "Unknown"
    }
    $updated = [DateTime]::Parse($repo.pushed_at).ToString("yyyy-MM-dd")
    $categories = Get-Categories -Name $repo.name -Description $desc -Language $language
    $categoryText = ($categories | Select-Object -First 2) -join " • "
    if ([string]::IsNullOrWhiteSpace($categoryText)) {
        $categoryText = "🧪 Experimental"
    }

    $cards.Add([pscustomobject]@{
        Name = $repo.name
        Url = $repo.html_url
        Desc = $desc
        Language = $language
        Updated = $updated
        Categories = $categoryText
    })
}

if ($Columns -lt 1) {
    $Columns = 2
}

$cardWidth = 400
$cardHeight = 110
$gapX = 20
$gapY = 16
$paddingX = 40
$paddingY = 24
$headerHeight = 52
$rows = if ($cards.Count -gt 0) { [math]::Ceiling($cards.Count / $Columns) } else { 1 }
$svgWidth = ($paddingX * 2) + ($cardWidth * $Columns) + ($gapX * ($Columns - 1))
$cardsTop = $paddingY + $headerHeight
$svgHeight = $paddingY + $headerHeight + ($rows * $cardHeight) + ($gapY * ($rows - 1)) + $paddingY

$cardsSvg = New-Object System.Text.StringBuilder

if ($cards.Count -eq 0) {
    $cardsSvg.AppendLine("<text x=""$paddingX"" y=""$($cardsTop + 28)"" fill=""#cbd5f5"" font-size=""14"" font-family=""Segoe UI, Roboto, sans-serif"">No active public repositories found.</text>") | Out-Null
} else {
    for ($index = 0; $index -lt $cards.Count; $index++) {
        $row = [math]::Floor($index / $Columns)
        $col = $index % $Columns
        $x = $paddingX + ($col * ($cardWidth + $gapX))
        $y = $cardsTop + ($row * ($cardHeight + $gapY))
        $card = $cards[$index]

        $name = Escape-Xml $card.Name
        $descText = Escape-Xml $card.Desc
        $langText = Escape-Xml $card.Language
        $updatedText = Escape-Xml $card.Updated
        $categoryText = Escape-Xml $card.Categories
        $url = Escape-Xml $card.Url

        $cardsSvg.AppendLine("<a href=""$url"">") | Out-Null
        $cardsSvg.AppendLine("<rect x=""$x"" y=""$y"" width=""$cardWidth"" height=""$cardHeight"" rx=""14"" fill=""#111827"" stroke=""#2a3348"" />") | Out-Null
        $cardsSvg.AppendLine("<text x=""$($x + 16)"" y=""$($y + 28)"" fill=""#e5edff"" font-size=""15"" font-weight=""600"" font-family=""Segoe UI, Roboto, sans-serif"">$name</text>") | Out-Null
        $cardsSvg.AppendLine("<text x=""$($x + 16)"" y=""$($y + 50)"" fill=""#9fb3ff"" font-size=""12"" font-family=""Segoe UI, Roboto, sans-serif"">$descText</text>") | Out-Null
        $cardsSvg.AppendLine("<text x=""$($x + 16)"" y=""$($y + 74)"" fill=""#6ea8ff"" font-size=""11"" font-family=""Segoe UI, Roboto, sans-serif"">$langText</text>") | Out-Null
        $cardsSvg.AppendLine("<text x=""$($x + 120)"" y=""$($y + 74)"" fill=""#6ea8ff"" font-size=""11"" font-family=""Segoe UI, Roboto, sans-serif"">Updated $updatedText</text>") | Out-Null
        $cardsSvg.AppendLine("<text x=""$($x + 16)"" y=""$($y + 96)"" fill=""#cbd5f5"" font-size=""11"" font-family=""Segoe UI, Roboto, sans-serif"">$categoryText</text>") | Out-Null
        $cardsSvg.AppendLine("</a>") | Out-Null
    }
}

$cardsSvgText = $cardsSvg.ToString().TrimEnd()
$recentSvg = @"
<svg xmlns="http://www.w3.org/2000/svg" width="$svgWidth" height="$svgHeight" viewBox="0 0 $svgWidth $svgHeight">
  <defs>
    <linearGradient id="cardsBg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#0b0f19"/>
      <stop offset="100%" stop-color="#151a28"/>
    </linearGradient>
  </defs>
  <rect x="0" y="0" width="$svgWidth" height="$svgHeight" rx="18" fill="url(#cardsBg)" stroke="#242b3d" />
  <text x="$paddingX" y="$($paddingY + 12)" fill="#9fb3ff" font-size="18" font-weight="600" font-family="Segoe UI, Roboto, sans-serif">Last 10 Repos</text>
  <text x="$paddingX" y="$($paddingY + 32)" fill="#6ea8ff" font-size="12" font-family="Segoe UI, Roboto, sans-serif">Sorted by last push • public + active only</text>
  $cardsSvgText
</svg>
"@

$recentSvgPath = Join-Path $assetsDir "recent-projects.svg"
Set-Content -Path $recentSvgPath -Value $recentSvg -Encoding utf8

$blockLines = New-Object System.Collections.Generic.List[string]
$blockLines.Add("<!--START_SECTION:recent_projects-->")
$blockLines.Add("<div align=""center"">")
$blockLines.Add("<img src=""assets/recent-projects.svg"" width=""100%"" alt=""Last 10 repos"" />")
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
