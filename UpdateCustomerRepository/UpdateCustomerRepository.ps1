# initial configuration
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

try {

    # import helper function and download bccontainerhelper
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $baseFolder = $ENV:GITHUB_WORKSPACE
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $baseFolder

    # get the algo settingsjson
    Write-Host -Object "`nParsing AL-Go-Settings.json..."
    $algosettingsjson = Get-Content -Path "$baseFolder\.github\AL-Go-Settings.json" | ConvertFrom-Json

    # get the list of apps
    $apps = $algosettingsjson.appFolders -replace "/app", ""
    Write-Host -Object "List of apps: $($apps -join ",")"

    # add app folders to customer repository
    Write-Host -Object "`nAdding apps to customer repository..."
    $apps | ForEach-Object {
        Write-Host -Object "Adding $_..."
        Remove-Item -Path "$baseFolder\inecta-apps\$_\.git" -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item -Path "$baseFolder\inecta-apps\$_" -Destination $baseFolder -Recurse -Force
    }
    Write-Host -Object "`nAdding release.version file to customer repository..."
    Copy-Item -Path "$baseFolder\inecta-apps\release.version" -Destination $baseFolder -Force
    Remove-Item -Path "$baseFolder\inecta-apps" -Recurse -Force -ErrorAction SilentlyContinue

    # merge the changes to customer repository
    Set-Location -Path $baseFolder
    git add .
    git commit --message "app folders update" --quiet
    git push

}
catch {
    OutputError -message $_.Exception.Message
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
    Write-Host -Object "Cleaning up inecta apps repository directories..."
    Set-Location -Path "$baseFolder"
    Remove-Item -Path "$baseFolder\inecta-apps" -Recurse -Force -ErrorAction SilentlyContinue
}
