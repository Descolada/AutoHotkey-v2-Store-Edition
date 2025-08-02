#include <iostream>
#include <stdio.h>
#include <stdlib.h>
#include <windows.h>
#include <shellapi.h>
#include <tchar.h>
#include <processenv.h>
#include <string.h>
#include <strsafe.h>
#include <string.h>
#include <tlhelp32.h>
#include <Psapi.h>

/*

    PURPOSE OF THIS PROGRAM

    This program is meant to essentially be a wrapper for AHK shell commands (open, edit, runas)
    and also a launcher for launcher.ahk.

    This means it should do the following:
    1) If opened with /edit flag it should read from the registry the default editor and run the
        script with that editor.
    2) If opened with /runas flag it should execute the script as an administrator
    3) If opened with /launch flag it should read from the registry the default AutoHotkey
        interpretor (or the launcher) and run the script with it.
        If the interpretor is the launcher, then the /launch flag should be injected into the argument
        list and closing of launcher should be waited. If the launcher is launched with /launch
        then it returns the PID of the script, so instead we take over the waiting for the launcher.
    4) If opened with/without /launch, all connected handles (eg StdOut, StdErr) should be forwarded
        to the opened program/script.
    5) If the WindowsApps folder executable was ran directly then that disables the virtualization
        of the file system and registry, in which case this program should run itself again from
        the symlink in the AppData folder, because the symlink contains the tokens for the
        app container virtualization. In that case this program launches itself with the /launch
        flag, gets the ExitCode (which is the PID for the running script), and waits for it to close.
        In this case the flow looks like this (supposing that the default launcher is launcher.ahk):
            1. WindowsAppsAHK.exe /args script.ahk /scriptargs   <--- primary run, wait for termination regardless of /launch
            2. AHK.exe /launch /args script.ahk /scriptargs      <--- virtualized run
            3. AHK64.exe launcher.ahk /launch /args script.ahk /scriptargs   <--- /launch didn't get passed, but was injected
            4. script.ahk /scriptargs

            Once 4 is reached, 3 will return PID of 4, then 2 will return PID of 3 (= 4), and 1 will wait for
            termination of 4.


    Desired functionality:
        1) Run with debug with only two processes open (this program, and the script)
        2) RunWait should work properly
        3) StdOut and StdErr should work properly
*/

typedef std::basic_string<TCHAR, std::char_traits<TCHAR>,
    std::allocator<TCHAR> > tstring;

enum StartFlag {
    OPEN = 0,
    RUNAS = 1,
    EDIT = 2,
    LAUNCH = 4,
    DISABLEVFS = 8,
    COMPILE = 16
};
DEFINE_ENUM_FLAG_OPERATORS(StartFlag)

LONG GetStringRegKey(HKEY hKey, const std::wstring& strValueName, std::wstring& strValue, const std::wstring& strDefaultValue)
{
    strValue = strDefaultValue;
    WCHAR szBuffer[512];
    DWORD dwBufferSize = sizeof(szBuffer);
    ULONG nError;
    nError = RegQueryValueExW(hKey, strValueName.c_str(), 0, NULL, (LPBYTE)szBuffer, &dwBufferSize);
    if (ERROR_SUCCESS == nError)
    {
        strValue = szBuffer;
    }
    return nError;
}

LONG ConcatArgs(std::wstring& result, LPWSTR* argv, int pNumArgs, int startFrom = 0) {
    for (int i = startFrom; i < pNumArgs; i++) {
        std::wstring arg = std::wstring(argv[i]);
        if (arg.find(L" ") != std::string::npos)
            result += L" \"" + arg + L"\"";
        else
            result += L" " + arg;
    }
    if (result.length() > 0) {
        result.erase(0, 1); // Remove leading space
    }
    return 1;
}

