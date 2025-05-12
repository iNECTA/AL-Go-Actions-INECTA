# initial configuration
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

# get github secrets
$script:gitHubSecrets = $env:secrets | ConvertFrom-Json
$script:envInput = $ENV:repoName + "/" + $ENV:envInput + ".json"

# secrets config
$DevOpsUser = $gitHubSecrets.AZDEVOPSUSER
$DevOpsToken = $gitHubSecrets.AZDEVOPSTOKEN

# git config
git config --global user.email "$($gitHubSecrets.AZDEVOPSUSER)@inecta.com"
git config --global user.name "$($gitHubSecrets.AZDEVOPSUSER)"

try {

    # import helper function and download bccontainerhelper
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $baseFolder = $ENV:GITHUB_WORKSPACE
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $baseFolder

    # get the algo settingsjson
    Write-Host -Object "`nParsing AL-Go-Settings.json..."
    $algosettingsjson = Get-Content -Path "$baseFolder\.github\AL-Go-Settings.json" | ConvertFrom-Json

    # cleanup the repo
    Get-ChildItem -Path $baseFolder -Exclude @(".AL-Go", ".github", "SUPPORT.md", "SECURITY.md", "README.md", "al.code-workspace", ".gitignore", "WriteEnviornmentFilesBackToMasterAfterPipelines.ps1") | Remove-Item -Recurse -Force

    # obtain the customer repository to parse the json
    Write-Host -Object "Obtaining customer repository..."
    Remove-Item -Path "$baseFolder\inecta-apps\customer-repo" -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -Path "$baseFolder\inecta-apps" -Name "customer-repo" -ItemType Directory -Force | Out-Null
    Set-Location -Path "$baseFolder\inecta-apps\customer-repo"
    $ENV:GIT_REDIRECT_STDERR = '2>&1'
    $customerrepo = $envInput.Split('/') | Select-Object -First 1
    $customerfile = $envInput.Split('/') | Select-Object -First 1 -Skip 1
    git clone ("https://$DevOpsUser%40inecta.com:" + $DevOpsToken + "@dev.azure.com/INECTA/PROJECTS/_git/" + $customerrepo)
    # set branch for testing purpose
    Set-Location -Path "$baseFolder\inecta-apps\customer-repo\$customerrepo"
    git switch "Environment-Staging"
    $envFile = Get-Content -Path "$baseFolder\inecta-apps\customer-repo\$customerrepo\Environment-Staging\$customerfile" | ConvertFrom-Json
    $envFile.Apps | ForEach-Object {"App: $($_.App); Branch: $($_.Branch); Tag: $($_.Tag)"}

    # load SCRIPTS repository also
    Set-Location -Path "$home\Desktop"
    git clone ("https://$DevOpsUser%40inecta.com:" + $DevOpsToken + "@dev.azure.com/INECTA/PROJECTS/_git/" + "SCRIPTS")

    # set loadsimp.config
    Write-Host -Object "Creating LoadSIMP.config..."
    Copy-Item -Path "$home\Desktop\SCRIPTS\LoadSIMP - SAMPLE.config" -Destination "$home\Desktop\SCRIPTS\LoadSIMP.config" -Force
    Write-Host -Object "Updating DevOpsToken in LoadSIMP.config..."
    (Get-Content -Path "$home\Desktop\SCRIPTS\LoadSIMP.config") -replace "^DevOpsToken=.*$", "DevOpsToken=$DevOpsToken" | Set-Content -Path "$home\Desktop\SCRIPTS\LoadSIMP.config" -Force
    Write-Host -Object "Updating DevOpsUser in LoadSIMP.config..."
    (Get-Content -Path "$home\Desktop\SCRIPTS\LoadSIMP.config") -replace "^Username=.*$", "DevOpsToken=$DevOpsUser" | Set-Content -Path "$home\Desktop\SCRIPTS\LoadSIMP.config" -Force

    # load scripts library
    $global:StoryNumber = $Null
    $filepath = "$ENV:ProgramData\BcContainerHelper\INECTA"
    New-Item -Path "$ENV:ProgramData" -Name "BcContainerHelper\INECTA" -ItemType Directory -Force | Out-Null
    "success" | Out-File -FilePath "$ENV:ProgramData\BcContainerHelper\INECTA\SIMPMgmtUpdate.log" -NoNewline -Force
    $ErrorActionPreference = "Continue"
    Set-Location -Path "$home\desktop\SCRIPTS"
    . "$home\Desktop\SCRIPTS\start.ps1"
    $ErrorActionPreference = "Stop"

  

    # run get-app
    $envFile.Apps | ForEach-Object {
        $jsonvalue = $_
        Get-App -simp $_.App -branch $_.Branch -Tag $_.Tag
        Move-Item -Path "$ENV:ProgramData\BcContainerHelper\INECTA\$($_.App)$($_.Branch)" -Destination "$baseFolder\inecta-apps\" -Force
        Write-Host -ForegroundColor Yellow -Object "Renumbering files..."
        $files = Get-ChildItem -Path "$baseFolder\inecta-apps\$($_.App)$($_.Branch)" -Include *.xml, *.json, *.al -Recurse
        foreach ($file in $files) {
        (Get-Content -Path $file.PSPath) | Foreach-Object {
                $_ -replace "3700", "5" `
                    -replace "3701", "6" `
                    -replace "3711", "6" `
            } | Set-Content -Path $file.PSPath
            #Write-Host -ForegroundColor Green -Object "File changed : $($file.Name)"
        }
    }
   
    

    # clean up .git folders
    $envFile.Apps | ForEach-Object {
        Write-Host -Object "Adding $($_.App)$($_.Branch)..."
        Remove-Item -Path "$baseFolder\inecta-apps\$($_.App)$($_.Branch)\.git" -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item -Path "$baseFolder\inecta-apps\$($_.App)$($_.Branch)" -Destination $baseFolder -Recurse -Force
    }
    
   

    # clean up repo
    Remove-Item -Path "$baseFolder\inecta-apps" -Recurse -Force -ErrorAction SilentlyContinue
    
    # update al-go-settings json
    Write-Host -Object "Updating AL-Go settings.json file apps..."
    
    # read the apps to list
    # $AppFolders = @($envFile.Apps | ForEach-Object {$($_.App + "/app") })
    #$AppFolders = ($envFile.Apps | ForEach-Object {$($_.App + "/app") }) -join ','
    $AppFolders = $envFile.Apps | ForEach-Object {$($_.App + $_.Branch + "/app")}
    $TestFolders = $envFile.Apps | ForEach-Object {$($_.App + $_.Branch + "/test")}

    
    # Write to the AL-GO/setting.JSON file
    $settingsJson = @{
        country = "us"
        appFolders = $AppFolders
        testFolders = $TestFolders
        testFolders = @()
        bcptTestFolders = @()
        enableUICop = $true
        enableCodeCop = $true
        enablePerTenantExtensionCop = $true
        alwaysBuildAllProjects = $false
        skipUpgrade = $true
    }
    $settingsJson | ConvertTo-Json -Depth 64 | Set-Content -Path "$baseFolder\.AL-Go\settings.json"
    
    # update al-go-settings json
    Write-Host -Object "Updating AL-Go-Settings.json file apps..."
    #$algosettingsjson | Add-Member -NotePropertyName appFolders -NotePropertyValue $($envFile.Apps | ForEach-Object {$($_.App + $_.Branch + "/app") }) -Force
    $algosettingsjson | Add-Member -NotePropertyName appFolders -NotePropertyValue (@($envFile.Apps | ForEach-Object {$($_.App + $_.Branch + "/app") })) -Force
    
    Write-Host -ForegroundColor Yellow -Object "Sending some message 1..$algosettingsjson.."

    $algosettingsjson | Add-Member -NotePropertyName versioningStrategy -NotePropertyValue $([System.Int32]15) -Force
    $algosettingsjson | Add-Member -NotePropertyName repoVersion -NotePropertyValue $((($ENV:envTag).Split('.') | Select-Object -First 2) -join '.') -Force
    $algosettingsjson | ConvertTo-Json -Depth 64 | Set-Content -Path "$baseFolder\.github\AL-Go-Settings.json"
    
    Write-Host -ForegroundColor Yellow -Object "Sending some message 2..$algosettingsjson.."

    # merge the changes to customer repository
    Set-Location -Path $baseFolder
    git add .
    git commit --message "app folders update" --quiet
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
