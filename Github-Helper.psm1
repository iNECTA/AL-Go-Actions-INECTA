function Get-dependencies {
    Param(
        $probingPathsJson,
        $token,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $saveToPath = (Join-Path $ENV:GITHUB_WORKSPACE "dependencies"),
        [string] $mask = "-Apps-"
    )

    if (!(Test-Path $saveToPath)) {
        New-Item $saveToPath -ItemType Directory | Out-Null
    }

    Write-Host "Getting all the artifacts from probing paths"
    $downloadedList = @()
    $probingPathsJson | ForEach-Object {
        $dependency = $_

        if (-not ($dependency.PsObject.Properties.name -eq "repo")) {
            throw "AppDependencyProbingPaths needs to contain a repo property, pointing to the repository on which you have a dependency"
        }
        if (-not ($dependency.PsObject.Properties.name -eq "AuthTokenSecret")) {
            $dependency | Add-Member -name "AuthTokenSecret" -MemberType NoteProperty -Value $token
        }
        if (-not ($dependency.PsObject.Properties.name -eq "Version")) {
            $dependency | Add-Member -name "Version" -MemberType NoteProperty -Value "latest"
        }
        if (-not ($dependency.PsObject.Properties.name -eq "Projects")) {
            $dependency | Add-Member -name "Projects" -MemberType NoteProperty -Value "*"
        }
        if (-not ($dependency.PsObject.Properties.name -eq "release_status")) {
            $dependency | Add-Member -name "release_status" -MemberType NoteProperty -Value "release"
        }

        # TODO better error messages

        $repository = ([uri]$dependency.repo).AbsolutePath.Replace(".git", "").TrimStart("/")
        if ($dependency.release_status -eq "latestBuild") {

            # TODO it should check the branch and limit to a certain branch

            Write-Host "Getting artifacts from $($dependency.repo)"
            $artifacts = GetArtifacts -token $dependency.authTokenSecret -api_url $api_url -repository $repository -mask $mask
            if ($dependency.version -ne "latest") {
                $artifacts = $artifacts | Where-Object { ($_.tag_name -eq $dependency.version) }
            }    
                
            $artifact = $artifacts | Select-Object -First 1
            if ($artifact) {
                $download = DownloadArtifact -path $saveToPath -token $dependency.authTokenSecret -artifact $artifact
            }
            else {
                Write-Host -ForegroundColor Red "Could not find any artifacts that matches '*$mask*'"
            }
        }
        else {

            Write-Host "Getting releases from $($dependency.repo)"
            $releases = GetReleases -api_url $api_url -token $dependency.authTokenSecret -repository $repository
            if ($dependency.version -ne "latest") {
                $releases = $releases | Where-Object { ($_.tag_name -eq $dependency.version) }
            }

            switch ($dependency.release_status) {
                "release" { $release = $releases | Where-Object { -not ($_.prerelease -or $_.draft ) } | Select-Object -First 1 }
                "prerelease" { $release = $releases | Where-Object { ($_.prerelease ) } | Select-Object -First 1 }
                "draft" { $release = $releases | Where-Object { ($_.draft ) } | Select-Object -First 1 }
                Default { throw "Invalid release status '$($dependency.release_status)' is encountered." }
            }

            if (!($release)) {
                throw "Could not find a release that matches the criteria."
            }
                
            $projects = $dependency.projects
            if ([string]::IsNullOrEmpty($dependency.projects)) {
                $projects = "*"
            }

            $download = DownloadRelease -token $dependency.authTokenSecret -projects $projects -api_url $api_url -repository $repository -path $saveToPath -release $release -mask $mask
        }
        if ($download) {
            $downloadedList += $download
        }
    }
    
    return $downloadedList;
}

