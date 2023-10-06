#Requires AutoHotkey v2.0

global AHK_V2_VERSION := "2.0.10.0", AHK_INSTALLDIR := "C:\Program Files\AutoHotkey", AHK_UNINSTALLER := AHK_INSTALLDIR "\UX\ui-uninstall.ahk",
    MSIX_BASEDIR := A_ScriptDir "\AutoHotkey-MSIX-base", MSIX_RELEASEDIR := A_ScriptDir "\AutoHotkey-MSIX-release",
    MAKEPRI_PATH := '"' A_ScriptDir '\Assets\makepri.exe"'
; Makepri.exe is usually located in "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\makepri.exe"

if A_Args.Length {
    ; Used to remove an empty AHK_INSTALLDIR folder which usually is in Program Files and requires admin access
    if A_Args[1] = "/deletedir" {
        DirDelete(A_Args[2])
        ExitApp
    }
}

Main()
Main() {
    RemoveOldAHK()
    DownloadLatestAutoHotkeyVersions()
    InstallAHKVersions()
    CopyFiles()
    PackageFolderToMSIX()
}

RemoveOldAHK() {
    if DirExist(AHK_INSTALLDIR) && FileExist(AHK_UNINSTALLER) {
        DebugPrint("Trying to remove old AHK folders")
        RunWait(A_AhkPath ' "' AHK_UNINSTALLER '"')
        endTime := A_TickCount + 30000
        While (A_TickCount < endTime && DirExist(AHK_INSTALLDIR)) {
            isEmpty := true
            Loop Files AHK_INSTALLDIR "\*.*" {
                isEmpty := false
                break
            }
            if isEmpty {
                RunWait('*RunAs "' A_AhkPath '" "' A_ScriptDir '\autoinstaller.ahk" /deletedir "' AHK_INSTALLDIR '"')
            } else 
                Sleep 200
        }
        if DirExist(AHK_INSTALLDIR) {
            ExitWithMsg("Unable to fully uninstall old AHK versions. Exiting...")
        }
    }
    DebugPrint("Old AHK folder removed")
}

InstallAHKVersions() {
    if DirExist(AHK_INSTALLDIR) && FileExist(AHK_INSTALLDIR "\AutoHotkeyU64.exe") && FileExist(AHK_INSTALLDIR "\v2\AutoHotkey64.exe")  {
        DebugPrint("AHK is already installed, skipping the installment...")
        return
    }
    Loop Files ".\*.exe" { ; Because of file naming, v1 comes before v2
        if !InStr(A_LoopFilePath, "setup")
            continue
        DebugPrint("Installing " A_LoopFileName)
        RunWait(A_LoopFilePath)
        lastFile := A_LoopFilePath
    }
    if !WinWaitActive("AutoHotkey Dash",,5) {
        ExitWithMsg("AHK v2 Dash failed to open. Exiting...")
    }
    WinClose("AutoHotkey Dash")
    global AHK_V2_VERSION := FileGetVersion(lastFile)
    DebugPrint("Extracted v2 version: " AHK_V2_VERSION)
    if !FileExist(AHK_INSTALLDIR "\AutoHotkeyU64.exe") || !FileExist(AHK_INSTALLDIR "\v2\AutoHotkey64.exe") {
        ExitWithMsg("Failed to find AHK v1 and v2 executables. Exiting...")
    }
    DebugPrint("AHK v1 and v2 successfully installed")
}

