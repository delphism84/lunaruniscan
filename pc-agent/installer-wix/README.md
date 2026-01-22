# UniScan PC Agent Installer (MSI + Setup EXE)

## 목표
- **관리자 권한(UAC)으로 설치** (per-machine)
- 설치 후 **자동 시작 등록**(HKLM Run)
- 배포 시 보안 경고를 최소화하기 위해 **서명(Authenticode) 전제**

## 산출물
- `UniScan.PcAgent.msi`: MSI 패키지(관리자 권한 필요)
- `UniScan.PcAgent.Setup.exe`: (권장) 부트스트래퍼. `.NET Framework 4.8`이 없으면 설치 후 MSI 실행

## 빌드(Visual Studio / Build Tools)
1. **.NET Framework 4.8 Developer Pack** 설치(빌드 머신)
2. (권장) Visual Studio 2022 또는 Build Tools 설치
3. 아래 중 하나 빌드

### MSI만 빌드
```powershell
dotnet build "c:\rc\uniscan\pc-agent\installer-wix\UniScan.PcAgent.Msi.wixproj" -c Release
```

### Setup EXE(권장) 빌드
```powershell
dotnet build "c:\rc\uniscan\pc-agent\installer-wix\UniScan.PcAgent.Setup.wixproj" -c Release
```

## 자동 시작(Startup) 등록 방식
- MSI 설치 시 아래 레지스트리에 Run 값이 생성됩니다(모든 사용자/머신 기준).
  - `HKLM\Software\Microsoft\Windows\CurrentVersion\Run`
  - Name: `UniScanPcAgent`
  - Value: `"C:\Program Files\UniScan\PcAgent\UniScan.PcAgent.exe"`

## “웹에서 다운로드 후 실행” 보안 경고를 줄이는 핵심
MSI/Setup EXE 모두 **코드 서명**이 사실상 필수입니다.

- **반드시 서명할 것(추천 순서)**:
  - `UniScan.PcAgent.exe` (앱)
  - `UniScan.PcAgent.msi` (MSI)
  - `UniScan.PcAgent.Setup.exe` (부트스트래퍼)
- **타임스탬프**도 같이 넣기(서명 만료 후에도 유효)
- SmartScreen 경고를 줄이려면 일반 서명보다 **EV Code Signing**이 유리합니다.

> 참고: 서명 없이 배포하면 “알 수 없는 게시자” / SmartScreen 경고를 완전히 피하기 어렵습니다.

