#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]] $EntryPoint,
    [string] $BicepPath = 'bicep',
    [string] $HtmlConfig = (Join-Path $PSScriptRoot 'bicep-docs-html.json'),
    [switch] $NoRestore,
    [switch] $Check
)

$ErrorActionPreference = 'Stop'
$requiredVersion = '0.49.2'
$version = & $BicepPath --version
if ($LASTEXITCODE -ne 0 -or $version -notmatch "^Bicep CLI version $([regex]::Escape($requiredVersion))(?:\s|$)") {
    throw "Bicep CLI $requiredVersion is required. Received: $version"
}

$htmlConfigPath = (Resolve-Path -LiteralPath $HtmlConfig).ProviderPath
$temporaryDirectory = [IO.Directory]::CreateTempSubdirectory('bicep-docs-').FullName
$rendered = [System.Collections.Generic.List[object]]::new()
$destinations = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$restoreOptions = @()
if ($NoRestore) {
    $restoreOptions += '--no-restore'
}

try {
    foreach ($entry in $EntryPoint) {
        $source = Get-Item -LiteralPath $entry
        if ($source.PSIsContainer -or $source.Extension -ne '.bicep') {
            throw "Expected a Bicep entrypoint file: $entry"
        }

        $prefix = 'bicep'
        if ($source.BaseName -ne 'main') {
            $prefix = "$($source.BaseName).bicep"
        }
        $markdownName = "${prefix}_readme.md"
        $htmlName = "${prefix}_report.html"
        $markdownFile = Join-Path $temporaryDirectory "$($rendered.Count).md"
        $htmlFile = Join-Path $temporaryDirectory "$($rendered.Count).html"
        $valuesPath = Join-Path $source.DirectoryName 'bicep-docs-values.json'
        $valueOptions = @()
        if (Test-Path -LiteralPath $valuesPath -PathType Leaf) {
            $valueOptions += '--custom-template-value-file-path', $valuesPath
        }
        $valueOptions += '--custom-template-value', "sourceFile=$($source.Name)"
        $valueOptions += '--custom-template-value', "markdownFile=$markdownName"

        & $BicepPath docs generate $source.FullName --outfile $markdownFile @restoreOptions
        if ($LASTEXITCODE -ne 0) {
            throw "Bicep Markdown generation failed for $($source.FullName)."
        }
        & $BicepPath docs generate $source.FullName --outfile $htmlFile --config $htmlConfigPath @restoreOptions @valueOptions
        if ($LASTEXITCODE -ne 0) {
            throw "Bicep HTML generation failed for $($source.FullName)."
        }

        foreach ($output in @(
            @{ Name = $markdownName; File = $markdownFile }
            @{ Name = $htmlName; File = $htmlFile }
        )) {
            $destination = Join-Path $source.DirectoryName $output.Name
            if (-not $destinations.Add($destination)) {
                throw "Multiple entrypoints resolve to the same documentation path: $destination"
            }
            $rendered.Add(@{ Destination = $destination; File = $output.File })
        }
    }

    $stale = foreach ($output in $rendered) {
        $expected = [IO.File]::ReadAllText($output.File).Replace("`r`n", "`n")
        $actual = $null
        if ([IO.File]::Exists($output.Destination)) {
            $actual = [IO.File]::ReadAllText($output.Destination).Replace("`r`n", "`n")
        }
        if ($actual -cne $expected) {
            if ($Check) {
                $output.Destination
            }
            else {
                [IO.File]::WriteAllText($output.Destination, $expected)
                Write-Host "Updated $($output.Destination)"
            }
        }
    }
    if ($stale) {
        throw "Missing or stale Bicep documentation:`n$($stale -join "`n")`nRerun Update-BicepDocs.ps1 with the same entrypoints and omit -Check."
    }
    if ($Check) {
        Write-Host "Bicep documentation is current ($($rendered.Count) files)."
    }
}
finally {
    foreach ($file in Get-ChildItem -LiteralPath $temporaryDirectory -File) {
        Remove-Item -LiteralPath $file.FullName
    }
    Remove-Item -LiteralPath $temporaryDirectory
}
