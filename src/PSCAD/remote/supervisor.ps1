param(
    [Parameter(Mandatory = $true)]
    [string] $SharedCase,
    [Parameter(Mandatory = $true)]
    [string] $LocalCase,
    [Parameter(Mandatory = $true)]
    [string] $RemoteRoot,
    [Parameter(Mandatory = $true)]
    [string] $Julia,
    [Parameter(Mandatory = $true)]
    [string] $Python,
    [Parameter(Mandatory = $true)]
    [string] $ProjectName,
    [Parameter(Mandatory = $true)]
    [string] $OutputStem,
    [Parameter(Mandatory = $true)]
    [string] $PSCADVersion,
    [ValidateScript({ $_ -eq 0 -or ($_ -ge 1024 -and $_ -le 65535) })]
    [int] $PSCADPort = 0,
    [Parameter(Mandatory = $true)]
    [ValidateRange(0, 2)]
    [int] $Verbosity,
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 2147483647)]
    [int] $TimeoutSeconds
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

. (Join-Path $PSScriptRoot "lifecycle.ps1")

function Remove-DirectoryWithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,
        [int] $Attempts = 30,
        [int] $DelayMilliseconds = 500,
        [switch] $BestEffort
    )

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        if (-not (Test-Path -LiteralPath $Path)) {
            return
        }
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            return
        } catch {
            if ($attempt -eq $Attempts) {
                if ($BestEffort) {
                    return
                }
                throw
            }
            Start-Sleep -Milliseconds $DelayMilliseconds
        }
    }
}

function Copy-Result {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Source,
        [Parameter(Mandatory = $true)]
        [string] $Destination
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    if (Test-Path -LiteralPath $Source -PathType Container) {
        Get-ChildItem -LiteralPath $Source -Force |
            Copy-Item -Destination $Destination -Recurse -Force
    }
}

function Write-NewLines {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,
        [Parameter(Mandatory = $true)]
        [ref] $Count,
        [Parameter(Mandatory = $true)]
        [bool] $ErrorStream
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }
    $lines = @(Get-Content -LiteralPath $Path)
    for ($index = $Count.Value; $index -lt $lines.Count; $index++) {
        if ($ErrorStream) {
            [Console]::Error.WriteLine($lines[$index])
        } else {
            [Console]::Out.WriteLine($lines[$index])
        }
    }
    $Count.Value = $lines.Count
}

if (-not (Test-Path -LiteralPath $SharedCase -PathType Container)) {
    throw "PSCAD exchange directory is unavailable: $SharedCase"
}
if (-not (Test-Path -LiteralPath $Julia -PathType Leaf)) {
    throw "Julia executable is unavailable: $Julia"
}
if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) {
    throw "Python executable is unavailable: $Python"
}

