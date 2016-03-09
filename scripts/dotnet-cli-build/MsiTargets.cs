﻿using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Runtime.InteropServices;
using Microsoft.DotNet.Cli.Build.Framework;
using Microsoft.Extensions.PlatformAbstractions;

using static Microsoft.DotNet.Cli.Build.Framework.BuildHelpers;

namespace Microsoft.DotNet.Cli.Build
{
    public class MsiTargets
    {
        private const string ENGINE = "engine.exe";

        private static string WixRoot
        {
            get
            {
                return Path.Combine(Dirs.Output, "WixTools");
            }
        }

        private static string SdkMsi { get; set; }

        private static string SdkBundle { get; set; }

        private static string SharedHostMsi { get; set; }

        private static string SharedFrameworkMsi { get; set; }

        private static string Engine { get; set; }

        private static string MsiVersion { get; set; }

        private static string CliVersion { get; set; }

        private static string Arch { get; } = CurrentArchitecture.Current.ToString();

        private static string Channel { get; set; }

        private static void AcquireWix(BuildTargetContext c)
        {
            if (File.Exists(Path.Combine(WixRoot, "candle.exe")))
            {
                return;
            }

            Directory.CreateDirectory(WixRoot);

            c.Info("Downloading WixTools..");
            // Download Wix version 3.10.2 - https://wix.codeplex.com/releases/view/619491
            Cmd("powershell", "-NoProfile", "-NoLogo",
                $"Invoke-WebRequest -Uri https://wix.codeplex.com/downloads/get/1540241 -Method Get -OutFile {WixRoot}\\WixTools.zip")
                    .Execute()
                    .EnsureSuccessful();

            c.Info("Extracting WixTools..");
            ZipFile.ExtractToDirectory($"{WixRoot}\\WixTools.zip", WixRoot);
        }

        [Target]
        [BuildPlatforms(BuildPlatform.Windows)]
        public static BuildTargetResult InitMsi(BuildTargetContext c)
        {
            SdkBundle = c.BuildContext.Get<string>("SdkInstallerFile");
            SdkMsi = Path.ChangeExtension(SdkBundle, "msi");
            Engine = Path.Combine(Path.GetDirectoryName(SdkBundle), ENGINE);

            SharedHostMsi = Path.ChangeExtension(c.BuildContext.Get<string>("SharedHostInstallerFile"), "msi");
            SharedFrameworkMsi = Path.ChangeExtension(c.BuildContext.Get<string>("SharedFrameworkInstallerFile"), "msi");

            var buildVersion = c.BuildContext.Get<BuildVersion>("BuildVersion");
            MsiVersion = buildVersion.GenerateMsiVersion();
            CliVersion = buildVersion.SimpleVersion;
            Channel = c.BuildContext.Get<string>("Channel");

            AcquireWix(c);
            return c.Success();
        }

        [Target(nameof(MsiTargets.InitMsi),
        nameof(GenerateDotnetSharedHostMsi),
        nameof(GenerateDotnetSharedFrameworkMsi),
        nameof(GenerateCliSdkMsi))]
        [BuildPlatforms(BuildPlatform.Windows)]
        public static BuildTargetResult GenerateMsis(BuildTargetContext c)
        {
            return c.Success();
        }

        [Target]
        [BuildPlatforms(BuildPlatform.Windows)]
        public static BuildTargetResult GenerateCliSdkMsi(BuildTargetContext c)
        {
            Cmd("powershell", "-NoProfile", "-NoLogo",
                Path.Combine(Dirs.RepoRoot, "packaging", "windows", "generatemsi.ps1"),
                Dirs.Stage2, SdkMsi, WixRoot, MsiVersion, CliVersion, Arch, Channel)
                    .Execute()
                    .EnsureSuccessful();
            return c.Success();
        }

        [Target(nameof(SharedFrameworkTargets.PublishSharedHost))]
        [BuildPlatforms(BuildPlatform.Windows)]
        public static BuildTargetResult GenerateDotnetSharedHostMsi(BuildTargetContext c)
        {
            string WixObjRoot = Path.Combine(Dirs.Output, "obj", "wix", "sharedhost");

            if (Directory.Exists(WixObjRoot))
            {
                Directory.Delete(WixObjRoot, true);
            }

            Directory.CreateDirectory(WixObjRoot);

            Cmd("powershell", "-NoProfile", "-NoLogo",
                Path.Combine(Dirs.RepoRoot, "packaging", "host", "windows", "generatemsi.ps1"),
                c.BuildContext.Get<string>("SharedHostPublishRoot"), SharedHostMsi, WixRoot, MsiVersion, CliVersion, Arch, WixObjRoot)
                    .Execute()
                    .EnsureSuccessful();
            return c.Success();
        }

        [Target(nameof(SharedFrameworkTargets.PublishSharedFramework))]
        [BuildPlatforms(BuildPlatform.Windows)]
        public static BuildTargetResult GenerateDotnetSharedFrameworkMsi(BuildTargetContext c)
        {
            string SharedFrameworkNuGetVersion = c.BuildContext.Get<string>("SharedFrameworkNugetVersion");

            string WixObjRoot = Path.Combine(Dirs.Output, "obj", "wix", "sharedframework");

            if (Directory.Exists(WixObjRoot))
            {
                Directory.Delete(WixObjRoot, true);
            }

            Directory.CreateDirectory(WixObjRoot);

            Cmd("powershell", "-NoProfile", "-NoLogo",
                Path.Combine(Dirs.RepoRoot, "packaging", "sharedframework", "windows", "generatemsi.ps1"),
                c.BuildContext.Get<string>("SharedFrameworkPublishRoot"), SharedFrameworkMsi, WixRoot, MsiVersion, SharedFrameworkTargets.SharedFrameworkName, SharedFrameworkNuGetVersion, Utils.GenerateGuidFromName($"{SharedFrameworkNuGetVersion}-{Arch}").ToString().ToUpper(), Arch, WixObjRoot)
                    .Execute()
                    .EnsureSuccessful();
            return c.Success();
        }


        [Target(nameof(MsiTargets.InitMsi))]
        [BuildPlatforms(BuildPlatform.Windows)]
        public static BuildTargetResult GenerateBundle(BuildTargetContext c)
        {
            Cmd("powershell", "-NoProfile", "-NoLogo",
                Path.Combine(Dirs.RepoRoot, "packaging", "windows", "generatebundle.ps1"),
                SdkMsi, SdkBundle, WixRoot, MsiVersion, CliVersion, Arch, Channel)
                    .EnvironmentVariable("Stage2Dir", Dirs.Stage2)
                    .Execute()
                    .EnsureSuccessful();
            return c.Success();
        }

        [Target(nameof(MsiTargets.InitMsi))]
        [BuildPlatforms(BuildPlatform.Windows)]
        public static BuildTargetResult ExtractEngineFromBundle(BuildTargetContext c)
        {
            Cmd($"{WixRoot}\\insignia.exe", "-ib", SdkBundle, "-o", Engine)
                    .Execute()
                    .EnsureSuccessful();
            return c.Success();
        }

        [Target(nameof(MsiTargets.InitMsi))]
        [BuildPlatforms(BuildPlatform.Windows)]
        public static BuildTargetResult ReattachEngineToBundle(BuildTargetContext c)
        {
            Cmd($"{WixRoot}\\insignia.exe", "-ab", Engine, SdkBundle, "-o", SdkBundle)
                    .Execute()
                    .EnsureSuccessful();
            return c.Success();
        }
    }
}