CopyFiles() {
    if DirExist(MSIX_RELEASEDIR) {
        DebugPrint("Removing old MSIX release folder")
        DirDelete(MSIX_RELEASEDIR, true)
    }
    DebugPrint("Copying base MSIX folder and all required extras")
    DirCopy(MSIX_BASEDIR, MSIX_RELEASEDIR)
    if DirExist(AHK_INSTALLDIR) && FileExist(AHK_INSTALLDIR "\UX\AutoHotkeyUX.exe")
        DirCopy(AHK_INSTALLDIR, MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey")

    ; Delete unnecessary exe files: AutoHotkeyUX, default AutoHotkey.exe, UIAccess versions
    FileDelete(MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\UX\AutoHotkeyUX.exe") ; Unused in the Store Edition
    FileDelete(MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\AutoHotkey.exe") ; Unused in the Store Edition
    FileDelete(MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\v2\AutoHotkey.exe") ; Unused in the Store Edition
    FileDelete(MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\v2\AutoHotkey64_UIA.exe") ; Unused in the Store Edition
    FileDelete(MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\v2\AutoHotkey32_UIA.exe") ; Unused in the Store Edition
    ; Copy AutoHotkeyShell over, which will act as runner for v1 and v2
    ShellName := FileExist(".\AutoHotkey.exe") ? ".\AutoHotkey.exe" : ".\Assets\AutoHotkeyShell.exe"
    FileCopy(ShellName, MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\v2\AutoHotkey.exe")
    ; Copy help file launchers over, which are necessary to avoid this MSIX from needing console application privileges
    FileCopy(".\Assets\LaunchHelpV1.ahk", MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\UX\LaunchHelpV1.ahk")
    FileCopy(".\Assets\LaunchHelpV2.ahk", MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\UX\LaunchHelpV2.ahk")
    ; Copy over the template script files for v1 and v2
    if FileExist(MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\UX\Templates\Minimal for v2.ahk")
        FileDelete(MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\UX\Templates\Minimal for v2.ahk")
    FileAppend('/*`n[NewScriptTemplate]`nDescription = Standard v2 Template`n*/`n' FileRead(MSIX_RELEASEDIR "\Assets\Minimal for v2.ahk"), MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\UX\Templates\Minimal for v2.ahk")
    FileAppend('/*`n[NewScriptTemplate]`nDescription = Standard v1 Template`n*/`n' FileRead(MSIX_RELEASEDIR "\Assets\Minimal for v1.ahk"), MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\UX\Templates\Minimal for v1.ahk")
    ; Modify ui-dash.ahk to apply registry defaults for HKCU. This is needed because if the package
    ; applied the defaults then they can't be written to afterwards... 
    inject := "
    (LTrim
        if ConfigRead("Dash", "FirstRun", "1") = 1
            ConfigWrite("0", "Dash", "FirstRun"), ConfigWrite("Minimal for v2", "New", "DefaultTemplate")

        class AutoHotkeyDashGui extends
    )"
    uidash := FileRead(MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\UX\ui-dash.ahk")
    uidash := StrReplace(uidash, "class AutoHotkeyDashGui extends", inject,, &count:=0, 1)
    if !count {
        ExitWithMsg("Failed to inject default registry settings to ui-dash.ahk. Exiting...")
    }
    FileDelete(MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\UX\ui-dash.ahk")
    FileAppend(uidash, MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\UX\ui-dash.ahk")
    if AHK_V2_VERSION {
        DebugPrint("Modifying manifest file for version update")
        manifest := FileRead(MSIX_RELEASEDIR "\AppxManifest.xml")
        manifest := RegExReplace(manifest, 'Version="[\d\.]+"', 'Version="' AHK_V2_VERSION '"', &count:=0, 1)
        if !count
            ExitWithMsg("Couldn't update manifest version to '" AHK_V2_VERSION "'. Exiting...")
        FileDelete(MSIX_RELEASEDIR "\AppxManifest.xml")
        FileAppend(manifest, MSIX_RELEASEDIR "\AppxManifest.xml")
    }
    DebugPrint("Modifying ui-launcherconfig.ahk (disable UIAccess)")
    launcherconfig := FileRead(MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\UX\ui-launcherconfig.ahk")
    launcherconfig := RegExReplace(launcherconfig, "(this\.AddCheckBox\('vUIA\d x\+m yp\+2)(', `"UI Access`"\))", "$1 Disabled$2", &count:=0)
    if (count != 2)
        ExitWithMsg("Couldn't disable UIAccess in ui-launcherconfig.ahk. Exiting...")
    FileDelete(MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\UX\ui-launcherconfig.ahk")
    FileAppend(launcherconfig, MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\UX\ui-launcherconfig.ahk")
}

PackageFolderToMSIX() {
    DebugPrint("Creating new resource files")
    ; https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-manual-conversion
    SavedWorkingDir := A_WorkingDir
    SetWorkingDir(MSIX_RELEASEDIR) ; Required for makepri.exe
    msg := RunWaitOutputStd(MAKEPRI_PATH ' createconfig /cf priconfig.xml /dq en-US')
    if !FileExist("priconfig.xml") {
        ExitWithMsg("Failed to create priconfig.xml with message:`n`n" msg "`n`nExiting...")
    }
    msg := RunWaitOutputStd(MAKEPRI_PATH ' new /pr "' MSIX_RELEASEDIR '" /cf "' MSIX_RELEASEDIR '\priconfig.xml"')
    SetWorkingDir(SavedWorkingDir)
    if !FileExist(MSIX_RELEASEDIR "\resources.pri")
        ExitWithMsg("Failed to create resources.pri with message:`n`n" msg "`n`nExiting...")
    DebugPrint("Packaging into MSIX")
    if FileExist(".\AutoHotkey-MSIX-release.msix")
        FileDelete(".\AutoHotkey-MSIX-release.msix")
    ; For some reason running this with RunWaitOutputStd fails
    RunWait('MSIXHeroCLI.exe pack --directory "' MSIX_RELEASEDIR '" --package "' A_ScriptDir "\AutoHotkey-MSIX-release-unsigned.msix")
    if !FileExist(".\AutoHotkey-MSIX-release-unsigned.msix") {
        ExitWithMsg("Failed to pack MSIX! Exiting...")
    }
    if FileExist(".\Assets\SignCert.pfx") {
        DebugPrint("Signing MSIX with certificate SignCert.pfx")
        ; MSIXHeroCLI.exe sign --file <path-to-pfx-file> [--password <certificate-password>] [--timestamp <timestamp-server-url>] [--increaseVersion Major|Minor|Build|Revision|None] [--noPublisherUpdate] <path1> [<path2> [<path3>...]]
        passwd := FileExist(".\Assets\SignCertPasswd.txt") ? Trim(FileRead(".\Assets\SignCertPasswd.txt")) : ""
        msg := RunWaitOutputStd('MSIXHeroCLI.exe sign --file "' A_ScriptDir '\Assets\SignCert.pfx" --password "' passwd '" --increaseVersion None --timestamp "http://time.certum.pl/" "' A_ScriptDir '\AutoHotkey-MSIX-release-unsigned.msix"')
        if msg {
            if InStr(msg, "Package signed successfully!") {
                FileMove(".\AutoHotkey-MSIX-release-unsigned.msix", ".\AutoHotkey-MSIX-release-signed.msix", 1)
                DebugPrint("Package signed successfully!")
            } else
                DebugPrint("MSIX signing failed: `n" msg "`n")
        } else
            DebugPrint("MSIX signing failed for an unknown reason")
    }
}

ExitWithMsg(msg) {
    MsgBox(msg)
    ExitApp
}
MaybeExitWithMsg(msg, opts, continueOpt) {
    if (MsgBox(msg, "Error", opts) = continueOpt)
        return
    else
        ExitApp
}
DebugPrint(msg, layer := 0) => OutputDebug((layer ? StrReplace(Format("{:" layer "}",""), " ", "---") : "") msg "`n")

DownloadLatestAutoHotkeyVersions() { ; based on DepthTrawler code from https://www.reddit.com/r/AutoHotkey/comments/15k4rqv/autohotkey_autoupdate_v2/
    ; Check if "www.autohotkey.com" is reachable and/or internet is accessible.
    InternetConnected := DllCall("wininet.dll\InternetCheckConnection",
        "Str", "https://www.autohotkey.com",
        "UInt", 1,
        "UInt", 0
    )
    if !InternetConnected {
        MaybeExitWithMsg("No internet connection detected and unable to download latest versions. Continue with local ones?", "YesNo", "Yes")
    }
    For version in ["1.1", "2.0"] {
        WinHttpRequest := ComObject("WinHttp.WinHttpRequest.5.1")
        WinHttpRequest.Open(
            "Get",
            "https://www.autohotkey.com/download/" version "/version.txt",
            true
        )
        WinHttpRequest.Send()
        WinHttpRequest.WaitForResponse()
        OnlineVersion := WinHttpRequest.ResponseText
        if !OnlineVersion || !RegExMatch(OnlineVersion, "\d\.\d{1,2}\.\d{1,2}") {
            MaybeExitWithMsg("Failed to get latest version for v" version ". Continue?", "YesNo", "Yes")
        }

        ; Download checksum
        WinHttpRequest.Open(
            "Get",
            "https://www.autohotkey.com/download/" version "/AutoHotkey_" OnlineVersion "_setup.exe.sha256",
            true
        )
        WinHttpRequest.Send()
        WinHttpRequest.WaitForResponse()
        VerificationChecksum := WinHttpRequest.ResponseText
    
        FilePath := A_ScriptDir "\AutoHotkey_" OnlineVersion "_setup.exe"
        Filename := RegExReplace(FilePath, ".*\\(.*)", "${1}")

        ; Check whether the install-file already exists and skip it if possible
        if FileExist(FilePath) && !VerifyChecksum(FilePath, VerificationChecksum)
            FileDelete(FilePath)

        if !FileExist(FilePath) {
            Download("https://www.autohotkey.com/download/" (version = "2.0" ? "ahk-v2.exe" : "ahk-install.exe"), FilePath)
            ; Ensure the file's checksum matches the reported verification checksum.
            if VerifyChecksum(FilePath, VerificationChecksum) {
                MaybeExitWithMsg('The downloaded file`'s checksum:`n"' Filename '"`ndoes not match the reported verification checksum.`nContinue anyway?', "YesNo", "Yes")
            }
            DebugPrint("AHK v" version " successfully downloaded")
        } else {
            DebugPrint("AHK v" version " already downloaded, skipping download...")
        }
    }
}

VerifyChecksum(FilePath, VerificationChecksum) {
        ; CertUtil standard output redirected to ".\checksum.tmp".
        StdOut := RunWaitOutputStd(A_ComSpec ' /c certutil -hashfile "' FilePath '" SHA256')
        if RegExMatch(StdOut, "i)(?<Checksum>[A-F0-9]{64})", &Match) {
            FileChecksum := Match.Checksum
        }
        return VerificationChecksum = FileChecksum
}

RunWaitOutputStd(cmd, workingDir := A_WorkingDir, outfile := "stdout.tmp") {
    RunWait(A_ComSpec ' /c ' (workingDir ? 'cd "' workingDir '" && ' : "") cmd ' > "' outfile '"')
    msg := ""
    if FileExist(outfile) {
        msg := FileRead(outfile)
        FileDelete(outfile)
    }
    return msg
}