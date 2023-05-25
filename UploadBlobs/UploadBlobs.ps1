# initial configuration
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

# get github secrets
$script:gitHubSecrets = $env:secrets | ConvertFrom-Json

# secrets config
$DevOpsRelease = $gitHubSecrets.AZDEVOPSRELEASE
$DevOpsAccount = $gitHubSecrets.AZDEVOPSACCOUNT
$DevOpsContainer = $gitHubSecrets.AZDEVOPSCONTAINER

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

    # copy the blobs to new directory
    Write-Host -Object "Copying artifacts to blobs upload directory..."
    New-Item -Path $baseFolder -Name "blob-files" -ItemType Directory -Force | Out-Null
    Copy-Item -Path "$baseFolder\artifacts\*\*.app" -Destination "$baseFolder\blob-files" -Force

    # rename artifacts
    Write-Host -Object "`nRenaming artifacts for upload to blob storage..."
    $apps | ForEach-Object {
        $appname = $_
        $blobname = Get-ChildItem -Path "$baseFolder\blob-files\" | Where-Object {$_.Name -like "*$appname*"}
        $releaseversion = ($blobname.BaseName).Split('_') | Select-Object -Last 1
        Rename-Item -Path $blobname.FullName -NewName "$baseFolder\blob-files\$appname.$releaseversion.app" -Verbose
    }
    Write-Host -NoNewline -Object "`n"

    # upload artifacts to blob storage
    Get-ChildItem -Path "$baseFolder\blob-files\" | ForEach-Object {
        $uri = $uri = "https://$DevOpsAccount.blob.core.windows.net" + $DevOpsContainer + $_.Name + $DevOpsRelease
        Write-Host -Object "Uploading $($_.Name) to Azure Blob Storage..."
        Invoke-WebRequest -Uri $uri -Method Put -InFile $_.FullName -ContentType 'application/json' -Headers @{'Content-Type' = 'application/json'; 'x-ms-blob-type' = 'BlockBlob'}
    }

}
catch {
    OutputError -message $_.Exception.Message
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
    Write-Host -Object "Cleaning up inecta blobs directoriy..."
    Set-Location -Path "$baseFolder"
    Remove-Item -Path "$baseFolder\blob-files" -Recurse -Force -ErrorAction SilentlyContinue
}
