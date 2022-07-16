# initial configuration
$ErrorActionPreference = "Stop"
$telemetryScope = $null
$bcContainerHelperPath = $null

# get github secrets
$script:gitHubSecrets = $env:secrets | ConvertFrom-Json

# secrets config
$ENV:GITHUB_TOKEN = $gitHubSecrets.GHTOKENWORKFLOW

try {

    # import helper function and download bccontainerhelper
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $baseFolder = $ENV:GITHUB_WORKSPACE
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $baseFolder

    # install & update github cli
    Write-Host -Object "Checking GitHub CLI installation...`n"
    $ghclibin = "C:\ProgramData\BcContainerHelper\gh-cli\bin\gh.exe"
    if (Test-Path -Path $ghclibin -PathType Leaf) {
        Install-GitHubCLI -Update
    }
    else {
        Install-GitHubCLI
    }

    # validate github authentication
    Write-Host -Object "`nValidating GitHub CLI authentication..."
    &$ghclibin auth status
    if (!($?)) {
        Write-Error -Message "GitHub CLI authentication failed."
        throw
    }

    # find the github username
    Clear-Variable -Name "ghcliuser" -Force -ErrorAction SilentlyContinue
    Write-Host -Object "Verifying GitHub CLI username..."
    &$ghclibin auth status *> "$ENV:TEMP\GITHUB_TOKEN.LOG"
    $ghcliuser = (Get-Content -Path "$ENV:TEMP\GITHUB_TOKEN.LOG" | Select-String "Logged in to").Line.Split() | Select-Object -Last 1 -Skip 1
    Remove-Item -Path "$ENV:TEMP\GITHUB_TOKEN.LOG" -Force -ErrorAction SilentlyContinue
    if ($null -eq $ghcliuser) {
        Write-Error -Message "Failed to determine GitHub CLI user name."
        throw
    }

    # git config
    git config --global user.email "$($ghcliuser)@inecta.com"
    git config --global user.name "$($ghcliuser)"

    Get-ChildItem -Path $ENV:GITHUB_WORKSPACE -Recurse

}
catch {
    OutputError -message $_.Exception.Message
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}
