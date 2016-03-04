# Copyright (c) .NET Foundation and contributors. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

$inputDir = "$PSScriptRoot\..\..\..\src\sharedframework\NETCoreApp\1.0.0"

. "$PSScriptRoot\..\..\..\scripts\common\_common.ps1"

$Stage0Dir = "$PSScriptRoot\..\..\..\.dotnet_stage0\Windows\cli\bin"

$MSIFakeRoot = "$OutputDir\msi\sharedframework\fakeroot"
$MSIObjRoot = "$OutputDir\msi\sharedframework\obj"

$DotnetMSIOutput = ""
$WixRoot = ""
$InstallFileswsx = "$MSIObjRoot\install-files.wxs"
$InstallFilesWixobj = "$MSIObjRoot\install-files.wixobj"

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

function PublishSharedFrameworkToFakeRoot
{
    mkdir "$MSIFakeRoot\NETCoreApp\1.0.0"

    & $Stage0Dir\dotnet.exe "publish" --output "$MSIFakeRoot\NETCoreApp\1.0.0" $inputDir
    rm "$MSIFakeRoot\NETCoreApp\1.0.0\1.0.0.exe"
    rm "$MSIFakeRoot\NETCoreApp\1.0.0\1.0.0.dll"
    rm "$MSIFakeRoot\NETCoreApp\1.0.0\1.0.0.pdb"
    mv "$MSIFakeRoot\NETCoreApp\1.0.0\1.0.0.deps" "$MSIFakeRoot\NETCoreApp\1.0.0\NETCoreApp.deps"
}

function RunHeat
{
    $result = $true
    pushd "$WixRoot"

    Write-Host Running heat..

    .\heat.exe dir `"$MSIFakeRoot`" `
    -nologo `
    -template fragment `
    -sreg -gg `
    -var var.SharedFrameworkSource `
    -cg InstallFiles `
    -srd `
    -dr SHAREDFRAMEWORKHOME `
    -out $InstallFileswsx | Out-Host

    if($LastExitCode -ne 0)
    {
        $result = $false
        Write-Host "Heat failed with exit code $LastExitCode."
    }

    popd
    return $result
}

function RunCandle
{
    $result = $true
    pushd "$WixRoot"

    Write-Host Running candle..
    $AuthWsxRoot =  Join-Path $RepoRoot "packaging\sharedframework\windows"

    .\candle.exe -nologo `
        -out "$MSIObjRoot\" `
        -dSharedFrameworkSource="$MSIFakeRoot" `
        -dMicrosoftEula="$RepoRoot\packaging\osx\resources\en.lproj\eula.rtf" `
        -dSharedFramework_Name="NETCoreApp" `
        -dSharedFramework_Version="1.0.0" `
        -arch x64 `
        -ext WixDependencyExtension.dll `
        "$AuthWsxRoot\sharedframework.wxs" `
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
    $CabCache = Join-Path $WixRoot "cabcache"

    .\light.exe -nologo -ext WixUIExtension -ext WixDependencyExtension -ext WixUtilExtension `
        -cultures:en-us `
        "$MSIObjRoot\sharedframework.wixobj" `
        "$MSIObjRoot\provider.wixobj" `
        "$MSIObjRoot\registrykeys.wixobj" `
        "$InstallFilesWixobj" `
        -out $SharedFrameworkMSIOutput | Out-Host

    if($LastExitCode -ne 0)
    {
        $result = $false
        Write-Host "Light failed with exit code $LastExitCode."
    }

    popd
    return $result
}

if(!(Test-Path $inputDir))
{
    throw "$inputDir not found"
}

if(!(Test-Path $PackageDir))
{
    mkdir $PackageDir | Out-Null
}

$SharedFrameworkMSIOutput = Join-Path $PackageDir "dotnet-sharedframework-win-x64.$env:DOTNET_CLI_VERSION.msi"

Write-Host "Creating dotnet MSI at $SharedFrameworkMSIOutput"

$WixRoot = AcquireWixTools

if([string]::IsNullOrEmpty($WixRoot))
{
    Exit -1
}

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

PublishSharedFrameworkToFakeRoot

if(-Not (RunHeat))
{
    Exit -1
}

if(-Not (RunCandle))
{
    Exit -1
}

if(-Not (RunLight))
{
    Exit -1
}

if(!(Test-Path $SharedFrameworkMSIOutput))
{
    throw "Unable to create the dotnet msi."
    Exit -1
}

Write-Host -ForegroundColor Green "Successfully created shared framework MSI - $SharedFrameworkMSIOutput"

$PublishScript = Join-Path $PSScriptRoot "..\..\..\scripts\publish\publish.ps1"
& $PublishScript -file $SharedFrameworkMSIOutput

exit $LastExitCode
