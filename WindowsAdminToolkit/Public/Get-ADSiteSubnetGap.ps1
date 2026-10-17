function Get-ADSiteSubnetGap {
    <#
    .SYNOPSIS
    Finds client IP addresses that don't belong to any AD subnet.

    .DESCRIPTION
    When a client's IP isn't covered by a subnet in AD Sites and Services, it can't be
    matched to a site. It may then log on against a DC in another site and get DFS
    referrals to remote file servers. Each DC records these clients in
    %SystemRoot%\debug\netlogon.log as NO_CLIENT_SITE. This reads that log from every DC
    and groups the addresses by /24, so you can see which subnets need adding.

    Reads \\DC\admin$, so you need admin rights on the domain controllers.

    .PARAMETER Server
    Domain controllers to check. Defaults to every DC in the current domain.

    .EXAMPLE
    Get-ADSiteSubnetGap | Format-Table

    .EXAMPLE
    # Detail for one suggested subnet
    Get-ADSiteSubnetGap | Where-Object SuggestedSubnet -eq '10.20.30.0/24' |
        Select-Object -ExpandProperty Clients
    #>
    [CmdletBinding()]
    param(
        [string[]]$Server
    )

    if (-not $Server) {
        Import-Module ActiveDirectory -ErrorAction Stop
        $Server = (Get-ADDomainController -Filter *).HostName
    }

    # Example line: 10/16 08:12:01 [1234] CONTOSO: NO_CLIENT_SITE: PC123 10.20.30.40
    $pattern = 'NO_CLIENT_SITE:\s+(?<client>\S+)\s+(?<ip>\d{1,3}(\.\d{1,3}){3})'

    $hits = foreach ($dc in $Server) {
        $log = "\\$dc\admin$\debug\netlogon.log"
        if (-not (Test-Path $log)) {
            Write-Warning "$dc - can't read $log"
            continue
        }
        foreach ($line in (Select-String -Path $log -Pattern $pattern)) {
            [pscustomobject]@{
                DC     = $dc
                Client = $line.Matches[0].Groups['client'].Value
                IP     = $line.Matches[0].Groups['ip'].Value
                When   = ($line.Line -split '\s+')[0..1] -join ' '
            }
        }
    }

    $hits |
        Group-Object { ($_.IP -split '\.')[0..2] -join '.' } |
        ForEach-Object {
            [pscustomobject]@{
                SuggestedSubnet = "$($_.Name).0/24"
                Hits            = $_.Count
                UniqueClients   = @($_.Group.Client | Sort-Object -Unique).Count
                SeenBy          = ($_.Group.DC | Sort-Object -Unique) -join ', '
                LastSeen        = ($_.Group.When | Sort-Object | Select-Object -Last 1)
                Clients         = @($_.Group | Sort-Object Client -Unique | Select-Object Client, IP)
            }
        } |
        Sort-Object Hits -Descending
}
