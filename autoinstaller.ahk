#Requires AutoHotkey v2.0

global AHK_V2_VERSION := "2.0.18.0", AHK_INSTALLDIR := "C:\Program Files\AutoHotkey", AHK_UNINSTALLER := AHK_INSTALLDIR "\UX\ui-uninstall.ahk",
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
    DownloadAhk2Exe()
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
    Loop Files ".\*.exe" {
        if InStr(A_LoopFilePath, "setup") && InStr(A_LoopFilePath, "AutoHotkey")
            FileDelete(A_LoopFilePath)
    }
    DebugPrint("Old AHK install files removed")
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
    if !WinWaitActive("AutoHotkey Dash",,10) {
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
    if DirExist(AHK_INSTALLDIR) && FileExist(AHK_INSTALLDIR "\UX\AutoHotkeyUX.exe") && !FileExist(AHK_INSTALLDIR "\v2\AutoHotkeyV2.exe")
        DirCopy(AHK_INSTALLDIR, MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey", 1)

    ;for exe in ["upx.exe", "mpress.exe", "Ahk2Exe.exe"]
    for exe in ["Ahk2Exe.exe"]
        FileCopy(".\Assets\" exe, MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\Compiler\" exe, 1)

    FileCopy(".\Assets\hh.exe", MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\UX\hh.exe", 1)

    ; Delete unnecessary exe files: AutoHotkeyUX, default AutoHotkey.exe, UIAccess versions
    ;FileDelete(MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\UX\AutoHotkeyUX.exe") ; Unused in the Store Edition
    FileDelete(MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\AutoHotkey.exe") ; Unused in the Store Edition
    FileDelete(MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\v2\AutoHotkey.exe") ; Unused in the Store Edition
    ; Trying to use UIAccess results in error "The request is not supported."
    FileDelete(MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\v2\AutoHotkey64_UIA.exe") ; Unused in the Store Edition
    FileDelete(MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\v2\AutoHotkey32_UIA.exe") ; Unused in the Store Edition
    ; Copy AutoHotkeyShell over, which will act as runner for v1 and v2
    ShellName := FileExist(".\AutoHotkey.exe") ? ".\AutoHotkey.exe" : ".\Assets\AutoHotkeyShell.exe"
    FileCopy(ShellName, MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\v2\AutoHotkey.exe")
    FileCopy(MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\AutoHotkeyU64.exe", MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\AutoHotkeyV1.exe")
    FileCopy(MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\v2\AutoHotkey64.exe", MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\v2\AutoHotkeyV2.exe")
    ; Copy help file launchers over, which are necessary to avoid this MSIX from needing console application privileges
    FileCopy(".\Assets\LaunchHelpV1.ahk", MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\UX\LaunchHelpV1.ahk")
    FileCopy(".\Assets\LaunchHelpV2.ahk", MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\UX\LaunchHelpV2.ahk")
    ; Copy over the template script files for v1 and v2
    if FileExist(MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\UX\Templates\Minimal for v2.ahk")
        FileDelete(MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\UX\Templates\Minimal for v2.ahk")
    FileAppend('/*`n[NewScriptTemplate]`nDescription = Standard v2 Template`n*/`n' FileRead(MSIX_RELEASEDIR "\Assets\Minimal for v2.ahk"), MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\UX\Templates\Minimal for v2.ahk")
    FileAppend('/*`n[NewScriptTemplate]`nDescription = Standard v1 Template`n*/`n' FileRead(MSIX_RELEASEDIR "\Assets\Minimal for v1.ahk"), MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\UX\Templates\Minimal for v1.ahk")

    if AHK_V2_VERSION {
        DebugPrint("Modifying manifest file for version update")
        manifest := FileRead(MSIX_RELEASEDIR "\AppxManifest.xml")
        manifest := RegExReplace(manifest, 'Version="[\d\.]+"', 'Version="' AHK_V2_VERSION '"', &count:=0, 1)
        if !count
            ExitWithMsg("Couldn't update manifest version to '" AHK_V2_VERSION "'. Exiting...")
        FileDelete(MSIX_RELEASEDIR "\AppxManifest.xml")
        FileAppend(manifest, MSIX_RELEASEDIR "\AppxManifest.xml")
    }
    DebugPrint("Running PatchStore.ahk")
    FileCopy(".\Assets\PatchStore.ahk", MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\UX\PatchStore.ahk")
    RunWait('"' A_AhkPath '" "' MSIX_RELEASEDIR '\VFS\ProgramFilesX64\AutoHotkey\UX\PatchStore.ahk"', MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey\UX")
    InjectHashes(["v2\AutoHotkey.exe", "v2\AutoHotkeyV2.exe", "AutoHotkeyV1.exe", "UX\PatchStore.ahk", "UX\Templates\Minimal for v2.ahk", "UX\Templates\Minimal for v1.ahk", "UX\LaunchHelpV1.ahk", "UX\LaunchHelpV2.ahk"], MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey")
    ; Remove hashes for UIA versions
    InjectHashes(["v2\AutoHotkey32_UIA.exe", "v2\AutoHotkey64_UIA.exe"], MSIX_RELEASEDIR "\VFS\ProgramFilesX64\AutoHotkey")
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

InjectHashes(files, RootDir) {
    if !(DirExist(RootDir "\UX") && (installedfiles := FileRead(RootDir "\UX\installed-files.csv"))) {
        DebugPrint("InjectHashes: RootDir or installed-files.csv not found", 1)
        return
    }
    originstalledfiles := installedfiles
    for filename in files {
        if !FileExist(RootDir "\" filename) {
            installedfiles := RegExReplace(installedfiles, '\w+,[^,]+,\Q"' filename '"\E,"[^"]*"\r?\n?',, &count:=0)
            if !count
                DebugPrint("InjectHashes: failed to remove " filename, 1)
            continue
        }
        if !(hash := HashFile(RootDir "\" filename)) {
            DebugPrint("InjectHashes: failed to hash " filename, 1)
            continue
        }
        if InStr(installedfiles, filename) {
            installedfiles := RegExReplace(installedfiles, '\w+(,[^,]*,\Q"' filename '"\E,"[^"\r\n]*")', hash "$1", &count:=0)
            if !count
                DebugPrint("InjectHashes: failed to modify " filename, 1)
        } else {
            try ; Cache the file description for the launcher
                exe := GetExeInfo(RootDir "\" filename)
            catch
                exe := {Description:"", Version:AHK_V2_VERSION}
            installedfiles .= Format('{},{},"{}","{}"`r`n', Hash, exe.Version, filename, exe.Description)
        }
    }

    A_Clipboard := installedfiles "`r`n`r`n" originstalledfiles
    if (installedfiles != originstalledfiles) {
        FileDelete(RootDir "\UX\installed-files.csv")
        FileAppend(installedfiles, RootDir "\UX\installed-files.csv")
    }
}

GetExeInfo(exe) {
    if !(verSize := DllCall("version\GetFileVersionInfoSize", "str", exe, "uint*", 0, "uint"))
        || !DllCall("version\GetFileVersionInfo", "str", exe, "uint", 0, "uint", verSize, "ptr", verInfo := Buffer(verSize))
        throw OSError()
    prop := {Path: exe}
    static Properties := {
        Version: 'FileVersion',
        Description: 'FileDescription',
        ProductName: 'ProductName'
    }
    for propName, infoName in Properties.OwnProps()
        if DllCall("version\VerQueryValue", "ptr", verInfo, "str", "\StringFileInfo\040904b0\" infoName, "ptr*", &p:=0, "uint*", &len:=0)
            prop.%propName% := StrGet(p, len)
        else throw OSError()
    if InStr(exe, '_UIA')
        prop.Description .= ' UIA'
    prop.Version := RegExReplace(prop.Version, 'i)[a-z]{2,}\K(?=\d)|, ', '.') ; Hack-fix for erroneous version numbers (AutoHotkey_H v2.0-beta3-H...)
    return prop
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
        WinHttpRequest := ComObject("Msxml2.XMLHTTP")
        WinHttpRequest.Open(
            "Get",
            "https://www.autohotkey.com/download/" version "/version.txt",
            false
        )
        WinHttpRequest.Send()
        while WinHttpRequest.readyState != 4
            Sleep 100
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
        while WinHttpRequest.readyState != 4
            Sleep 100
        VerificationChecksum := WinHttpRequest.ResponseText
    
        FilePath := A_ScriptDir "\AutoHotkey_" OnlineVersion "_setup.exe"
        Filename := RegExReplace(FilePath, ".*\\(.*)", "${1}")

        ; Check whether the install-file already exists and skip it if possible
        if FileExist(FilePath) && !VerifyChecksum(FilePath, VerificationChecksum)
            FileDelete(FilePath)

        if !FileExist(FilePath) {
            Download("https://www.autohotkey.com/download/" (version = "2.0" ? "ahk-v2.exe" : "ahk-install.exe"), FilePath)
            ; Ensure the file's checksum matches the reported verification checksum.
            if !VerifyChecksum(FilePath, VerificationChecksum) {
                MaybeExitWithMsg('The downloaded file`'s checksum:`n"' Filename '"`ndoes not match the reported verification checksum.`nContinue anyway?' , "YesNo", "Yes")
            }
            DebugPrint("AHK v" version " successfully downloaded")
        } else {
            DebugPrint("AHK v" version " already downloaded, skipping download...")
        }
    }
}

DownloadAhk2Exe() {
    static TempFile := ".\temp.zip", TempFolder := ".\temp"
    if FileExist(TempFile)
        FileDelete(TempFile)
    if DirExist(TempFolder)
        DirDelete(TempFolder, 1)
    ;for target in [{repo:"UPX/UPX", ext:"64.zip", exe:"upx.exe"}, {repo:"AutoHotkey/Ahk2Exe", exe:"Ahk2Exe.exe"}, {url:"https://www.autohotkey.com/mpress/mpress.219.zip", exe:"mpress.exe"}] {
    for target in [{repo:"AutoHotkey/Ahk2Exe", exe:"Ahk2Exe.exe"}] {
        if target.HasOwnProp("repo") {
            try DownloadGithub(TempFile, target.repo, target.HasOwnProp("ext") ? target.ext : ".zip")
        } else {
            try Download target.url, TempFile
        }
        if !FileExist(TempFile)
            ExitWithMsg("Unable to download " target.exe)
        DirCopy(".\temp.zip", ".\temp")

        Loop Files ".\temp\*", "R"
            if A_LoopFileName = target.exe
                FileCopy(A_LoopFileFullPath, ".\Assets\" target.exe, 1)

        FileDelete(TempFile)
        DirDelete(TempFolder, 1)

        if !FileExist(".\Assets\" target.exe)
            ExitWithMsg("Unable to copy " target.exe " from temp folder")
    }
}

DownloadGithub(To, Repo, Ext := ".zip", Typ := "browser_download") {
	Req := ComObject("Msxml2.XMLHTTP")
	Req.open("GET", "https://api.github.com/repos/" Repo "/releases/latest", 0)
    Req.send()
    while req.readyState != 4
        sleep 100
	if (Req.status = 200) {	
        Res := Req.responseText, Type1 := "browser_download", Type2 := "zipball"
		while RegExMatch(Res,"i)`"" Typ "_url`":`"") {
            Res := RegExReplace(Res,"iU)^.+`"" Typ "_url`":`"")
			Url := RegExReplace(Res,"`".+$")
			if (!Ext || SubStr(url, -StrLen(Ext)) = Ext) {
                Download(Url, To)
                return Url
            }
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

; HashFile by Deo
; https://autohotkey.com/board/topic/66139-ahk-l-calculating-md5sha-checksum-from-file/
; Modified for AutoHotkey v2 by lexikos.
/*
HASH types:
1 - MD2
2 - MD5
3 - SHA
4 - SHA256
5 - SHA384
6 - SHA512
*/
HashFile(filePath, hashType:=2)
{
	static PROV_RSA_AES := 24
	static CRYPT_VERIFYCONTEXT := 0xF0000000
	static BUFF_SIZE := 1024 * 1024 ; 1 MB
	static HP_HASHVAL := 0x0002
	static HP_HASHSIZE := 0x0004
	
    switch hashType {
        case 1: hash_alg := (CALG_MD2 := 32769)
        case 2: hash_alg := (CALG_MD5 := 32771)
        case 3: hash_alg := (CALG_SHA := 32772)
        case 4: hash_alg := (CALG_SHA_256 := 32780)
        case 5: hash_alg := (CALG_SHA_384 := 32781)
        case 6: hash_alg := (CALG_SHA_512 := 32782)
        default: throw ValueError('Invalid hashType', -1, hashType)
    }
	
	f := FileOpen(filePath, "r")
    f.Pos := 0 ; Rewind in case of BOM.
    
    HCRYPTPROV() => {
        ptr: 0,
        __delete: this => this.ptr && DllCall("Advapi32\CryptReleaseContext", "Ptr", this, "UInt", 0)
    }
    
	if !DllCall("Advapi32\CryptAcquireContextW"
				, "Ptr*", hProv := HCRYPTPROV()
				, "Uint", 0
				, "Uint", 0
				, "Uint", PROV_RSA_AES
				, "UInt", CRYPT_VERIFYCONTEXT)
		throw OSError()
	
    HCRYPTHASH() => {
        ptr: 0,
        __delete: this => this.ptr && DllCall("Advapi32\CryptDestroyHash", "Ptr", this)
    }
    
	if !DllCall("Advapi32\CryptCreateHash"
				, "Ptr", hProv
				, "Uint", hash_alg
				, "Uint", 0
				, "Uint", 0
				, "Ptr*", hHash := HCRYPTHASH())
        throw OSError()
	
	read_buf := Buffer(BUFF_SIZE, 0)
	
	While (cbCount := f.RawRead(read_buf, BUFF_SIZE))
	{
		if !DllCall("Advapi32\CryptHashData"
					, "Ptr", hHash
					, "Ptr", read_buf
					, "Uint", cbCount
					, "Uint", 0)
			throw OSError()
	}
	
	if !DllCall("Advapi32\CryptGetHashParam"
				, "Ptr", hHash
				, "Uint", HP_HASHSIZE
				, "Uint*", &HashLen := 0
				, "Uint*", &HashLenSize := 4
				, "UInt", 0) 
        throw OSError()
		
    bHash := Buffer(HashLen, 0)
	if !DllCall("Advapi32\CryptGetHashParam"
				, "Ptr", hHash
				, "Uint", HP_HASHVAL
				, "Ptr", bHash
				, "Uint*", &HashLen
				, "UInt", 0 )
        throw OSError()
	
	loop HashLen
		HashVal .= Format('{:02x}', (NumGet(bHash, A_Index-1, "UChar")) & 0xff)
	
	return HashVal
}