DWORD GetParentPID(DWORD pid) {
    HANDLE h = NULL;
    PROCESSENTRY32 pe = { 0 };
    DWORD ppid = 0;
    pe.dwSize = sizeof(PROCESSENTRY32);
    h = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (Process32First(h, &pe)) {
        do {
            if (pe.th32ProcessID == pid) {
                ppid = pe.th32ParentProcessID;
                break;
            }
        } while (Process32Next(h, &pe));
    }
    CloseHandle(h);
    return (ppid);
}

int GetProcessName(DWORD pid, TCHAR* fname, DWORD sz) {
    int e = 0;
    HANDLE h = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, pid);
    if (h) {
        if (GetModuleBaseName(h, NULL, fname, sz) == 0)
            e = GetLastError();
        CloseHandle(h);
    }
    else {
        e = GetLastError();
    }
    return (e);
}

BOOL FileExists(LPCTSTR szPath)
{
    DWORD dwAttrib = GetFileAttributes(szPath);

    return (dwAttrib != INVALID_FILE_ATTRIBUTES &&
        !(dwAttrib & FILE_ATTRIBUTE_DIRECTORY));
}

DWORD WaitForScript(StartFlag& flag, BOOL bWaitClose, HANDLE hChildProcess, HANDLE hChildThread) {
    // If /launch was injected into the arg list before this function is used (bWaitClose == true), 
    // then wait for the launcher to close. return lpExitCode which should be the PID of the launched script
    DWORD lpExitCode = 0;
    if (hChildProcess && bWaitClose) {
        WaitForSingleObject(hChildProcess, INFINITE);
        GetExitCodeProcess(hChildProcess, &lpExitCode);
        CloseHandle(hChildProcess);
    }
    if (hChildThread)
        CloseHandle(hChildThread);
    // if /launch was used on this call, return PID of script
    if (flag & LAUNCH) {
        return lpExitCode;
    }
    // otherwise /launch wasn't used, so wait until the script finishes running
    if (lpExitCode) {
        hChildProcess = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, false, lpExitCode);
        if (hChildProcess) {
            lpExitCode = 0;
            WaitForSingleObject(hChildProcess, INFINITE);
            if (!GetExitCodeProcess(hChildProcess, &lpExitCode))
                lpExitCode = GetLastError();
            CloseHandle(hChildProcess);
        }
        else
            lpExitCode = GetLastError();
    }
    else
        return E_FAIL;
    return lpExitCode;
}