$sharedFull = [IO.Path]::GetFullPath($SharedCase).TrimEnd('\') + '\'
$localFull = [IO.Path]::GetFullPath($LocalCase).TrimEnd('\') + '\'
if ($sharedFull.StartsWith($localFull, [StringComparison]::OrdinalIgnoreCase) -or
    $localFull.StartsWith($sharedFull, [StringComparison]::OrdinalIgnoreCase)) {
    throw "PSCAD exchange and scratch directories must not overlap"
}
$ownerPath = Join-Path $LocalCase "owner.txt"
$pscadOwnerPath = Join-Path $LocalCase "pscad-owner.txt"
Stop-PSCADCase -LocalCase $LocalCase
if (Test-Path -LiteralPath $LocalCase) {
    Remove-DirectoryWithRetry -Path $LocalCase
}
New-Item -ItemType Directory -Path $LocalCase -Force | Out-Null
Get-ChildItem -LiteralPath $SharedCase -Force |
    Where-Object Name -ne "outputs" |
    Copy-Item -Destination $LocalCase -Recurse -Force

$toolkit = Join-Path $LocalCase "toolkit"
$runner = Join-Path $toolkit "runner.jl"
$project = Join-Path $toolkit "Project.toml"
$projectFile = Join-Path $LocalCase "generated.pscx"
$result = Join-Path $LocalCase "result"
$sharedOutput = Join-Path $SharedCase "outputs"
$stdoutPath = Join-Path $result "stdout.txt"
$stderrPath = Join-Path $result "stderr.txt"
$exitPath = Join-Path $result "exit-code.txt"
$invokePath = Join-Path $LocalCase "invoke-runner.cmd"

foreach ($required in @($runner, $project, $projectFile)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Staged PSCAD input is missing: $required"
    }
}

New-Item -ItemType Directory -Path $result -Force | Out-Null
New-Item -ItemType Directory -Path $sharedOutput -Force | Out-Null
$commandValues = @(
    $Julia,
    $Python,
    $toolkit,
    $runner,
    $projectFile,
    $result,
    $ProjectName,
    $OutputStem,
    $RemoteRoot,
    $stdoutPath,
    $stderrPath,
    $exitPath
)
foreach ($value in $commandValues) {
    if ($value.IndexOfAny(@([char] '"', [char] '%', [char] 10, [char] 13)) -ge 0) {
        throw "PSCAD runner command value contains an unsupported character: $value"
    }
}
$pscadOwned = $false
$pscadProcessId = 0
$process = $null
$exitCode = 1
$timedOut = $false
$stdoutCount = 0
$stderrCount = 0
try {
    if ($PSCADPort -ne 0) {
        $listeners = @(Get-NetTCPConnection -LocalPort $PSCADPort -State Listen -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty OwningProcess -Unique)
        if ($listeners.Count -eq 0) {
            $exe = & $Python -c "from mhi.common import process; print(process.find_exe('PSCAD', version='$PSCADVersion', x64=True))"
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $exe -PathType Leaf)) {
                throw "Could not resolve the PSCAD $PSCADVersion executable with mhi.common"
            }
            $exe = [IO.Path]::GetFullPath($exe.Trim())
            $runId = Split-Path (Split-Path $LocalCase -Parent) -Leaf
            $taskName = "PowerImpedance-PSCAD-$runId"
            $startedAt = [DateTime]::UtcNow
            try {
                $action = New-ScheduledTaskAction -Execute $exe -Argument "/startup:au /port:$PSCADPort /silence:true /splash:false"
                $principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
                $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
                Register-ScheduledTask -TaskName $taskName -TaskPath '\' -Action $action -Principal $principal -Settings $settings -Force | Out-Null
                Start-ScheduledTask -TaskName $taskName -TaskPath '\'
                $deadline = [DateTime]::UtcNow.AddSeconds(90)
                do {
                    $listeners = @(Get-NetTCPConnection -LocalPort $PSCADPort -State Listen -ErrorAction SilentlyContinue |
                        Select-Object -ExpandProperty OwningProcess -Unique)
                    if ($listeners.Count -gt 0) { break }
                    Start-Sleep -Milliseconds 500
                } while ([DateTime]::UtcNow -lt $deadline)
                if ($listeners.Count -eq 0) {
                    # PSCAD may have started without opening its automation port.
                    # Retain ownership so the outer finally can still close it.
                    $applications = @(Get-CimInstance Win32_Process -Filter "Name = 'Pscad.exe'" |
                        Where-Object {
                            $_.ExecutablePath -ieq $exe -and
                            $_.CreationDate.ToUniversalTime() -ge $startedAt -and
                            $null -ne $_.CommandLine -and
                            $_.CommandLine -match "/port:$PSCADPort(\s|$)"
                        })
                    if ($applications.Count -eq 1) {
                        $application = $applications[0]
                        $pscadProcessId = $application.ProcessId
                        Set-Content -LiteralPath $pscadOwnerPath -Value @($pscadProcessId, $exe, $PSCADPort, $application.CreationDate.ToUniversalTime().ToString('o'))
                        $pscadOwned = $true
                    }
                    throw "PSCAD did not listen on port $PSCADPort within 90 seconds. A logged-on desktop session is required for the station account (a disconnected RDP session is fine), or start PSCAD with /port:$PSCADPort."
                }
                if ($listeners.Count -ne 1) {
                    throw "Multiple processes are listening on PSCAD port $PSCADPort"
                }
                $pscadProcessId = $listeners[0]
                $application = Get-CimInstance Win32_Process -Filter "ProcessId = $pscadProcessId"
                if ($null -eq $application -or $application.ExecutablePath -ine $exe -or
                    $application.CreationDate.ToUniversalTime() -lt $startedAt -or
                    $null -eq $application.CommandLine -or
                    $application.CommandLine -notmatch "/port:$PSCADPort(\s|$)") {
                    throw "Listener on port $PSCADPort does not belong to the PSCAD desktop start"
                }
                Set-Content -LiteralPath $pscadOwnerPath -Value @($pscadProcessId, $exe, $PSCADPort, $application.CreationDate.ToUniversalTime().ToString('o'))
                $pscadOwned = $true
            } finally {
                Unregister-ScheduledTask -TaskName $taskName -TaskPath '\' -Confirm:$false -ErrorAction SilentlyContinue
            }
        } else {
            if ($listeners.Count -ne 1) {
                throw "Multiple processes are listening on PSCAD port $PSCADPort"
            }
            $pscadProcessId = $listeners[0]
        }
        [Console]::Out.WriteLine("PSCAD port=$PSCADPort PID=$pscadProcessId owned=$pscadOwned")
    }
    $runnerOwned = ($PSCADPort -eq 0 -or $pscadOwned).ToString().ToLowerInvariant()
    $runnerArguments = @(
        "`"--project=$toolkit`"",
        "--startup-file=no",
        "`"$runner`"",
        "`"$projectFile`"",
        "`"$result`"",
        "`"$ProjectName`"",
        "`"$OutputStem`"",
        "`"$PSCADVersion`"",
        "`"$Verbosity`"",
        "`"$PSCADPort`"",
        "`"$runnerOwned`"",
        "`"$RemoteRoot`""
    )
    $invokeLines = @(
        "@echo off",
        "setlocal",
        "set `"JULIA_PYTHONCALL_EXE=$Python`"",
        "`"$Julia`" $($runnerArguments -join ' ') 1>`"$stdoutPath`" 2>`"$stderrPath`"",
        "set `"PSCAD_EXIT=%ERRORLEVEL%`"",
        ">`"$exitPath`" echo %PSCAD_EXIT%",
        "exit /b %PSCAD_EXIT%"
    )
    [IO.File]::WriteAllLines($invokePath, $invokeLines, [Text.Encoding]::ASCII)

    $process = Start-Process `
        -FilePath $env:ComSpec `
        -ArgumentList @("/d", "/s", "/c", "`"$invokePath`"") `
        -PassThru `
        -WindowStyle Hidden
    Set-Content -LiteralPath $ownerPath -Value @($process.Id, $invokePath)
    if ($Verbosity -ge 2) {
        [Console]::Out.WriteLine("Started PSCAD runner process $($process.Id)")
    }

    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    while (-not $process.HasExited) {
        if ($Verbosity -ge 2) {
            Write-NewLines -Path $stdoutPath -Count ([ref] $stdoutCount) -ErrorStream $false
            Write-NewLines -Path $stderrPath -Count ([ref] $stderrCount) -ErrorStream $true
        }
        if ($stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
            $timedOut = $true
            break
        }
        Start-Sleep -Milliseconds 500
        $process.Refresh()
    }

    if ($timedOut) {
        [Console]::Error.WriteLine(
            "PSCAD runner exceeded the configured timeout of $TimeoutSeconds seconds"
        )
        Stop-OwnedRunner -OwnerPath $ownerPath -OwnedRoot $LocalCase
        Stop-EMTDC -CaseDirectory $LocalCase
        $exitCode = 124
    } else {
        $process.WaitForExit()
        if (Test-Path -LiteralPath $exitPath -PathType Leaf) {
            $recordedExit = (Get-Content -LiteralPath $exitPath -Raw).Trim()
            if (-not [int]::TryParse($recordedExit, [ref] $exitCode)) {
                [Console]::Error.WriteLine(
                    "PSCAD runner wrote an invalid exit code: $recordedExit"
                )
                $exitCode = 1
            }
        } else {
            [Console]::Error.WriteLine("PSCAD runner did not write an exit code")
            $exitCode = 1
        }
        if ($Verbosity -ge 2) {
            [Console]::Out.WriteLine(
                "PSCAD runner process $($process.Id) exited with code $exitCode"
            )
        }
    }

    if ($Verbosity -ge 2) {
        Write-NewLines -Path $stdoutPath -Count ([ref] $stdoutCount) -ErrorStream $false
        Write-NewLines -Path $stderrPath -Count ([ref] $stderrCount) -ErrorStream $true
    }
} catch {
    [Console]::Error.WriteLine($_.Exception.ToString())
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-OwnedRunner -OwnerPath $ownerPath -OwnedRoot $LocalCase
    }
    $exitCode = 1
} finally {
    try {
        Stop-EMTDC -CaseDirectory $LocalCase
    } finally {
        try {
            if ($pscadOwned) {
                Stop-OwnedPSCAD -OwnerPath $pscadOwnerPath -GraceSeconds 10
            }
        } finally {
            Copy-Result -Source $result -Destination $sharedOutput
            Remove-Item -LiteralPath $ownerPath -Force -ErrorAction SilentlyContinue
        }
    }
}

if ($exitCode -eq 0) {
    Remove-DirectoryWithRetry -Path $LocalCase -BestEffort
}
exit $exitCode
