reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v EnableFirstLogonAnimation /t REG_DWORD /d 0 /f
schtasks /create /RU SYSTEM /Z /V1 /F /SC once /TN SetupCleanup /TR "net user admin /delete" /ST 23:59
schtasks /create /RU SYSTEM /Z /V1 /F /SC once /TN SetupCleanup1 /TR "cmd /c rd /s /q C:\Users\Admin" /ST 23:59
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" /v !SRSInstall /t REG_SZ /d "cmd /c powershell -WindowStyle Maximized -ExecutionPolicy Unrestricted C:\Rigel\x64\Scripts\Provisioning\FinalSetup.ps1" /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"  /f /v DefaultUserName /t REG_SZ /d "Admin"
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"  /f /v DefaultPassword /t REG_SZ /d "sfb"
reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce /f /v !SkypeLogon /t REG_SZ /d "reg add \"HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\" /f /v DefaultUserName /t REG_SZ /d Skype"
reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce /f /v !SkypeLogonPwd /t REG_SZ /d "reg add \"HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\" /f /v DefaultPassword /t REG_SZ /d \"""
reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce /f /v !SRSReboot /t REG_SZ /d "shutdown /r /f /t 59"