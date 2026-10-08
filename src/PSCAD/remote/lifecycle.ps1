# Shared process lifecycle for the supervisor and caller-side cancellation.
$ErrorActionPreference = "Stop"

function Stop-OwnedRunner {
    param(
        [Parameter(Mandatory = $true)]
        [string] $OwnerPath,
        [Parameter(Mandatory = $true)]
        [string] $OwnedRoot
    )

    if (-not (Test-Path -LiteralPath $OwnerPath -PathType Leaf)) {
        return
    }

    $owner = @(Get-Content -LiteralPath $OwnerPath)
    if ($owner.Count -ne 2) {
        throw "Invalid PSCAD runner owner file: $OwnerPath"
    }

    $processId = 0
    if (-not [int]::TryParse($owner[0], [ref] $processId)) {
        throw "Invalid PSCAD runner PID in $OwnerPath"
    }
    if ($processId -le 0) {
        throw "Invalid PSCAD runner PID in $OwnerPath"
    }

    $runner = [IO.Path]::GetFullPath($owner[1])
    $root = [IO.Path]::GetFullPath($OwnedRoot).TrimEnd('\') + '\'
    if (-not $runner.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to stop a process outside the PSCAD case directory: $runner"
    }

    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $processId"
    if ($null -eq $process) {
        Remove-Item -LiteralPath $OwnerPath -Force
        return
    }

    if ($null -eq $process.CommandLine -or
        $process.CommandLine.IndexOf($runner, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw "PID $processId no longer belongs to the recorded PSCAD runner"
    }

    & taskkill.exe /PID $processId /T /F | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not stop PSCAD runner process tree $processId"
    }
    Remove-Item -LiteralPath $OwnerPath -Force -ErrorAction SilentlyContinue
}

function Stop-EMTDC {
    param([string] $CaseDirectory)

    $root = [IO.Path]::GetFullPath($CaseDirectory).TrimEnd('\') + '\'
    # Simulation executables are built beneath the staged case. Never select
    # by executable name alone: restored user projects may also be running.
    foreach ($simulation in @(Get-CimInstance Win32_Process)) {
        if ($null -ne $simulation.ExecutablePath -and
            $simulation.ExecutablePath.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -and
            $simulation.ExecutablePath.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase)) {
            & taskkill.exe /PID $simulation.ProcessId /T /F | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Could not stop EMTDC simulation process $($simulation.ProcessId)"
            }
        }
    }
}

function Stop-OwnedPSCAD {
    param([string] $OwnerPath, [int] $GraceSeconds = 0)

    if (-not (Test-Path -LiteralPath $OwnerPath -PathType Leaf)) {
        return
    }
    # Only a desktop PSCAD started by this supervisor gets an owner file.
    # Include creation time to distinguish the process from a reused PID.
    $owner = @(Get-Content -LiteralPath $OwnerPath)
    $processId = 0
    $port = 0
    if ($owner.Count -ne 4 -or
        -not [int]::TryParse($owner[0], [ref] $processId) -or $processId -le 0 -or
        -not [int]::TryParse($owner[2], [ref] $port) -or $port -lt 1024 -or $port -gt 65535 -or
        [IO.Path]::GetFileName($owner[1]) -ine 'Pscad.exe') {
        throw "Invalid PSCAD application owner file: $OwnerPath"
    }
    $deadline = [DateTime]::UtcNow.AddSeconds($GraceSeconds)
    do {
        $application = Get-CimInstance Win32_Process -Filter "ProcessId = $processId"
        if ($null -eq $application) {
            Remove-Item -LiteralPath $OwnerPath -Force -ErrorAction SilentlyContinue
            return
        }
        if ($application.ExecutablePath -ine $owner[1] -or
            $application.CreationDate.ToUniversalTime().ToString('o') -cne $owner[3] -or
            $null -eq $application.CommandLine -or
            $application.CommandLine -notmatch "/port:$port(\s|$)") {
            throw "PID $processId no longer belongs to the recorded owned PSCAD"
        }
        if ([DateTime]::UtcNow -ge $deadline) { break }
        Start-Sleep -Milliseconds 500
    } while ($true)
    & taskkill.exe /PID $processId /T /F | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not stop owned PSCAD process tree $processId"
    }
    Remove-Item -LiteralPath $OwnerPath -Force -ErrorAction SilentlyContinue
}

function Stop-PSCADCase {
    param(
        [Parameter(Mandatory = $true)]
        [string] $LocalCase
    )

    Stop-OwnedRunner -OwnerPath (Join-Path $LocalCase "owner.txt") -OwnedRoot $LocalCase
    Stop-EMTDC -CaseDirectory $LocalCase
    Stop-OwnedPSCAD -OwnerPath (Join-Path $LocalCase "pscad-owner.txt")
}
