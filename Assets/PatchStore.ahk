#Requires AutoHotkey v2

if FileExist(".\ui-dash.ahk") {
    ; Replace running help files with a virtualized copy of hh.exe
    uidash := FileRead(".\ui-dash.ahk")
    needle := "Run(f)", inject := "Run(ROOT_DIR '\UX\hh.exe ' f)"
    uidash := StrReplace(uidash, needle, inject,, &count:=0)
    if count {
        try {
            FileDelete(".\ui-dash.ahk")
            FileAppend(uidash, ".\ui-dash.ahk")
            DebugPrint("Injected help files redirection in ui-dash.ahk")
        } catch {
            DebugPrint("Failed to write ui-dash.ahk")
        }
    } else
        DebugPrint("Couldn't redirect help files in ui-dash.ahk.")
}

if FileExist(".\ui-launcherconfig.ahk") {
    ; Disable UI Access checkboxes in ui-launcherconfig.ahk, because UIAccess is not available in the Store edition
    launcherconfig := FileRead(".\ui-launcherconfig.ahk")
    if RegExMatch(launcherconfig, "this\.AddCheckBox\('vUIA\d x\+m yp\+2', `"UI Access`"\)") {
        launcherconfig := RegExReplace(launcherconfig, "(this\.AddCheckBox\('vUIA\d x\+m yp\+2)(', `"UI Access`"\))", "$1 Disabled$2", &count:=0)
        if (count != 2)
            DebugPrint("Couldn't disable UIAccess in ui-launcherconfig.ahk.")
        else {
            try {
                FileDelete(".\ui-launcherconfig.ahk")
                FileAppend(launcherconfig, ".\ui-launcherconfig.ahk")
                DebugPrint("Disabled UIAccess in ui-launcherconfig.ahk.")
            } catch
                DebugPrint("Failed to write ui-launcherconfig.ahk")
        }
    } else
        DebugPrint("ui-launcherconfig.ahk had UIAccess already disabled, skipping.")
}