# this function handles the installation of github cli
function global:Install-GitHubCLI {

    param (

        [Parameter(Mandatory = $False)]
        [switch] $Update

    )

    # intitial variables
    $uri = "https://github.com/cli/cli/releases/latest/"
    $workdir = "C:\ProgramData\BcContainerHelper"

    # create directory
    New-Item -Path $workdir -ItemType Directory -Force | Out-Null

    # determine the latest release
    $web1 = Invoke-WebRequest -Uri $uri -MaximumRedirection 0 -Method Get -UseBasicParsing -ErrorAction SilentlyContinue
    $web2 = Invoke-WebRequest -Uri $uri -MaximumRedirection 1 -Method Get -UseBasicParsing -ErrorAction SilentlyContinue
    $ver1 = ((($web1.RawContent.Split("`r`n")) | Where-Object {$_ -like "Location*"}).Replace("Location: ", "").Split('/') | Select-Object -Last 1).Replace("v", "")
    $ver2 = $web2.Links.href | Where-Object {$_ -like "*$ver1*amd64*.zip"}
    $latestver = $ver1

    # determine the link to download
    $link = "https://github.com" + $ver2

    if ($Update) {
        if (Test-Path -Path "$workdir\gh-cli\bin\gh.exe" -PathType Leaf) {
        }
        else {
            Write-Host -ForegroundColor Yellow -Object "gh-cli installation not found!"
            return
        }
        Write-Host -Object "Checking installed and latest available version..."
        $currentver = ((&$workdir\gh-cli\bin\gh.exe --version | Select-Object -Last 1).Split('/') | Select-Object -Last 1).Replace("v", "")
        Write-Host -ForegroundColor Yellow -Object "Installed version: $currentver"
        Write-Host -ForegroundColor Yellow -Object "Available version: $latestver"
        if ($currentver -eq $latestver) {
            Write-Host -Object "Latest version already installed."
        }
        else {
            Write-Host -Object "Downloading the latest installer..."
            try {
                Invoke-WebRequest -Uri $link -Method Get -OutFile "$workdir\gh-cli.zip"
            }
            catch {
                Write-Warning -Message "Download failed!"
                return
            }
            Write-Host -Object "Removing the existing installation..."
            Remove-Item -Path "$workdir\gh-cli" -Recurse -Force
            Write-Host -Object "Installing the downloaded version..."
            New-Item -Path $workdir -Name "gh-cli" -ItemType Directory -Force | Out-Null
            Expand-Archive -Path "$workdir\gh-cli.zip" -DestinationPath "$workdir\gh-cli" -Force
            $currentver = ((&$workdir\gh-cli\bin\gh.exe --version | Select-Object -Last 1).Split('/') | Select-Object -Last 1).Replace("v", "")
            Write-Host -Object "Removing the downloaded installer..."
            Remove-Item -Path "$workdir\gh-cli.zip" -Force
            Write-Host -ForegroundColor Yellow -Object "Installed version: $currentver"
        }
        return
    }

    if (Test-Path -Path "$workdir\gh-cli\bin\gh.exe" -PathType Leaf) {
        Write-Host -Object "gh-cli already installed, checking installed and latest available version..."
        $currentver = ((&$workdir\gh-cli\bin\gh.exe --version | Select-Object -Last 1).Split('/') | Select-Object -Last 1).Replace("v", "")
        Write-Host -ForegroundColor Yellow -Object "Installed version: $currentver"
        Write-Host -ForegroundColor Yellow -Object "Available version: $latestver"
    }
    else {
        Write-Host -ForegroundColor Yellow -Object "gh-cli installation not found!"
        Write-Host -Object "Downloading the installer..."
        try {
            Invoke-WebRequest -Uri $link -Method Get -OutFile "$workdir\gh-cli.zip"
        }
        catch {
            Write-Warning -Message "Download failed!"
            return
        }
        Write-Host -Object "Installing..."
        New-Item -Path $workdir -Name "gh-cli" -ItemType Directory -Force | Out-Null
        Expand-Archive -Path "$workdir\gh-cli.zip" -DestinationPath "$workdir\gh-cli" -Force
        $currentver = ((&$workdir\gh-cli\bin\gh.exe --version | Select-Object -Last 1).Split('/') | Select-Object -Last 1).Replace("v", "")
        Write-Host -Object "Removing the downloaded installer..."
        Remove-Item -Path "$workdir\gh-cli.zip" -Force
        Write-Host -ForegroundColor Yellow -Object "Installed version: $currentver"
    }

}