int APIENTRY _tWinMain(_In_ HINSTANCE hInstance, _In_opt_ HINSTANCE hPrevInstance, _In_ LPTSTR lpCmdLine, _In_ int nCmdShow)
{
    LPCWSTR lpDefaultLauncher = L"\"C:\\Program Files\\AutoHotkey\\v2\\AutoHotkey64.exe\" \"C:\\Program Files\\AutoHotkey\\UX\\launcher.ahk\" \"%1\" %*";
    LPCWSTR lpDefaultEditor = L"\"C:\\Program Files\\AutoHotkey\\v2\\AutoHotkey64.exe\" \"C:\\Program Files\\AutoHotkey\\UX\\ui-editor.ahk\" \"%1\"";
    LPCWSTR lpDefaultCompiler = L"\"C:\\Program Files\\AutoHotkey\\Compiler\\Ahk2Exe.exe\" /gui /in \"%1\" %*";
    LPCWSTR lpVFSAutoHotkeyDir = _T("C:\\Program Files\\AutoHotkey");
    //MessageBox(0, lpCmdLine, L"lpCmdLine", MB_OK);
    int pNumArgs = 0;
    LPWSTR* argv = CommandLineToArgvW(lpCmdLine, &pNumArgs);

    STARTUPINFO si = { sizeof(si) };
    PROCESS_INFORMATION pi;
    DWORD lpExitCode = 0;
    DWORD childPID = 0;
    BOOL bInjectedLaunch = false;
    HRESULT hr;

    std::wstring result = L"";
    std::wstring exeArgs;
    std::wstring scriptArgs;

    std::wstring wstrRemainder;
    TCHAR szFileName[MAX_PATH];
    GetModuleFileName(NULL, szFileName, MAX_PATH);

    std::wstring parentDir = szFileName;
    size_t replacementLen = wcslen(_T("\\v2\\AutoHotkey.exe")), VFSAutoHotkeyDirLen = wcslen(lpVFSAutoHotkeyDir);
    parentDir.erase(parentDir.length() - replacementLen, replacementLen);

    StartFlag flag = OPEN;
    int startPoint = pNumArgs;

    // This reads and removes all AutoHotkeyShell-specific flags from the argument list, and finds
    // the position of the script filename
    for (int i = 0; i < pNumArgs; i++) {
        if (argv[i][0] != '/') {
            startPoint = i;
            break;
        } 
        else if ((lstrcmpi(argv[i], _T("/iLib")) == 0) || (lstrcmpi(argv[i], _T("/include")) == 0)) {
            i++; continue;
        } 
        else if (lstrcmpi(argv[i], _T("/RunWith")) == 0) { // Launcher.ahk specific. /which gets passed through without intervening
            i++; continue;
        }
        else if (lstrcmpi(argv[i], _T("/open")) == 0) {
            flag |= OPEN;
        }
        else if (lstrcmpi(argv[i], _T("/launch")) == 0) {
            flag |= LAUNCH;
        }
        else if (lstrcmpi(argv[i], _T("/runas")) == 0) {
            flag |= RUNAS;
        }
        else if (lstrcmpi(argv[i], _T("/edit")) == 0) {
            flag |= EDIT;
        }
        else if (lstrcmpi(argv[i], _T("/disablevfs")) == 0) {
            flag |= DISABLEVFS;
        }
        else if (lstrcmpi(argv[i], _T("/compile")) == 0) {
            flag |= COMPILE;
        }
        else {
            continue;
        }
        for (int j = i; j < pNumArgs; ++j)
            argv[j] = argv[j + 1];
        pNumArgs--; i--;
    }

    bool bVFSEnabled = FileExists(L"C:\\Program Files\\AutoHotkey\\v2\\AutoHotkey.exe");

    // If VFS isn't enabled then some functionalities won't work properly (e.g. reading from
    // "C:\Program Files\AutoHotkey". This happens when the program is ran directly from WindowsApps
    // instead of the AppData folder, because then the App Container Tokens won't be applied.
    // This workaround causes this program to run itself again from the AppData folder with all
    // arguments unchanged. Bypass this autorunning with /disablevfs flag. 
    if (!bVFSEnabled && !(flag & DISABLEVFS)) {
        wchar_t expandedPath[MAX_PATH];
        ExpandEnvironmentStrings(L"%LOCALAPPDATA%\\Microsoft\\WindowsApps\\AutoHotkey.exe", expandedPath, MAX_PATH);

        result = L"\"";
        result += expandedPath;
        result += L"\" ";
        if (!(flag & LAUNCH))
            result += L"/launch "; // Make the next run return the PID which we'll wait to close
        result += L"/disablevfs "; // Prevent running this again
        result += lpCmdLine;

        if (!FileExists(expandedPath)) {
            std::cout << L"Error! AutoHotkey wasn't found in the AppData folder!\n";
            return E_FAIL;
        }

        GetStartupInfo(&si);
        GetProcessInformation(GetCurrentProcess(), ProcessInformationClassMax, &pi, sizeof(pi));
        if (!CreateProcess(NULL,   // No module name (use command line)
            &result[0],        // Command line
            NULL,           // Process handle not inheritable
            NULL,           // Thread handle not inheritable
            TRUE,          // Set handle inheritance to TRUE
            0,              // Console window might be required if the script is passed with StdIn
            NULL,           // Use parent's environment block
            NULL,           // Use parent's starting directory 
            &si,            // Pointer to STARTUPINFO structure
            &pi) && !(flag & LAUNCH))           // Pointer to PROCESS_INFORMATION structure
            return GetLastError();
        return WaitForScript(flag, 1, pi.hProcess, pi.hThread);
    }
    else if (flag & RUNAS) { // Run this same exe with all arguments after "/runas" as admin
        wstrRemainder = L" /launch ";
        ConcatArgs(wstrRemainder, argv, pNumArgs);
        hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
        SHELLEXECUTEINFO ShExecInfo = { 0 };
        ShExecInfo.cbSize = sizeof(SHELLEXECUTEINFO);
        ShExecInfo.fMask = SEE_MASK_NOCLOSEPROCESS;
        ShExecInfo.hwnd = NULL;
        ShExecInfo.lpVerb = L"runas";
        ShExecInfo.lpFile = szFileName;
        ShExecInfo.lpParameters = wstrRemainder.c_str();
        ShExecInfo.lpDirectory = NULL;
        ShExecInfo.nShow = CREATE_NO_WINDOW;
        ShExecInfo.hInstApp = NULL;
        // if /launch is used then return PID, otherwise HR
        if (!ShellExecuteEx(&ShExecInfo) && !(flag & LAUNCH))
            return GetLastError();
        lpExitCode = WaitForScript(flag, 1, ShExecInfo.hProcess, NULL);
        CoUninitialize();
        return lpExitCode;
    }

    wchar_t emptyDefault[] = L"";
    LPWSTR scriptPath = (startPoint < pNumArgs) ? argv[startPoint] : emptyDefault;

    exeArgs = L""; scriptArgs = L"";
    ConcatArgs(exeArgs, argv, startPoint);
    ConcatArgs(scriptArgs, argv, pNumArgs, startPoint + 1);

    // Get default registry values for "edit" or "open" verbs
    HKEY hKey;
    std::wstring pvData = L"";
    if (flag & EDIT) {
        pvData = lpDefaultEditor;
        if (RegOpenKeyExW(HKEY_CLASSES_ROOT, _T("AutoHotkeyScript\\Shell\\edit\\command"),
            NULL, KEY_QUERY_VALUE, &hKey) == ERROR_SUCCESS) {
            GetStringRegKey(hKey, L"", pvData, lpDefaultEditor);
        }
    }
    else if (flag & COMPILE) {
        pvData = lpDefaultCompiler;
        if (RegOpenKeyExW(HKEY_CLASSES_ROOT, _T("AutoHotkeyScript\\Shell\\compile-gui\\command"),
            NULL, KEY_QUERY_VALUE, &hKey) == ERROR_SUCCESS) {
            GetStringRegKey(hKey, L"", pvData, lpDefaultCompiler);
        }
    }
    else {
        pvData = lpDefaultLauncher;
        if (RegOpenKeyExW(HKEY_CLASSES_ROOT, _T("AutoHotkeyScript\\Shell\\open\\command"),
            NULL, KEY_QUERY_VALUE, &hKey) == ERROR_SUCCESS) {
            GetStringRegKey(hKey, L"", pvData, lpDefaultLauncher);
        }
    }
    if (!pvData.length())
        pvData = lpDefaultLauncher;

    // If the default launcher.ahk is used but no /launch is in arguments, then add it to the args.
    // This is because this program will act as the launcher and wait for the launched script to terminate,
    // so launcher.ahk doesn't need to wait and consume resources.
    if ((pvData.find(L"AutoHotkey\\UX\\launcher.ahk") != std::string::npos) && (exeArgs.find(L"/launch") == std::string::npos)) {
        exeArgs += (exeArgs.length() ? L" /launch" : L"/launch");
        bInjectedLaunch = true;
    }

    // Replace %l and %L with %1
    size_t found = pvData.find(_T("\"%l\""));
    if (found != std::string::npos) {
        pvData.replace(found, 4, _T("\"%1\""));
    }
    found = pvData.find(_T("\"%L\""));
    if (found != std::string::npos) {
        pvData.replace(found, 4, _T("\"%1\""));
    }
    // Replace %1 with script path, preceded by exe arguments (eg /debug),
    // also taking into account that %1 might be surrounded by quotes.
    found = pvData.find(_T("%1"));
    if (found != std::string::npos) {
        if (exeArgs.length()) {
            std::wstring repl;
            if (wcsstr(scriptPath, _T(" "))) {
                repl = exeArgs + L" \"" + scriptPath + L"\"";
            } else {
                repl = exeArgs + L" " + scriptPath;
            }
            if (pvData[found - 1] == '\"')
                pvData.replace(found - 1, 4, repl);
            else
                pvData.replace(found, 2, repl);
        }
        else
            pvData.replace(found, 2, scriptPath);
    }
    else {
        pvData += L" " + exeArgs + L" " + scriptPath;
    }

    // Replace the remaining arguments
    found = pvData.find(_T("%*"));
    if (found != std::string::npos)
        pvData.replace(found, max(scriptArgs.length(), 2), scriptArgs.c_str());
    else
        pvData += L" " + scriptArgs;

    result += pvData.c_str();

    // Do some VFS redirection in case the actual path of the VFS is used.
    // In that case we need to replace all occurrences of the WindowsApps dir path with
    // "C:\Program Files\AutoHotkey". This is to ensure adherence to virtualization.
    //found = result.find(lpVFSAutoHotkeyDir);
    //while (found != std::string::npos) {
    //    result.replace(found, VFSAutoHotkeyDirLen, parentDir);
    //    found = result.find(lpVFSAutoHotkeyDir, found + parentDir.length());
    //}
    //found = result.find(parentDir);
    //while (found != std::string::npos) {
    //    result.replace(found, parentDir.length(), lpVFSAutoHotkeyDir);
    //    found = result.find(parentDir, found + VFSAutoHotkeyDirLen);
    //}

    // When the /launch switch is used for this program, don't wait for process to close.
    // However, wait for close if /launch was used AND was injected into the new command.
    // In that case we are waiting for launcher.ahk to return the PID of the launched process,
    // which we can then return.
    // Also don't wait for process termination if the parent of this process is explorer.exe, or no parent
    bool bWaitClose = !(flag & LAUNCH) || ((flag & LAUNCH) && bInjectedLaunch);

    DWORD parentPID = GetParentPID(GetCurrentProcessId());
    if (parentPID) {
        TCHAR parentName[MAX_PATH];
        if ((GetProcessName(parentPID, parentName, MAX_PATH) == 0) && (lstrcmpi(parentName, _T("explorer.exe")) == 0)) {
            bWaitClose = false;
        }
    }
    else {
        bWaitClose = false;
    }
    //wchar_t strbuf[2048];
    //swprintf_s(strbuf, 2048, L"exeArgs: %s\nscriptArgs: %s\nlpCmdLine: %s\nResult: %s\nFlag: %i\nLaunch: %i\nbWaitClose: %i", exeArgs.c_str(), scriptArgs.c_str(), lpCmdLine, result.c_str(), flag, flag & LAUNCH, bWaitClose);
    //MessageBox(0, strbuf, L"Debug", MB_OK);
    GetStartupInfo(&si);
    GetProcessInformation(GetCurrentProcess(), ProcessInformationClassMax, &pi, sizeof(pi));
    if (!CreateProcess(NULL,   // No module name (use command line)
        &result[0],        // Command line
        NULL,           // Process handle not inheritable
        NULL,           // Thread handle not inheritable
        TRUE,          // Set handle inheritance to TRUE
        0,          // Console window might be required if the script is passed with StdIn
        NULL,           // Use parent's environment block
        NULL,           // Use parent's starting directory 
        &si,            // Pointer to STARTUPINFO structure
        &pi)           // Pointer to PROCESS_INFORMATION structure
        && !(flag & LAUNCH)) // CreateProcess failed if result is zero, so return the error code
        return GetLastError();
    return WaitForScript(flag, bWaitClose, pi.hProcess, pi.hThread);
}