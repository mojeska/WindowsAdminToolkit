function Get-PatchReadiness {
    <#
    .SYNOPSIS
    Checks whether servers are ready for a patch window.

    .DESCRIPTION
    Run it the day before patching. For each server it reports whether it's reachable,
    already waiting on a reboot, short on disk, or has automatic services that aren't
    running, plus the last update installed and how long it's been up.

    .PARAMETER ComputerName
    Servers to check. Accepts pipeline input, e.g. from Get-ADComputer.

    .PARAMETER MinFreeGB
    Flag the system drive when free space drops below this. Default 10 GB.

    .PARAMETER Credential
    Optional credential for the remote session.

    .EXAMPLE
    Get-PatchReadiness -ComputerName app01, sql01, dc01 | Format-Table

    .EXAMPLE
    Get-ADComputer -Filter 'OperatingSystem -like "*Server*"' |
        Select-Object -ExpandProperty Name |
        Get-PatchReadiness |
        Export-Csv .\patch-readiness.csv -NoTypeInformation
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'DNSHostName')]
        [string[]]$ComputerName,

        [int]$MinFreeGB = 10,

        [pscredential]$Credential
    )

    begin {
        $targets = [System.Collections.Generic.List[string]]::new()

        # Runs on each server. Kept self-contained so it works over WinRM.
        $check = {
            param($MinFreeGB)

            # Services set to Automatic that are normally stopped; not worth flagging.
            $benign = 'gupdate', 'gupdatem', 'edgeupdate', 'edgeupdatem', 'sppsvc', 'RemoteRegistry',
                      'MapsBroker', 'CDPSvc', 'tiledatamodelsvc', 'WbioSrvc', 'ShellHWDetection',
                      'BITS', 'wuauserv', 'TrustedInstaller', 'sacsvr', 'GoogleUpdaterService*'

            $pending = @()
            if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $pending += 'CBS' }
            if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $pending += 'WindowsUpdate' }
            $rename = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
            if ($rename.PendingFileRenameOperations) { $pending += 'FileRename' }

            $os   = Get-CimInstance Win32_OperatingSystem
            $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
            $freeGB = [math]::Round($disk.FreeSpace / 1GB, 1)

            $stopped = Get-CimInstance Win32_Service -Filter "StartMode='Auto' AND State<>'Running'" |
                Where-Object {
                    $name = $_.Name
                    -not ($benign | Where-Object { $name -like $_ })
                } |
                Select-Object -ExpandProperty Name

            $lastPatch = Get-HotFix -ErrorAction SilentlyContinue |
                Where-Object InstalledOn |
                Sort-Object InstalledOn -Descending |
                Select-Object -First 1

            [pscustomobject]@{
                PendingReboot = [bool]$pending
                RebootReason  = $pending -join ', '
                SystemFreeGB  = $freeGB
                LowDisk       = $freeGB -lt $MinFreeGB
                StoppedAuto   = $stopped -join ', '
                LastKB        = $lastPatch.HotFixID
                LastPatched   = $lastPatch.InstalledOn
                UptimeDays    = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 1)
            }
        }
    }

    process {
        foreach ($c in $ComputerName) { $targets.Add($c) }
    }

    end {
        $params = @{
            ComputerName = $targets
            ScriptBlock  = $check
            ArgumentList = $MinFreeGB
            ErrorAction  = 'SilentlyContinue'
            ErrorVariable = 'failed'
        }
        if ($Credential) { $params.Credential = $Credential }

        # One fan-out call instead of a loop: Invoke-Command runs the servers in parallel.
        $results = Invoke-Command @params

        foreach ($r in $results) {
            [pscustomobject]@{
                ComputerName  = $r.PSComputerName
                Online        = $true
                PendingReboot = $r.PendingReboot
                RebootReason  = $r.RebootReason
                SystemFreeGB  = $r.SystemFreeGB
                LowDisk       = $r.LowDisk
                StoppedAuto   = $r.StoppedAuto
                LastKB        = $r.LastKB
                LastPatched   = $r.LastPatched
                UptimeDays    = $r.UptimeDays
                Error         = $null
            }
        }

        # Anything that didn't answer still gets a row, so nothing silently drops off the report.
        # Only connection failures count; errors raised on a server that did answer are ignored here.
        $answered = @($results.PSComputerName)
        $unreachable = $failed | Where-Object {
            $_.Exception -is [System.Management.Automation.Remoting.PSRemotingTransportException] -and
            $answered -notcontains $_.TargetObject
        }
        foreach ($e in $unreachable) {
            [pscustomobject]@{
                ComputerName  = $e.TargetObject
                Online        = $false
                PendingReboot = $null
                RebootReason  = $null
                SystemFreeGB  = $null
                LowDisk       = $null
                StoppedAuto   = $null
                LastKB        = $null
                LastPatched   = $null
                UptimeDays    = $null
                Error         = $e.Exception.Message
            }
        }
    }
}
