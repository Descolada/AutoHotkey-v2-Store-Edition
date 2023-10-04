# AutoHotkey v2 Store Edition
This is my attempt at an MSIX package containing AHK v1 and v2, which is compatible with Microsoft Store. It tries to mimic the native installation of v1 followed by v2, meaning it should have all the additional tools of v2 such as the Dash and the launcher.

## How to use
Because MSIX installs all files inside the restricted C:\Program Files\WindowsApps folder and makes them accessible as "shortcuts" then it causes some use differences when compared to the native installation.

* All executables (or more correctly, executable aliases containing app tokens) are stored inside the `C:\Users\User\AppData\Local\Microsoft\WindowsApps` folder
* `AutoHotkeyv1.exe` or `AutoHotkeyv2.exe` commands can be used to exclusively use either AutoHotkey v1 or v2 without any wrappers in the middle. Example Powershell command: `AutoHotkeyv2 script.ahk`. Alternatively the full path can be used: `C:\Users\user\AppData\Local\Microsoft\WindowsApps\AutoHotkeyv2.exe`. These can be used for editors, debuggers, etc.
* `AutoHotkey.exe` command runs the script using the preferences set in Dash. This functions the same as double-clicking a script. 

## Notes about MSIX
The MSIX version has some key differences to native AHK installation. 

The MSIX version creates the following 
Start Menu items:
* AutoHotkey (opens Dash)
* AutoHotkey v1 (opens v1 help)
* AutoHotkey v2 (opens v2 help)

App execution aliases (commands):
* AutoHotkey.exe (wrapper for launcher.ahk + Dash functionalities)
* AutoHotkeyv2.exe (Unicode 64-bit)
* AutoHotkeyv1.exe (Unicode 64-bit)

Due to MSIX limitations
* UIAccess is disabled (otherwise it would require admin access to install the package)
* AutoHotkey install folder is virtualized to be at C:\Program Files\AutoHotkey, which means that only scripts executed with one of the executables from the MSIX package can read that folder
* Registry writes are virtualized, which means other programs can't read them

Miscellaneous notes:
* If an exe is ran directly from the WindowsApps folder (C:\Program Files\WindowsApps\AutoHotkey-v2-hash\AutoHotkey.exe), then it will be ran without any virtualization (registry or file-system). This is only possible if the WindowsApps default access rights have been changed.
* Running as admin is possible, but requires admin account password

Developer notes about AutoHotkey.exe
* If ran without any arguments beside the script and its args, it will read the currently set launcher from `HKEY_CLASSES_ROOT\AutoHotkeyScript\Shell\open\command` and run the script with that.
* Flags are mostly used for shell actions: /launch, /runas, /edit
* /launch flag causes the wrapper to exit once the script is running
* /edit flag opens the target script with the editor set in Dash
* /runas flag uses ShellExecute to try to run the script as administrator, causing the UAC prompt
* /disablevfs flag stops the script from running itself from inside the AppData folder if it detects that it's not running in a virtualized environment
* Source code for AutoHotkey.exe is in 

# Autoinstaller
Autoinstaller packages AHK v1 and v2 into an MSIX package. This requires MSIX Hero to be installed (eg from Store).

When ran with AutoHotkey64.exe, this script will
1. Remove all old AHK versions
2. Download the latest versions of v1 and v2
3. Install first v1, then v2 (this requires user input)
4. Merges the AHK files from AHK_INSTALLDIR with AutoHotkey-MSIX-base to create AutoHotkey-MSIX-release
5. Copies AutoHotkeyShell.exe to v2 folder as AutoHotkey.exe; modifies ui-launcheditor.ahk to disable UI Access checkboxes
6. Packages AutoHotkey-MSIX-release into an .msix file using MSIX Hero
7. If SignCert.pfx is available along with SignCertPasswd.txt (containing the plain-text password for the cert), then also signs the package. SignCert.pfx can be for example the file in Windows10STestPolicies/AppxTestRootAgency/AppxTestRootAgency.pfx

After packaging to MSIX, the package should be tested whether it complies to Windows 10S test policies. Read more from here: https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-test-windows-s
