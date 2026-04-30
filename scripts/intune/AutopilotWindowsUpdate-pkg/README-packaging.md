# AutopilotWindowsUpdate - Win32-pakking

## Innhold

| Fil | Formaal |
|-----|---------|
| `Invoke-AutopilotWindowsUpdate.ps1` | Hoved-script (install) |
| `Detect-AutopilotWindowsUpdate.ps1` | Deteksjonsskript |
| `Uninstall-AutopilotWindowsUpdate.ps1` | Avinstallasjon (fjerner registernoekkel) |
| `ServiceUI.exe` | **Du legger den til selv** - fra MDT (se nedenfor) |

---

## 1. Hent ServiceUI.exe

`ServiceUI.exe` projiserer vinduet fra SYSTEM-konteksten inn i bruker-sesjonen.

1. Last ned **Microsoft Deployment Toolkit (MDT)**:
   https://www.microsoft.com/en-us/download/details.aspx?id=54259
2. Etter installasjon finn `ServiceUI.exe` her:
   ```
   C:\Program Files\Microsoft Deployment Toolkit\Templates\Distribution\Tools\x64\ServiceUI.exe
   ```
3. Kopier den til pakkemappen ved siden av `Invoke-AutopilotWindowsUpdate.ps1`.

> **Bruk x64-versjonen.** Autopilot-enheter er 64-bit.

---

## 2. Test lokalt foer pakking

Aapne **PowerShell som administrator** paa en testmaskin og kjoer:

```powershell
.\Invoke-AutopilotWindowsUpdate.ps1 -NoReboot
```

Hvis dette fungerer (vinduet vises, oppdateringer installeres, deteksjonsnoekkelen
skrives til `HKLM:\SOFTWARE\AutopilotWindowsUpdate`), kan du gaa videre til pakking.

---

## 3. Pakk med IntuneWinAppUtil

```cmd
IntuneWinAppUtil.exe ^
  -c "C:\Path\To\AutopilotWindowsUpdate-pkg" ^
  -s "Invoke-AutopilotWindowsUpdate.ps1" ^
  -o "C:\Path\To\Output"
```

Resultat: `Invoke-AutopilotWindowsUpdate.intunewin`

---

## 4. Intune - Win32-app-innstillinger

### Generelt
| Felt | Verdi |
|------|-------|
| Navn | `Autopilot - Windows Update` |
| Beskrivelse | Installerer alle Windows-oppdateringer under Autopilot-enrollment |
| Publisher | (din org) |
| App-versjon | 1.2 |

### Programinformasjon

**Install command** (paa én linje):
```
ServiceUI.exe -process:explorer.exe %WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden -File Invoke-AutopilotWindowsUpdate.ps1 -NoReboot
```

**Uninstall command**:
```
%WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NonInteractive -File Uninstall-AutopilotWindowsUpdate.ps1
```

| Felt | Verdi |
|------|-------|
| **Install behavior** | `System` (kritisk - PSWindowsUpdate krever SYSTEM) |
| **Device restart behavior** | `Determine behavior based on return codes` |
| **Allow available uninstall** | `No` |

### Return codes
| Kode | Type | Beskrivelse |
|------|------|-------------|
| 0 | Success | Fullfoert OK |
| 1 | Failed | Feil - se logg |
| 1707 | Success | Standard MSI-suksess |
| 3010 | Soft reboot | Fullfoert, omstart oensket |
| 1641 | Hard reboot | Fullfoert, omstart paabegynt |
| 1618 | Retry | Annen installasjon paagaar |

### Krav
| Felt | Verdi |
|------|-------|
| OS-arkitektur | 64-bit |
| Min. OS | Windows 10 2004 (19041) |

### Deteksjon
Velg **"Use a custom detection script"** og last opp:
`Detect-AutopilotWindowsUpdate.ps1`

| Felt | Verdi |
|------|-------|
| Run script as 32-bit | No |
| Enforce script signature check | No |

---

## 5. Tilordning (Assignment)

| Felt | Verdi |
|------|-------|
| Gruppe | Autopilot-enhetsgruppe (eller alle enheter) |
| Formaal | `Required` |
| Filter | (valgfritt - f.eks. modellnavn) |

### Enrollment Status Page
I ESP-profilen for Autopilot:
- Aktiver **"Block device use until required apps are installed"**
- Legg til denne Win32-appen i listen over required apps under **User ESP**

> **Viktig**: ServiceUI projiserer kun til en aktiv bruker-sesjon. Det betyr at
> appen MAA kjoere under **User ESP** (etter brukeren har logget inn), ikke
> under Device ESP. Tilordne derfor til brukergruppe eller bruk en
> enhetsgruppe sammen med User ESP.

---

## 6. Logg og feilsoeking

Loggfil:
```
C:\Windows\Logs\AutopilotWindowsUpdate\AutopilotWindowsUpdate.log
```

Deteksjonsnoekkel:
```
HKLM:\SOFTWARE\AutopilotWindowsUpdate
  Status    = "Completed" | "Failed"
  Timestamp = ISO 8601
  Detail    = "NoUpdatesNeeded" | "3Updates/RebootRequired" | ...
```

Hent etter enrollment:
```powershell
Get-ItemProperty 'HKLM:\SOFTWARE\AutopilotWindowsUpdate'
Get-Content 'C:\Windows\Logs\AutopilotWindowsUpdate\AutopilotWindowsUpdate.log'
```

Intune Win32-app-logger paa enheten:
```
C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log
C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\AgentExecutor.log
```

---

## 7. Vanlige problemer

### Vinduet vises ikke under enrollment
- Kontroller at `ServiceUI.exe` ligger i pakken
- Kontroller at install-kommandoen starter med `ServiceUI.exe -process:explorer.exe`
- ServiceUI virker kun under User ESP (ikke Device ESP)

### "Access denied" fra PSWindowsUpdate
- Kontroller at **Install behavior = System** (ikke User)
- Sjekk loggen for hvilken konto som kjoerer scriptet

### Modulen lar seg ikke installere
- Sjekk Internet-tilgang under enrollment
- PSGallery maa vaere naabar (TLS 1.2 paaslaatt - PS 5.1 paa nyere Windows har dette by default)
