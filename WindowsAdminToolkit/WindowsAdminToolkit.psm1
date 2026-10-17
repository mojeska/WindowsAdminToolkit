# Load every function in Public\ and export it.
$public = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter *.ps1
foreach ($file in $public) { . $file.FullName }
Export-ModuleMember -Function $public.BaseName
