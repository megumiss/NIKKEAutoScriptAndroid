param(
    [switch]$DryRun
)

$mobileRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pubspecPath = Join-Path $mobileRoot 'pubspec.yaml'
$aboutPagePath = Join-Path $mobileRoot 'lib/features/settings/about_page.dart'

$utf8 = [Text.UTF8Encoding]::new($false)
$pubspec = $utf8.GetString([IO.File]::ReadAllBytes($pubspecPath))
$versionMatch = [regex]::Match($pubspec, '(?m)^version:[ \t]+(\d+)\.(\d+)\.(\d+)(?:\+\d+)?[ \t]*$')
if (-not $versionMatch.Success) {
    throw "Unable to find a semantic version in $pubspecPath"
}

$major = [int]$versionMatch.Groups[1].Value
$minor = [int]$versionMatch.Groups[2].Value
$patch = [int]$versionMatch.Groups[3].Value + 1
if ($patch -ge 10) {
    $patch = 0
    $minor++
}
if ($minor -ge 10) {
    $minor = 0
    $major++
}
$nextVersion = "$major.$minor.$patch"

if ($DryRun) {
    Write-Output "$($versionMatch.Groups[1].Value).$($versionMatch.Groups[2].Value).$($versionMatch.Groups[3].Value) -> $nextVersion"
    exit 0
}

$nextPubspec = [regex]::Replace(
    $pubspec,
    '(?m)^version:[ \t]+\S+[ \t]*$',
    "version: $nextVersion",
    1
)
$nextAboutPage = [regex]::Replace(
    $utf8.GetString([IO.File]::ReadAllBytes($aboutPagePath)),
    "const appVersion = '[^']+';",
    "const appVersion = '$nextVersion';",
    1
)

[IO.File]::WriteAllText($pubspecPath, $nextPubspec, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($aboutPagePath, $nextAboutPage, [Text.UTF8Encoding]::new($false))
Write-Output "Version bumped to $nextVersion"