if FileExist(".\install.ahk") {
    ; Change GetExeInfo path argument, because otherwise the GetFileVersionInfoSize call will fail
    install := FileRead(".\install.ahk"), orig := install
    needle := 'exe := GetExeInfo(item.Path)', inject := 'exe := GetExeInfo(".\" item.Path)'
    if InStr(install, needle) {
        install := StrReplace(install, needle, inject,,, 1)
        DebugPrint("Injected into GetExeInfo in install.ahk")
    } else
        DebugPrint(InStr(install, inject) ? "install.ahk already has GetExeInfo changed" : "Failed to inject into GetExeInfo in install.ahk")

    ; Force UserInstall mode, because HKCU install dir can't be easily made default in other ways
    install := StrReplace(install, "this.UserInstall := false", "this.UserInstall := true")

    ; Do not create any new shortcuts
    needle := 'this.AddPostAction this.Create', inject := ';this.AddPostAction this.Create'
    install := RegExReplace(install, "(?<!;)this\.AddPostAction this\.Create", inject)

    ; Disable file type association changing
    needle := "this.AddFileTypeReg", inject := ";this.AddFileTypeReg"
    if InStr(install, needle) {
        install := StrReplace(install, needle, inject,,, 1)
        DebugPrint("Disabled this.AddFileTypeReg in install.ahk")
    } else
        DebugPrint(InStr(install, inject) ? "install.ahk already has AddFileTypeReg disabled" : "Failed to disable AddFileTypeReg in install.ahk")

    ; Run ui-dash.ahk but virtualized
    needle := "ShellRun this.Interpreter, 'UX\ui-dash.ahk', this.InstallDir", inject := "Run 'AutoHotkey.exe `"' this.InstallDir '\UX\ui-dash.ahk`"', this.InstallDir"
    if InStr(install, needle) {
        install := StrReplace(install, needle, inject,,, 1)
        DebugPrint("Replaced ShellRun ui-dash.ahk in install.ahk")
    } else
        DebugPrint(InStr(install, inject) ? "install.ahk already has ShellRun ui-dash.ahk replaced" : "Failed to replace ShellRun ui-dash.ahk in install.ahk")

    if (install != orig && install != "") {
        try {
            FileDelete(".\install.ahk")
            FileAppend(install, ".\install.ahk")
        } catch
            DebugPrint("Failed to write install.ahk")
    }
}

if FileExist(".\install-version.ahk") {
    ; Inject PatchStore.ahk to be ran after downloading new AHK version but before installing
    needle := "try localUX := inst.Hashes['UX\install.ahk']"
    inject := "
    (LTrim
        try if DirExist(inst.SourceDir '\UX') && FileExist(inst.InstallDir "\UX\PatchStore.ahk") {
            FileCopy(inst.InstallDir "\UX\PatchStore.ahk", inst.SourceDir '\UX\PatchStore.ahk')
            Run('AutoHotkey.exe "' inst.SourceDir '\UX\PatchStore.ahk"', inst.SourceDir '\UX')
        }
        
        try localUX := inst.Hashes['UX\install.ahk']
    )"
    installversion := FileRead(".\install-version.ahk")
    if InStr(installversion, needle) && !InStr(installversion, inject) {
        installversion := StrReplace(installversion, needle, inject,, &count:=0, 1)
        if !count {
            DebugPrint("Failed to inject PatchStore.ahk to install-version.ahk.")
        } else {
            try {
                FileDelete(".\install-version.ahk"), FileAppend(installversion, ".\install-version.ahk")
                DebugPrint("Injected PatchStore.ahk to install-version.ahk.")
            } catch
                DebugPrint("Failed to write install-version.ahk")
        }
    } else
        DebugPrint("install-version.ahk already has PatchStore.ahk injected, skipping.")
}

if FileExist(".\launcher.ahk") {
    ; Disable AHK update if cmd.exe is unavailable (eg S-mode)
    needle := "if downloadable := IsNumber(v)"
    inject := "
    (LTrim
        try downloadable := !RunWait(A_ComSpec " /c echo 1",, "Hide") ; RunWait returns 0 if successful, otherwise non-zero. This is a rudimentary check for S-mode and other restricted environments.
        catch
            downloadable := false
        if downloadable && downloadable := IsNumber(v)
    )"
    launcher := FileRead(".\launcher.ahk")
    if InStr(launcher, needle) && !InStr(launcher, inject) {
        launcher := StrReplace(launcher, needle, inject,, &count:=0, 1)
        if !count {
            DebugPrint("Failed to inject S-mode check to launcher.ahk.")
        } else {
            try {
                FileDelete(".\launcher.ahk"), FileAppend(launcher, ".\launcher.ahk")
                DebugPrint("Injected S-mode check to install-version.ahk.")
            } catch
                DebugPrint("Failed to inject S-mode check to launcher.ahk")
        }
    } else
        DebugPrint("launcher.ahk already has S-mode check injceted, skipping.")
}

; Not needed
if FileExist(".\reset-assoc.ahk")
    try FileDelete(".\reset-assoc.ahk")

InjectHashes(["UX\launcher.ahk", "UX\reset-assoc.ahk", "UX\ui-dash.ahk", "UX\ui-launcherconfig.ahk", "UX\install.ahk", "UX\install-version.ahk"], "..")


DebugPrint(msg, layer := 0) => OutputDebug((layer ? StrReplace(Format("{:" layer "}",""), " ", "---") : "") msg "`n")
InjectHashes(files, RootDir) {
    if !(DirExist(RootDir "\UX") && FileExist(RootDir "\UX\installed-files.csv") && (installedfiles := FileRead(RootDir "\UX\installed-files.csv"))) {
        DebugPrint("InjectHashes: RootDir or installed-files.csv not found", 1)
        return
    }
    originstalledfiles := installedfiles
    for filename in files {
        if !FileExist(RootDir "\" filename) {
            installedfiles := RegExReplace(installedfiles, '\w+,[^,]+,\Q"' filename '"\E,""\r?\n?',, &count:=0)
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
                exe := {Description:"", Version:A_AhkVersion}
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
