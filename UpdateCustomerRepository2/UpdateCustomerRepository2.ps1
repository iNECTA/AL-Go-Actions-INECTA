# initial configuration
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

# get github secrets
$script:gitHubSecrets = $env:secrets | ConvertFrom-Json
$script:envInput = $ENV:repoName + "/" + $ENV:envInput + ".json"
$script:envTag = $ENV:envTag

# secrets config
$DevOpsUser = $gitHubSecrets.AZDEVOPSUSER
$DevOpsToken = $gitHubSecrets.AZDEVOPSTOKEN
$algoauthcontext = $gitHubSecrets.AUTHCONTEXT | ConvertFrom-Json

# git config
git config --global user.email "$($gitHubSecrets.AZDEVOPSUSER)@inecta.com"
git config --global user.name "$($gitHubSecrets.AZDEVOPSUSER)"

try {

    # import helper function and download bccontainerhelper
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $baseFolder = $ENV:GITHUB_WORKSPACE
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $baseFolder

    # obtain the customer repository to write back json
    Write-Host -Object "Obtaining customer repository..."
    Remove-Item -Path "$baseFolder\inecta-apps\customer-repo" -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -Path "$baseFolder\inecta-apps" -Name "customer-repo" -ItemType Directory -Force | Out-Null
    Set-Location -Path "$baseFolder\inecta-apps\customer-repo"
    $ENV:GIT_REDIRECT_STDERR = '2>&1'
    $customerrepo = $envInput.Split('/') | Select-Object -First 1
    $customerfile = $envInput.Split('/') | Select-Object -First 1 -Skip 1
    git clone ("https://$DevOpsUser%40inecta.com:" + $DevOpsToken + "@dev.azure.com/INECTA/PROJECTS/_git/" + $customerrepo)
    Set-Location -Path "$baseFolder\inecta-apps\customer-repo\$customerrepo"
    git switch "Environment-Staging"
    Copy-Item -Path "$baseFolder\inecta-apps\customer-repo\$customerrepo\Environment-Staging\$customerfile" -Destination "$baseFolder\inecta-apps" -Force
    $defbranch = ((git branch --remotes --list '*/HEAD').Split('->').Trim() | Select-Object -Last 1)
    git switch $($defbranch.Replace("origin/", ""))

    # build bcauthcontext
    $bcauthcontext = New-BcAuthContext -clientID $algoauthcontext.ClientID -tenantID $algoauthcontext.TenantID -clientSecret $algoauthcontext.ClientSecret

    # get the installed extensions
    $installedexts = Get-BcInstalledExtensions -bcAuthContext $bcauthcontext -environment ALGODemo | Where-Object {$_.Publisher -ne "Microsoft" -and $_.isInstalled -eq $True} | Select-Object -Property displayName, publisher, versionMajor, versionMinor, versionBuild, versionRevision, isInstalled | ConvertTo-Json | % { [System.Text.RegularExpressions.Regex]::Unescape($_) }

    # set location and update the repo
    Set-Location -Path "$baseFolder\inecta-apps\customer-repo\$customerrepo"
    #$installedexts | Out-File -FilePath "$baseFolder\inecta-apps\customer-repo\$customerrepo\$customerrepo-$($customerfile.Replace('.json', ''))-$envTag.json"
    Move-Item -Path "$baseFolder\inecta-apps\$customerfile" -Destination "$baseFolder\inecta-apps\customer-repo\$customerrepo\" -Force
    git config user.name "CICDNonUserProcessing"
    git config user.email "CICDNonUserProcessing@inecta.com"
    git add .\$customerfile
    git commit -m "[skip ci]"
    git push

}
catch {
    OutputError -message $_.Exception.Message
    Write-Host -Object "Cleaning up inecta apps repository directories..."
    Set-Location -Path "$baseFolder"
    Remove-Item -Path "$baseFolder\inecta-apps" -Recurse -Force -ErrorAction SilentlyContinue
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
    Write-Host -Object "Cleaning up inecta apps repository directories..."
    Set-Location -Path "$baseFolder"
    Remove-Item -Path "$baseFolder\inecta-apps" -Recurse -Force -ErrorAction SilentlyContinue
}
