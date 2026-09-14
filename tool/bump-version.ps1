param(
    [ValidateSet('Patch', 'Minor', 'Major')]
    [string]$Part = 'Patch',
    [switch]$DryRun
)

$mobileRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pubspecPath = Join-Path $mobileRoot 'pubspec.yaml'
$aboutPagePath = Join-Path $mobileRoot 'lib/features/settings/about_page.dart'

$utf8 = [Text.UTF8Encoding]::new($false)
$pubspec = $utf8.GetString([IO.File]::ReadAllBytes($pubspecPath))
$versionPattern = [regex]::new('(?m)^version:[ \t]+(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(\+[1-9]\d*)?[ \t]*(?=\r?$)')
$versionMatch = $versionPattern.Match($pubspec)
if (-not $versionMatch.Success) {
    throw "Unable to find a semantic version in $pubspecPath"
}

$aboutPage = $utf8.GetString([IO.File]::ReadAllBytes($aboutPagePath))
$aboutPattern = [regex]::new("(?m)^const appVersion = '[^']+';")
if (-not $aboutPattern.IsMatch($aboutPage)) {
    throw "Unable to find appVersion in $aboutPagePath"
}

$major = [int]$versionMatch.Groups[1].Value
$minor = [int]$versionMatch.Groups[2].Value
$patch = [int]$versionMatch.Groups[3].Value
$currentVersion = "$major.$minor.$patch"
$buildSuffix = $versionMatch.Groups[4].Value
switch ($Part) {
    'Patch' { $patch++ }
    'Minor' { $minor++; $patch = 0 }
    'Major' { $major++; $minor = 0; $patch = 0 }
}
$nextVersion = "$major.$minor.$patch"
$nextPubspecVersion = "$nextVersion$buildSuffix"

if ($DryRun) {
    Write-Output "$currentVersion$buildSuffix -> $nextPubspecVersion"
    exit 0
}

$nextPubspec = $versionPattern.Replace(
    $pubspec,
    "version: $nextPubspecVersion",
    1
)
$nextAboutPage = $aboutPattern.Replace(
    $aboutPage,
    "const appVersion = '$nextVersion';",
    1
)

[IO.File]::WriteAllText($pubspecPath, $nextPubspec, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($aboutPagePath, $nextAboutPage, [Text.UTF8Encoding]::new($false))
Write-Output "Version bumped to $nextPubspecVersion"
