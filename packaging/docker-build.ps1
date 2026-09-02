[CmdletBinding()]
param(
    [switch]$NoCache,
    [switch]$WithArduinoAvr,
    [string]$UbuntuMirror,
    [string]$PyPiMirror
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$imageName = 'lapki-compiler-builder:local'

$buildArgs = @('build')
if ($NoCache) {
    $buildArgs += '--no-cache'
}
if ($WithArduinoAvr) {
    $buildArgs += @('--build-arg', 'INSTALL_ARDUINO_AVR_CORE=true')
}
if ($UbuntuMirror) {
    $buildArgs += @('--build-arg', "UBUNTU_MIRROR=$UbuntuMirror")
}
if ($PyPiMirror) {
    $buildArgs += @('--build-arg', "PIP_INDEX_URL=$PyPiMirror")
}
$buildArgs += @('-t', $imageName, $projectRoot)
& docker @buildArgs
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

& docker run --rm -v "${projectRoot}:/src" $imageName
exit $LASTEXITCODE
