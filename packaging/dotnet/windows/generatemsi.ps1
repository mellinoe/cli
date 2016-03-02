# Copyright (c) .NET Foundation and contributors. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

. "$PSScriptRoot\..\..\..\scripts\common\_common.ps1"

$MSIFakeRoot = "$OutputDir\msi\host\fakeroot"
$MSIObjRoot = "$OutputDir\msi\host\obj"

$DotnetHostMSIOutput = ""
$WixRoot = ""

function AcquireWixTools
{
    $result = Join-Path $OutputDir WiXTools

    if(Test-Path "$result\candle.exe")
    {
        return $result
    }

    Write-Host Downloading Wixtools..
    New-Item $result -type directory -force | Out-Null
    # Download Wix version 3.10.2 - https://wix.codeplex.com/releases/view/619491
    Invoke-WebRequest -Uri https://wix.codeplex.com/downloads/get/1540241 -Method Get -OutFile $result\WixTools.zip

    Write-Host Extracting Wixtools..
    [System.IO.Compression.ZipFile]::ExtractToDirectory("$result\WixTools.zip", $result)

    if($LastExitCode -ne 0)
    {
        throw "Unable to download and extract the WixTools."
    }

    return $result
}

function MoveAndRenameCoreHost
{
    # CoreHost, when installed, should be called dotnet.exe
    Copy-Item $OutputDir\corehost\corehost.exe $MSIFakeRoot\dotnet.exe
}

function RunCandle
{
    $result = $true
    pushd "$WixRoot"

    Write-Host Running candle..
    $AuthWsxRoot =  Join-Path $RepoRoot "packaging\dotnet\windows"

    .\candle.exe -nologo `
        -out "$MSIObjRoot\" `
        -ext WixDependencyExtension.dll `
        -dDotnetSrc="$MSIFakeRoot" `
        -dMicrosoftEula="$RepoRoot\packaging\osx\resources\en.lproj\eula.rtf" `
        -dBuildVersion="$env:DOTNET_MSI_VERSION" `
        -dDisplayVersion="$env:DOTNET_CLI_VERSION" `
        -arch x64 `
        "$AuthWsxRoot\dotnet.wxs" `
        "$AuthWsxRoot\provider.wxs" `
        "$AuthWsxRoot\registrykeys.wxs" `
        $InstallFileswsx | Out-Host

    if($LastExitCode -ne 0)
    {
        $result = $false
        Write-Host "Candle failed with exit code $LastExitCode."
    }

    popd
    return $result
}

function RunLight
{
    $result = $true
    pushd "$WixRoot"

    Write-Host Running light..

    .\light.exe -nologo `
        -ext WixUIExtension.dll `
        -ext WixDependencyExtension.dll `
        -ext WixUtilExtension.dll `
        -cultures:en-us `
        "$MSIObjRoot\dotnet.wixobj" `
        "$MSIObjRoot\provider.wixobj" `
        "$MSIObjRoot\registrykeys.wixobj" `
        -out $DotnetHostMSIOutput | Out-Host

    if($LastExitCode -ne 0)
    {
        $result = $false
        Write-Host "Light failed with exit code $LastExitCode."
    }

    popd
    return $result
}

if(!(Test-Path $PackageDir))
{
    mkdir $PackageDir | Out-Null
}

$DotnetHostMSIOutput = Join-Path $PackageDir "dotnet-host-win-x64.$env:DOTNET_CLI_VERSION.msi"

Write-Host "Creating dotnet MSI at $DotnetLauncherMSIOutput"

$WixRoot = AcquireWixTools

if(!(Test-Path $MSIFakeRoot))
{
    mkdir $MSIFakeRoot | Out-Null
}

Remove-Item -Recurse "$MSIFakeRoot\*"

if(!(Test-Path $MSIObjRoot))
{
    mkdir $MSIObjRoot | Out-Null
}

Remove-Item -Recurse "$MSIObjRoot\*"

if([string]::IsNullOrEmpty($WixRoot))
{
    Exit -1
}

MoveAndRenameCoreHost

if(-Not (RunCandle))
{
    Exit -1
}

if(-Not (RunLight))
{
    Exit -1
}

if(!(Test-Path $DotnetHostMSIOutput))
{
    throw "Unable to create the dotnet host msi."
    Exit -1
}

Write-Host -ForegroundColor Green "Successfully created dotnet host MSI - $DotnetHostMSIOutput"

$PublishScript = Join-Path $PSScriptRoot "..\..\..\scripts\publish\publish.ps1"
& $PublishScript -file $DotnetHostMSIOutput

exit $LastExitCode
