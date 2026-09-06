param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateRange(2, 2147483647)]
    [int]$Processes,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$Script,

    [string]$MatlabExecutable = $env:OPENSEES_MATLAB_EXECUTABLE,

    [string]$MpiExecutable = $env:OPENSEES_MPIEXEC,

    [string]$FigureDirectory = $env:OPENSEES_MATLAB_FIGURE_DIRECTORY
)

$ErrorActionPreference = 'Stop'
$scriptPath = (Resolve-Path -LiteralPath $Script).Path
$nativeDirectory = Join-Path $PSScriptRoot 'derived\windows-x86_64'
$worker = Join-Path $nativeDirectory 'OpenSeesSPWorker.exe'
if (-not (Test-Path -LiteralPath $worker -PathType Leaf)) {
    throw "OpenSeesSPWorker.exe was not found in $nativeDirectory"
}

if (-not $MatlabExecutable) {
    $matlabCandidates = @()
    if ($env:MATLAB_ROOT) {
        $matlabCandidates += Join-Path $env:MATLAB_ROOT 'bin\matlab.exe'
    }
    $matlabCommand = Get-Command matlab.exe -ErrorAction SilentlyContinue
    if ($matlabCommand) {
        $matlabCandidates += $matlabCommand.Source
    }
    foreach ($registryRoot in @(
        'HKLM:\SOFTWARE\MathWorks\MATLAB',
        'HKCU:\SOFTWARE\MathWorks\MATLAB'
    )) {
        if (Test-Path -LiteralPath $registryRoot) {
            Get-ChildItem -LiteralPath $registryRoot -ErrorAction SilentlyContinue |
                Sort-Object PSChildName -Descending |
                ForEach-Object {
                    $properties = Get-ItemProperty -LiteralPath $_.PSPath `
                        -ErrorAction SilentlyContinue
                    if ($properties.MATLABROOT) {
                        $matlabCandidates += Join-Path $properties.MATLABROOT 'bin\matlab.exe'
                    }
                }
        }
    }
    $MatlabExecutable = $matlabCandidates |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
    if (-not $MatlabExecutable) {
        throw 'MATLAB was not found automatically. Set OPENSEES_MATLAB_EXECUTABLE to matlab.exe.'
    }
}

$mpiCandidates = @()
if ($MpiExecutable) { $mpiCandidates += $MpiExecutable }
if ($env:I_MPI_ROOT) { $mpiCandidates += Join-Path $env:I_MPI_ROOT 'bin\mpiexec.exe' }
if ($env:MSMPI_BIN) { $mpiCandidates += Join-Path $env:MSMPI_BIN 'mpiexec.exe' }
if ($env:ONEAPI_ROOT) { $mpiCandidates += Join-Path $env:ONEAPI_ROOT 'mpi\latest\bin\mpiexec.exe' }
if (${env:ProgramFiles(x86)}) {
    $intelMpiRoot = Join-Path ${env:ProgramFiles(x86)} 'Intel\oneAPI\mpi'
    if (Test-Path -LiteralPath $intelMpiRoot -PathType Container) {
        $mpiCandidates += Get-ChildItem -LiteralPath $intelMpiRoot -Directory `
            -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName 'bin\mpiexec.exe' }
    }
}
$mpiCommand = Get-Command mpiexec.exe -ErrorAction SilentlyContinue
if ($mpiCommand) { $mpiCandidates += $mpiCommand.Source }
$resolvedMpiExecutable = $mpiCandidates |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1
if (-not $resolvedMpiExecutable) {
    throw 'mpiexec.exe was not found automatically. Install a compatible MPI runtime or set OPENSEES_MPIEXEC.'
}

# These environment changes are limited to this MPI job.
$runtimeDirectories = @(
    $nativeDirectory,
    (Split-Path -Parent $resolvedMpiExecutable)
) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) }
$env:PATH = (($runtimeDirectories + $env:PATH) -join [IO.Path]::PathSeparator)
$env:OPENSEES_BACKEND = 'sp'
if ($FigureDirectory) {
    $resolvedFigureDirectory = (Resolve-Path -LiteralPath $FigureDirectory).Path
    $env:OPENSEES_MATLAB_FIGURE_DIRECTORY = $resolvedFigureDirectory
}

$escapedRoot = $PSScriptRoot.Replace("'", "''")
$escapedScript = $scriptPath.Replace("'", "''")
$matlabCode = "addpath('$escapedRoot','-begin');"
$matlabCode += "OpenSeesNexus.setBackend('sp');"
$matlabCode += "nexus.internal.runSPModel('$escapedScript')"
$arguments = @(
    '-n', '1', $MatlabExecutable, '-batch', $matlabCode,
    ':', '-n', ($Processes - 1).ToString(), $worker
)
& $resolvedMpiExecutable @arguments
exit $LASTEXITCODE