function CreateGitHubRequestHeaders([string]$username, [string]$token) {
    Write-Host -Object "Generating GitHub API request headers..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $username, $token)))
    $headers = @{
        Authorization = "Basic $base64AuthInfo"
    }
    return $headers
}

function GetRestfulErrorResponse($exception) {
    $ret = ""
    if ($exception.Exception -and $exception.Exception.Response) {
        $result = $exception.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($result)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $ret = $reader.ReadToEnd()
        $reader.Close()
    }
    if ($ret -eq $null -or $ret.Trim() -eq "") {
        $ret = $exception.ToString()
    }
    return $ret
}

function SemVerObjToSemVerStr {
    Param(
        $semVerObj
    )

    try {
        $str = "$($semVerObj.Prefix)$($semVerObj.Major).$($semVerObj.Minor).$($semVerObj.Patch)"
        for ($i = 0; $i -lt 5; $i++) {
            $seg = $semVerObj."Addt$i"
            if ($seg -eq 'zzz') { break }
            if ($i -eq 0) { $str += "-$($seg)" } else { $str += ".$($seg)" }
        }
        $str
    }
    catch {
        throw "'$SemVerObj' cannot be recognized as a semantic version object (internal error)"
    }
}

function SemVerStrToSemVerObj {
    Param(
        [string] $semVerStr
    )

    $obj = New-Object PSCustomObject
    try {
        $prefix = ''
        $verstr = $semVerStr
        if ($semVerStr -like 'v*') {
            $prefix = 'v'
            $verStr = $semVerStr.Substring(1)
        }
        $version = [System.Version]"$($verStr.split('-')[0])"
        if ($version.Revision -ne -1) { throw "not semver" }
        $obj | Add-Member -MemberType NoteProperty -Name "Prefix" -Value $prefix
        $obj | Add-Member -MemberType NoteProperty -Name "Major" -Value ([int]$version.Major)
        $obj | Add-Member -MemberType NoteProperty -Name "Minor" -Value ([int]$version.Minor)
        $obj | Add-Member -MemberType NoteProperty -Name "Patch" -Value ([int]$version.Build)
        0..4 | ForEach-Object {
            $obj | Add-Member -MemberType NoteProperty -Name "Addt$_" -Value 'zzz'
        }
        $idx = $verStr.IndexOf('-')
        if ($idx -gt 0) {
            $segments = $verStr.SubString($idx + 1).Split('.')
            if ($segments.Count -ge 5) {
                throw "max. 5 segments"
            }
            0..($segments.Count - 1) | ForEach-Object {
                $result = 0
                if ([int]::TryParse($segments[$_], [ref] $result)) {
                    $obj."Addt$_" = [int]$result
                }
                else {
                    if ($segments[$_] -ge 'zzz') {
                        throw "Unsupported segment"
                    }
                    $obj."Addt$_" = $segments[$_]
                }
            }
        }
        $newStr = SemVerObjToSemVerStr -semVerObj $obj
        if ($newStr -cne $semVerStr) {
            throw "Not equal"
        }
    }
    catch {
        throw "'$semVerStr' cannot be recognized as a semantic version string (https://semver.org)"
    }
    $obj
}

