# initial configuration
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

# get github secrets
$script:gitHubSecrets = $env:secrets | ConvertFrom-Json

# secrets config
$DevOpsUser = $gitHubSecrets.AZDEVOPSUSER
$DevOpsToken = $gitHubSecrets.AZDEVOPSTOKEN

# git config
git config --global user.email "$($gitHubSecrets.AZDEVOPSUSER)@inecta.com"
git config --global user.name "$($gitHubSecrets.AZDEVOPSUSER)"

# determine release branch
$releasebranch2 = "TMP.REL." + $(Get-Date -Format "yy") + $("{0:d1}" -f ($(Get-Culture).Calendar.GetWeekOfYear((Get-Date), [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [DayOfWeek]::Monday)))

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

    # get the repositories and create cutoff beanches
    Remove-Item -Path "$baseFolder\inecta-apps" -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -Path $baseFolder -Name "inecta-apps" -ItemType Directory -Force | Out-Null
    Set-Location -Path "$baseFolder\inecta-apps"
    Write-Host -Object "Checking out apps repositories...`n"
    $ENV:GIT_REDIRECT_STDERR = '2>&1'
    $apps | ForEach-Object {
        git clone ("https://$DevOpsUser%40inecta.com:" + $DevOpsToken + "@dev.azure.com/INECTA/PROJECTS/_git/" + $_)
        if ($LASTEXITCODE -eq 128) {
            throw "Git cloning failed for $_!"
        }
        Write-Host -Object "Entering granule directory..."
        Set-Location -Path "$baseFolder\inecta-apps\$_"
        $defbranch = ((git branch --remotes --list '*/HEAD').Split('->').Trim() | Select-Object -Last 1)
        $releasebranches = @(git branch --remotes --list "*/$releasebranch2*")
        $suffix = $releasebranches | ForEach-Object {
            $_.Split('.') | Select-Object -Last 1
        }
        $suffix = ($suffix | Measure-Object -Maximum).Maximum + 1
        $suffix = '{0:d3}' -f [System.Int32]$suffix
        $releasebranch = $releasebranch2 + "." + $suffix
        $releaseversion = ([System.Version]$($(Get-Date -Format "yyyy.M.d") + "." + $($suffix))).ToString()
        if ((git branch --remotes --list).Split('/').Trim() -notcontains $releasebranch) {
            Write-Host -Object "Creating cutoff branch $releasebranch for $_..."
            git branch $releasebranch $defbranch --no-track
            git push -u origin $releasebranch
        }
        else {
            Write-Host -Object "Branch $releasebranch already exists for $_, skipping branch creation..."
        }
        git switch $releasebranch
        Write-Host -Object "Running conversion from 3x to 5x/6x..."
        # renumber files from 37x to 5x/6x
        Write-Host -ForegroundColor Yellow -Object "Renumbering files..."
        $files = Get-ChildItem -Path ".\app" -Include *.xml, *.json, *.al -Recurse
        foreach ($file in $files) {
        (Get-Content -Path $file.PSPath) | Foreach-Object {
                $_ -replace "3700", "5" `
                    -replace "3701", "6" `
                    -replace "3711", "6" `
            } | Set-Content -Path $file.PSPath
            #Write-Host -ForegroundColor Green -Object "File changed : $($file.Name)"
        }
        Write-Host -Object "Updating app.json file..."
        $appjson = (Get-Content -Path ".\app\app.json" -Raw) | ConvertFrom-Json
        #$appjson.dependencies | Where-Object {$_.publisher -like "inecta*"} | Foreach-Object {
        #    $_.version = $releaseversion
        #}
        #$appjson.version = $releaseversion
        $appjson | Add-Member -Name "showMyCode" -Value $False -MemberType "NoteProperty" -ErrorAction SilentlyContinue
        $appjson.showMyCode = $False
        $appjson | ConvertTo-Json -Depth 32 | Set-Content -Path ".\app\app.json" -Force
        git add --all
        git commit -m "renumbered files from 3x to 5x/6x"
        git push origin $releasebranch --force
        Set-Location -Path "$baseFolder\inecta-apps\"
        Write-Host -NoNewline -Object "`n"
    }
    $releaseversion | Out-File -FilePath "$baseFolder\inecta-apps\release.version" -Encoding utf8 -NoNewline -Force
    Set-Location -Path $baseFolder

}
catch {
    OutputError -message $_.Exception.Message
    Write-Host -Object "Cleaning up inecta apps repository directories..."
    Set-Location -Path "$baseFolder"
    Remove-Item -Path "$baseFolder\inecta-apps" -Recurse -Force -ErrorAction SilentlyContinue
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}
