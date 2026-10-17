function Test-ServerHardening {
    <#
    .SYNOPSIS
    Checks servers for the hardening settings vulnerability scanners flag most often.

    .DESCRIPTION
    Report only, changes nothing. One row per server and check, with Pass, Fail or
    Default (not configured, so the OS default applies). The checks are the usual
    scanner findings that aren't fixed by patching:

      SMBv1 enabled            - should be off
      SMB signing (server)     - should be required
      TLS 1.0 / 1.1 (server)   - should be disabled in SCHANNEL
      LLMNR                    - should be off by policy
      NTLMv1 / LM              - LmCompatibilityLevel should be 5
      WDigest                  - must not cache plain-text credentials
      RDP NLA                  - Network Level Authentication should be required

    Test changes like TLS or SMB signing with application owners before rolling them
    out. They're the ones that break old apps and devices.

    .PARAMETER ComputerName
    Servers to check. Defaults to the local machine. Accepts pipeline input.

    .PARAMETER Credential
    Optional credential for remote servers.

    .EXAMPLE
    Test-ServerHardening -ComputerName app01, app02 | Where-Object Status -ne 'Pass' | Format-Table

    .EXAMPLE
    # Summary matrix: one row per server, one column per check
    Test-ServerHardening -ComputerName (Get-Content .\servers.txt) |
        Group-Object ComputerName |
        ForEach-Object {
            $row = [ordered]@{ Server = $_.Name }
            $_.Group | ForEach-Object { $row[$_.Check] = $_.Status }
            [pscustomobject]$row
        } | Format-Table
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [pscredential]$Credential
    )

    begin {
        $targets = [System.Collections.Generic.List[string]]::new()

        $check = {
            function Get-Reg ($Path, $Name) {
                (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
            }
            function Out-Check ($Check, $Value, $Status, $Fix) {
                [pscustomobject]@{ Check = $Check; Value = $Value; Status = $Status; Recommendation = $Fix }
            }

            # SMBv1
            $smb = Get-SmbServerConfiguration -ErrorAction SilentlyContinue
            Out-Check 'SMBv1' $smb.EnableSMB1Protocol `
                $(if ($smb.EnableSMB1Protocol) { 'Fail' } else { 'Pass' }) `
                'Set-SmbServerConfiguration -EnableSMB1Protocol $false'

            # SMB signing
            Out-Check 'SMBSigningRequired' $smb.RequireSecuritySignature `
                $(if ($smb.RequireSecuritySignature) { 'Pass' } else { 'Fail' }) `
                'GPO: Microsoft network server: Digitally sign communications (always) = Enabled'

            # TLS 1.0 / 1.1 server side
            foreach ($ver in '1.0', '1.1') {
                $base = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS $ver\Server"
                $enabled = Get-Reg $base 'Enabled'
                $status = if ($null -eq $enabled) { 'Default' } elseif ($enabled -eq 0) { 'Pass' } else { 'Fail' }
                Out-Check "TLS$($ver -replace '\.')Server" $enabled $status "Set $base\Enabled = 0 and DisabledByDefault = 1, then reboot"
            }

            # LLMNR
            $llmnr = Get-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' 'EnableMulticast'
            Out-Check 'LLMNR' $llmnr `
                $(if ($llmnr -eq 0) { 'Pass' } elseif ($null -eq $llmnr) { 'Default' } else { 'Fail' }) `
                'GPO: Computer > Admin Templates > Network > DNS Client > Turn off multicast name resolution = Enabled'

            # NTLM level
            $lm = Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'LmCompatibilityLevel'
            Out-Check 'LmCompatibilityLevel' $lm `
                $(if ($lm -eq 5) { 'Pass' } elseif ($null -eq $lm) { 'Default' } else { 'Fail' }) `
                'GPO: Network security: LAN Manager authentication level = Send NTLMv2 response only. Refuse LM & NTLM'

            # WDigest
            $wd = Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' 'UseLogonCredential'
            Out-Check 'WDigestCleartext' $wd `
                $(if ($wd -eq 1) { 'Fail' } elseif ($null -eq $wd) { 'Default' } else { 'Pass' }) `
                'Set UseLogonCredential = 0 (absent is safe on 2012 R2 and later)'

            # RDP NLA
            $nla = Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' 'UserAuthentication'
            Out-Check 'RdpNla' $nla `
                $(if ($nla -eq 1) { 'Pass' } else { 'Fail' }) `
                'GPO: Require user authentication for remote connections by using Network Level Authentication = Enabled'
        }
    }

    process {
        foreach ($c in $ComputerName) { $targets.Add($c) }
    }

    end {
        $local = $targets | Where-Object { $_ -in $env:COMPUTERNAME, 'localhost', '.' }
        $remote = $targets | Where-Object { $_ -notin $env:COMPUTERNAME, 'localhost', '.' }

        if ($local) {
            & $check | Select-Object @{ n = 'ComputerName'; e = { $env:COMPUTERNAME } }, *
        }
        if ($remote) {
            $params = @{ ComputerName = $remote; ScriptBlock = $check }
            if ($Credential) { $params.Credential = $Credential }
            Invoke-Command @params |
                Select-Object @{ n = 'ComputerName'; e = { $_.PSComputerName } }, Check, Value, Status, Recommendation
        }
    }
}