function GetReleases {
    Param(
        [string] $token,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $repository = $ENV:GITHUB_REPOSITORY
    )

    Write-Host "Analyzing releases $api_url/repos/$repository/releases"
    $releases = @(Invoke-WebRequest -UseBasicParsing -Headers (GetHeader -token $token) -Uri "$api_url/repos/$repository/releases" | ConvertFrom-Json)
    if ($releases.Count -gt 1) {
        # Sort by SemVer tag
        try {
            $sortedReleases = $releases.tag_name | 
                ForEach-Object { SemVerStrToSemVerObj -semVerStr $_ } | 
                    Sort-Object -Property Major, Minor, Patch, Addt0, Addt1, Addt2, Addt3, Addt4 -Descending | 
                        ForEach-Object { SemVerObjToSemVerStr -semVerObj $_ } | ForEach-Object {
                            $tag_name = $_
                            $releases | Where-Object { $_.tag_name -eq $tag_name }
                        }
            $sortedReleases
        }
        catch {
            Write-Host -ForegroundColor red "Some of the release tags cannot be recognized as a semantic version string (https://semver.org)"
            Write-Host -ForegroundColor red "Using default GitHub sorting for releases"
            $releases
        }
    }
    else {
        $releases
    }
}

function GetHeader {
    param (
        [string] $token,
        [string] $accept = "application/json"
    )
    $headers = @{ "Accept" = $accept }
    if (![string]::IsNullOrEmpty($token)) {
        $headers["Authorization"] = "token $token"
    }

    return $headers
}

function GetReleaseNotes {
    Param(
        [string] $token,
        [string] $repository = $ENV:GITHUB_REPOSITORY,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $tag_name,
        [string] $previous_tag_name
    )
    
    Write-Host "Generating release note $api_url/repos/$repository/releases/generate-notes"

    $postParams = @{
        tag_name = $tag_name;
    } 
    
    if (-not [string]::IsNullOrEmpty($previous_tag_name)) {
        $postParams["previous_tag_name"] = $previous_tag_name
    }

    Invoke-WebRequest -UseBasicParsing -Headers (GetHeader -token $token) -Method POST -Body ($postParams | ConvertTo-Json) -Uri "$api_url/repos/$repository/releases/generate-notes" 
}

function GetLatestRelease {
    Param(
        [string] $token,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $repository = $ENV:GITHUB_REPOSITORY
    )
    
    Write-Host "Getting the latest release from $api_url/repos/$repository/releases/latest"
    try {
        Invoke-WebRequest -UseBasicParsing -Headers (GetHeader -token $token) -Uri "$api_url/repos/$repository/releases/latest" | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function DownloadRelease {
    Param(
        [string] $token,
        [string] $projects = "*",
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $repository = $ENV:GITHUB_REPOSITORY,
        [string] $path,
        [string] $mask = "-Apps-",
        $release
    )

    if ($projects -eq "") { $projects = "*" }
    Write-Host "Downloading release $($release.Name)"
    $headers = @{ 
        "Authorization" = "token $token"
        "Accept"        = "application/octet-stream"
    }
    $projects.Split(',') | ForEach-Object {
        $project = $_
        Write-Host "project '$project'"
        
        $release.assets | Where-Object { $_.name -like "$project$mask*.zip" } | ForEach-Object {
            Write-Host "$api_url/repos/$repository/releases/assets/$($_.id)"
            $filename = Join-Path $path $_.name
            Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri "$api_url/repos/$repository/releases/assets/$($_.id)" -OutFile $filename 
            return $filename
        }
    }
}       

function GetArtifacts {
    Param(
        [string] $token,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $repository = $ENV:GITHUB_REPOSITORY,
        [string] $mask = "-Apps-"
    )

    Write-Host "Analyzing artifacts"
    $artifacts = Invoke-WebRequest -UseBasicParsing -Headers (GetHeader -token $token) -Uri "$api_url/repos/$repository/actions/artifacts" | ConvertFrom-Json
    $artifacts.artifacts | Where-Object { $_.name -like "*$($mask)*" }
}

function DownloadArtifact {
    Param(
        [string] $token,
        [string] $path,
        $artifact
    )

    Write-Host "Downloading artifact $($artifact.Name)"
    $headers = @{ 
        "Authorization" = "token $token"
        "Accept"        = "application/vnd.github.v3+json"
    }
    $outFile = Join-Path $path "$($artifact.Name).zip"
    Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $artifact.archive_download_url -OutFile $outFile
    $outFile
}    
