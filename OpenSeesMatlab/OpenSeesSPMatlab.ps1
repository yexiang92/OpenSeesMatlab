param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateRange(2, 2147483647)]
    [int]$Processes,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$Script,

    [string]$MatlabExecutable = $env:OPENSEES_MATLAB_EXECUTABLE,

    [string]$MpiExecutable = $env:OPENSEES_MPIEXEC
)

$ErrorActionPreference = 'Stop'
$launcher = Join-Path $PSScriptRoot '+ops\+core\OpenSeesSPMatlab.ps1'
if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
    throw "The OpenSeesSP MATLAB launcher was not found below $PSScriptRoot"
}

& $launcher -Processes $Processes -Script $Script `
    -MatlabExecutable $MatlabExecutable -MpiExecutable $MpiExecutable
exit $LASTEXITCODE
