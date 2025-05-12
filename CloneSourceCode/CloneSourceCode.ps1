# initial configuration
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

# Add this function to sanitize version numbers
function Sanitize-VersionNumber {
    param (
        [string]$version
    )
    # Remove any non-numeric characters except periods
    return $version -replace "[^0-9.]", ""
}

# get github secrets
$script:gitHubSecrets = $env:secrets | ConvertFrom-Json
$script:envInput = $ENV:repoName + "/" + $ENV:envInput + ".json"

# secrets config
$DevOpsUser = $gitHubSecrets.AZDEVOPSUSER
$DevOpsToken = $gitHubSecrets.AZDEVOPSTOKEN

Write-Host -Object "Clone Source Code (v1.04)"

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

    # Encode the username and PAT for the Authorization header
    $authString = "${DevOpsUser}:${DevOpsToken}"
    
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($authString)
    $base64Auth = [System.Convert]::ToBase64String($bytes)
    
    # Construct the Git repository URL without credentials
    $gitRepoUrl = "https://dev.azure.com/INECTA/PROJECTS/_git/$customerrepo"
    
    Write-Host -Object "Cloning the repository: $gitRepoUrl..."
    
    # Perform the git clone with the extraheader
    git -c http.extraheader="Authorization: Basic $base64Auth" clone $gitRepoUrl
    
    # Verify the clone path exists after running the command
    $customerRepoPath = "$baseFolder\inecta-apps\customer-repo\$customerrepo"
    if (!(Test-Path -Path $customerRepoPath)) {
        throw "Error: Cloned path '$customerRepoPath' does not exist. Please verify the repository URL and credentials."
    }
    
    # Set branch for testing purposes only if cloning succeeds
    Set-Location -Path $customerRepoPath
    git switch "Environment-Staging"
    
    $envFile = Get-Content -Path "$baseFolder\inecta-apps\customer-repo\$customerrepo\Environment-Staging\$customerfile" | ConvertFrom-Json
    $envFile.Apps | ForEach-Object { "App: $($_.App); Branch: $($_.Branch); Tag: $($_.Tag)" }

    # load SCRIPTS repository also
    $gitRepoUrl = "https://dev.azure.com/INECTA/PROJECTS/_git/SCRIPTS"

    Set-Location -Path "$home\Desktop"

    Write-Host -Object "Cloning the repository: $gitRepoUrl..."
    
    # Perform the git clone with the extraheader
    git -c http.extraheader="Authorization: Basic $base64Auth" clone $gitRepoUrl
    
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
    Set-Location -Path "$home\desktop\SCRIPTS"; . ./Simpmgmt.ps1
    # TODO: Ben
    $ErrorActionPreference = "Stop"

    # run get-app
    $envFile.Apps | ForEach-Object {
        $jsonvalue = $_
        
        # Debug output of original values
        Write-Host "Original App: $($_.App), Branch: $($_.Branch), Tag: $($_.Tag)" -ForegroundColor Yellow
        
        # Pass branch and tag values as-is to Get-App, which clones correctly
        Get-App -simp $_.App -branch $_.Branch -Tag $_.Tag 
        
        # Move the folder - use the branch name exactly as provided 
        $sourceFolder = "$ENV:ProgramData\BcContainerHelper\INECTA\$($_.App)$($_.Branch)"
        $destinationFolder = "$baseFolder\inecta-apps\$($_.App)$($_.Branch)"
        
        Write-Host "Moving from: $sourceFolder to: $destinationFolder" -ForegroundColor Cyan
        Move-Item -Path $sourceFolder -Destination "$baseFolder\inecta-apps\" -Force
        
        Write-Host -ForegroundColor Yellow -Object "Renumbering files..."
        $files = Get-ChildItem -Path "$baseFolder\inecta-apps\$($_.App)$($_.Branch)" -Include *.xml, *.json, *.al -Recurse
        foreach ($file in $files) {
            (Get-Content -Path $file.PSPath) | Foreach-Object {
                $_ -replace "3700", "5" `
                    -replace "3701", "6" `
                    -replace "3711", "6" `
            } | Set-Content -Path $file.PSPath
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
    $AppFolders = $envFile.Apps | ForEach-Object { $($_.App + $_.Branch + "/app") }
    $TestFolders = @()
    
    # Write to the AL-GO/setting.JSON file
    $settingsJson = @{
        country                     = "us"
        artifact                    = "//25.5//" # TODO: remove hardcoding
        appFolders                  = $AppFolders
        testFolders                 = $TestFolders        
        bcptTestFolders             = @()
        enableUICop                 = $true
        enableCodeCop               = $true
        enablePerTenantExtensionCop = $true
        alwaysBuildAllProjects      = $false
        skipUpgrade                 = $true
        doNotRunTests               = $true
    }
    $settingsJson | ConvertTo-Json -Depth 64 | Set-Content -Path "$baseFolder\.AL-Go\settings.json"
    
    # update al-go-settings json
    Write-Host -Object "Updating AL-Go-Settings.json file apps..."
    $algosettingsjson | Add-Member -NotePropertyName appFolders -NotePropertyValue (@($envFile.Apps | ForEach-Object { $($_.App + $_.Branch + "/app") })) -Force
    
    Write-Host -ForegroundColor Yellow -Object "Configuring versioning strategy..."

    # *** KEY FIX: Sanitize the version number from envTag ***
    $originalEnvTag = $ENV:envTag
    Write-Host "Original envTag: $originalEnvTag" -ForegroundColor Cyan
    
    # Get the version parts
    $versionParts = $originalEnvTag.Split('.')
    $sanitizedVersionParts = @()
    
    # Sanitize each part of the version
    foreach ($part in $versionParts) {
        $sanitizedPart = $part -replace "[^0-9]", ""
        $sanitizedVersionParts += $sanitizedPart
    }
    
    # Reconstruct the version with at least 2 parts
    $sanitizedVersion = ($sanitizedVersionParts | Select-Object -First 2) -join "."
    
    Write-Host "Sanitized version: $sanitizedVersion" -ForegroundColor Green
    
    # Update settings with sanitized version
    $algosettingsjson | Add-Member -NotePropertyName versioningStrategy -NotePropertyValue $([System.Int32]15) -Force
    $algosettingsjson | Add-Member -NotePropertyName repoVersion -NotePropertyValue $sanitizedVersion -Force
    $algosettingsjson | ConvertTo-Json -Depth 64 | Set-Content -Path "$baseFolder\.github\AL-Go-Settings.json"
    
    Write-Host -ForegroundColor Green -Object "Successfully updated AL-Go-Settings.json"

    # Check and update app.json files to ensure versions are sanitized
    $envFile.Apps | ForEach-Object {
        $appFolder = "$baseFolder\$($_.App)$($_.Branch)"
        $appJsonPath = "$appFolder\app\app.json"
        
        if (Test-Path $appJsonPath) {
            Write-Host "Checking app.json in $appJsonPath" -ForegroundColor Yellow
            $appJson = Get-Content -Path $appJsonPath | ConvertFrom-Json
            
            # Check if version contains non-numeric characters
            if ($appJson.version -match "[^0-9.]") {
                Write-Host "Found non-numeric characters in version: $($appJson.version)" -ForegroundColor Red
                
                # Sanitize the version
                $appJson.version = Sanitize-VersionNumber -version $appJson.version
                Write-Host "Sanitized version: $($appJson.version)" -ForegroundColor Green
                
                # Save the updated app.json
                $appJson | ConvertTo-Json -Depth 32 | Set-Content -Path $appJsonPath -Force
                Write-Host "Updated app.json with sanitized version" -ForegroundColor Green
            }
            else {
                Write-Host "Version is already numeric: $($appJson.version)" -ForegroundColor Green
            }
        }
    }

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
