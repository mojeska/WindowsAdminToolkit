@{
    RootModule        = 'WindowsAdminToolkit.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '7c0b6d3e-5f2a-4c1e-9d8b-2a4e6f1c3b57'
    Author            = 'Jeff Rainey'
    Description       = 'Everyday checks for Windows Server and Active Directory admins: patch readiness, replication health, missing AD subnets and baseline hardening.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-PatchReadiness'
        'Get-ADReplicationHealth'
        'Get-ADSiteSubnetGap'
        'Test-ServerHardening'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('ActiveDirectory', 'WindowsServer', 'Patching', 'Hardening')
            LicenseUri = 'https://github.com/mojeska/WindowsAdminToolkit/blob/main/LICENSE'
            ProjectUri = 'https://github.com/mojeska/WindowsAdminToolkit'
        }
    }
}
