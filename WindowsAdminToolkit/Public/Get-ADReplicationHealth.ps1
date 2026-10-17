function Get-ADReplicationHealth {
    <#
    .SYNOPSIS
    Shows replication status for every domain controller and partner, worst first.

    .DESCRIPTION
    The PowerShell version of 'repadmin /replsummary'. One row per DC, partner and
    naming context, with the last success, consecutive failures and the last error.
    Rows that are failing or haven't replicated within -WarnHours are marked Healthy = $false.
    Needs the ActiveDirectory module (RSAT).

    .PARAMETER Scope
    Domain (default) or Forest.

    .PARAMETER WarnHours
    Treat a link as unhealthy if it hasn't replicated successfully in this many hours. Default 3.

    .PARAMETER UnhealthyOnly
    Only return the problem rows.

    .EXAMPLE
    Get-ADReplicationHealth -UnhealthyOnly | Format-Table Server, Partner, Partition, HoursSinceSuccess, Failures, LastError

    .EXAMPLE
    Get-ADReplicationHealth -Scope Forest | Export-Csv .\replication.csv -NoTypeInformation
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Domain', 'Forest')]
        [string]$Scope = 'Domain',

        [int]$WarnHours = 3,

        [switch]$UnhealthyOnly
    )

    Import-Module ActiveDirectory -ErrorAction Stop

    $now = Get-Date
    $metadata = Get-ADReplicationPartnerMetadata -Target * -Scope $Scope -PartnerType Inbound -ErrorAction Continue

    $rows = foreach ($m in $metadata) {
        $hours = if ($m.LastReplicationSuccess) { [math]::Round(($now - $m.LastReplicationSuccess).TotalHours, 1) } else { $null }

        # LastReplicationResult is a Win32 error code; 0 means success. Translate it so
        # the report says "The RPC server is unavailable" instead of 1722.
        $errorText = $null
        if ($m.LastReplicationResult -ne 0) {
            $errorText = '{0}: {1}' -f $m.LastReplicationResult, ([ComponentModel.Win32Exception][int]$m.LastReplicationResult).Message
        }

        [pscustomobject]@{
            Server            = ($m.Server -split '\.')[0]
            Partner           = ($m.Partner -replace '^CN=NTDS Settings,CN=([^,]+),.*$', '$1')
            Partition         = $m.Partition
            LastSuccess       = $m.LastReplicationSuccess
            HoursSinceSuccess = $hours
            Failures          = $m.ConsecutiveReplicationFailures
            LastError         = $errorText
            Healthy           = ($m.ConsecutiveReplicationFailures -eq 0 -and $null -ne $hours -and $hours -le $WarnHours)
        }
    }

    if ($UnhealthyOnly) { $rows = $rows | Where-Object { -not $_.Healthy } }

    $rows | Sort-Object Healthy, @{ Expression = 'Failures'; Descending = $true }, Server
}
