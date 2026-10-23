# WindowsAdminToolkit

[![CI](https://github.com/mojeska/WindowsAdminToolkit/actions/workflows/ci.yml/badge.svg)](https://github.com/mojeska/WindowsAdminToolkit/actions/workflows/ci.yml)

Checks I'd run before a patch window or when AD starts acting up. Everything is
read-only: it reports, it doesn't change anything. Works in Windows PowerShell 5.1 and PowerShell 7.

| Function | What it tells you |
| --- | --- |
| `Get-PatchReadiness` | Which servers are unreachable, already waiting on a reboot, low on disk, or have stopped services |
| `Get-ADReplicationHealth` | Replication status for every DC and partner, worst first (like `repadmin /replsummary`) |
| `Get-ADSiteSubnetGap` | Client IPs missing from AD Sites and Services, found in each DC's `netlogon.log` |
| `Test-ServerHardening` | The common scanner findings patching doesn't fix: SMBv1, SMB signing, TLS 1.0/1.1, LLMNR, NTLMv1, WDigest, RDP NLA |

## Disclaimer

> [!WARNING]
> **Use at your own risk.** This module and its scripts are provided as-is, with no warranty or guarantee of any kind. The author accepts no liability for any damage, data loss, downtime or other problems that result from using them.
>
> Read and understand anything before you run it, do your own research, and test in a lab before using it in production. See the [MIT License](LICENSE) for the full terms.

## Getting started

### 1. Let PowerShell run the scripts

These scripts aren't code-signed. Windows blocks unsigned scripts downloaded from
the internet until you allow them. Allow scripts you've reviewed, for your account only:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

If you downloaded a ZIP instead of cloning, remove the "came from the internet" mark
before extracting, or `RemoteSigned` will still block the files:

```powershell
Unblock-File -Path .\WindowsAdminToolkit-main.zip
```

Read any script before you run it. More on execution policies:
[about_Execution_Policies](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_execution_policies).

### 2. Install the module

Clone (or extract) the repo and copy the module folder to your modules path:

```powershell
git clone https://github.com/mojeska/WindowsAdminToolkit.git
Copy-Item .\WindowsAdminToolkit\WindowsAdminToolkit "$HOME\Documents\WindowsPowerShell\Modules\" -Recurse   # 5.1
Copy-Item .\WindowsAdminToolkit\WindowsAdminToolkit "$HOME\Documents\PowerShell\Modules\" -Recurse          # 7.x
Import-Module WindowsAdminToolkit
Get-Command -Module WindowsAdminToolkit
```

Or just load it for one session without installing:

```powershell
Import-Module .\WindowsAdminToolkit\WindowsAdminToolkit\WindowsAdminToolkit.psd1
```

### 3. Prerequisites

- **Remote checks** use PowerShell remoting (WinRM), which is on by default on Windows Server. Turn it on elsewhere with `Enable-PSRemoting`.
- **The AD functions** need the ActiveDirectory module from RSAT:

  ```powershell
  # Windows Server
  Install-WindowsFeature RSAT-AD-PowerShell
  # Windows 10/11
  Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
  ```
- Run as an account with admin rights on the target servers (and on the DCs for `Get-ADSiteSubnetGap`, which reads `\\DC\admin$`).

### PowerShell resources

- [PowerShell documentation](https://learn.microsoft.com/powershell/): Microsoft Learn
- [PowerShell on GitHub](https://github.com/PowerShell/PowerShell): source and releases for PowerShell 7
- [PowerShell Gallery](https://www.powershellgallery.com/): Microsoft's public module repository (`Install-Module`)

## The functions

### Get-PatchReadiness

Run the day before patching. One row per server: reachable or not, pending reboot
(and why), free space on the system drive, automatic services that aren't running,
the last KB installed, and uptime. Servers that don't answer still get a row, so
nothing quietly drops off the list.

```powershell
Get-PatchReadiness -ComputerName app01, sql01, dc01 | Format-Table

# Every server in AD, to CSV
Get-ADComputer -Filter 'OperatingSystem -like "*Server*"' |
    Select-Object -ExpandProperty Name |
    Get-PatchReadiness |
    Export-Csv .\patch-readiness.csv -NoTypeInformation
```

### Get-ADReplicationHealth

Every inbound replication link in the domain or forest, with last success,
consecutive failures and the error translated to text (1722 becomes "The RPC server
is unavailable"). Links failing or quiet for more than 3 hours are marked unhealthy.

```powershell
Get-ADReplicationHealth -UnhealthyOnly |
    Format-Table Server, Partner, Partition, HoursSinceSuccess, Failures, LastError

Get-ADReplicationHealth -Scope Forest -WarnHours 12
```

### Get-ADSiteSubnetGap

When a client's IP isn't in any AD subnet, it can't be matched to a site. It logs on
against whichever DC answers and can get DFS referrals to file servers in another
site. Each DC logs those clients as `NO_CLIENT_SITE` in `netlogon.log`. This collects
them from every DC and groups them by /24, so you know which subnets to add.

```powershell
Get-ADSiteSubnetGap | Format-Table SuggestedSubnet, Hits, UniqueClients, SeenBy, LastSeen

# Then add the subnet and link it to the right site
New-ADReplicationSubnet -Name '10.20.30.0/24' -Site 'Irvine'
```

### Test-ServerHardening

Report only. Pass, Fail, or Default (not configured, so the OS default applies),
with the GPO or registry setting that fixes each finding. Test TLS and SMB signing
changes with app owners first. Those are the ones that break old apps and devices.

```powershell
Test-ServerHardening -ComputerName app01, app02 | Where-Object Status -ne 'Pass' | Format-Table

# Local machine
Test-ServerHardening
```

## Tests

Pester tests check that the module loads, every function has help and examples,
and PSScriptAnalyzer is clean. GitHub Actions runs them on every push.

```powershell
Install-Module Pester, PSScriptAnalyzer -Scope CurrentUser
Invoke-Pester ./Tests
```

## License

MIT
