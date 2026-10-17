# Basic quality gates: the module loads, exports what the manifest says,
# every function has help with examples, and PSScriptAnalyzer is clean.

BeforeDiscovery {
    $moduleDir = Join-Path $PSScriptRoot '..\WindowsAdminToolkit'
    $functions = (Get-ChildItem (Join-Path $moduleDir 'Public') -Filter *.ps1).BaseName
}

BeforeAll {
    $moduleDir = Join-Path $PSScriptRoot '..\WindowsAdminToolkit'
    $manifest  = Join-Path $moduleDir 'WindowsAdminToolkit.psd1'
    Import-Module $manifest -Force
}

Describe 'Module' {
    It 'has a valid manifest' {
        { Test-ModuleManifest $manifest -ErrorAction Stop } | Should -Not -Throw
    }
    It 'exports every public function' {
        $exported = (Get-Module WindowsAdminToolkit).ExportedFunctions.Keys
        foreach ($f in (Get-ChildItem (Join-Path $moduleDir 'Public') -Filter *.ps1).BaseName) {
            $exported | Should -Contain $f
        }
    }
}

Describe '<_>' -ForEach $functions {
    BeforeAll { $help = Get-Help $_ -Full }

    It 'has a synopsis' { $help.Synopsis | Should -Not -BeNullOrEmpty }
    It 'has a description' { $help.Description.Text | Should -Not -BeNullOrEmpty }
    It 'has at least one example' { @($help.Examples.Example).Count | Should -BeGreaterThan 0 }
}

Describe 'PSScriptAnalyzer' {
    It 'reports no warnings or errors' {
        $issues = Invoke-ScriptAnalyzer -Path $moduleDir -Recurse -Severity Warning, Error
        $issues | ForEach-Object { Write-Host "$($_.ScriptName):$($_.Line) $($_.RuleName) $($_.Message)" }
        $issues | Should -BeNullOrEmpty
    }
}
