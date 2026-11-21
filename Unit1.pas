unit Unit1;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  StdCtrls, Registry, Clipbrd;

type
  TForm1 = class(TForm)
    Memo1: TMemo;
    Button1: TButton;
    Button2: TButton;
    Button3: TButton;
    procedure FormCreate(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure Button3Click(Sender: TObject);
  private
    procedure CollectSystemInfo;
    function GetOSInfo: string;
    function GetSystemExtraInfo: string;
    function GetMoboBiosInfo: string;
    function GetCPUBrandStringFromCPUID: string;
    function GetCPUFallbackNameBySignature(const Vendor: string; Family, Model, Stepping, BrandID: Cardinal): string;
    function GetCPUInfo: string;
    function GetCPUFeatures: string;
    function MeasureCPUSpeedRDTSC: Cardinal;
    function GetMemoryInfo: string;
    function GetVideoInfo: string;
    function GetScreenInfo: string;
    function GetDrivesInfo: string;
  public
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

type
  TMemoryStatusEx = record
    dwLength: DWORD;
    dwMemoryLoad: DWORD;
    ullTotalPhys: Int64;
    ullAvailPhys: Int64;
    ullTotalPageFile: Int64;
    ullAvailPageFile: Int64;
    ullTotalVirtual: Int64;
    ullAvailVirtual: Int64;
    ullAvailExtendedVirtual: Int64;
  end;

  TGlobalMemoryStatusEx = function(var lpBuffer: TMemoryStatusEx): BOOL; stdcall;

  TDisplayDeviceA = record
    cb: DWORD;
    DeviceName: array[0..31] of AnsiChar;
    DeviceString: array[0..127] of AnsiChar;
    StateFlags: DWORD;
    DeviceID: array[0..127] of AnsiChar;
    DeviceKey: array[0..127] of AnsiChar;
  end;

  TEnumDisplayDevicesA = function(lpDevice: PAnsiChar; iDevNum: DWORD;
    var lpDisplayDevice: TDisplayDeviceA; dwFlags: DWORD): BOOL; stdcall;

  TRtlGetVersion = function(var lpVersionInformation: TOSVersionInfoA): LongInt; stdcall;
  TGetTickCount64 = function: Int64; stdcall;
  TGetDiskFreeSpaceExA = function(lpDirectoryName: PAnsiChar;
    var lpFreeBytesAvailableToCaller, lpTotalNumberOfBytes,
    lpTotalNumberOfFreeBytes: Int64): BOOL; stdcall;
  TIsWow64Process = function(hProcess: THandle; var Wow64Process: BOOL): BOOL; stdcall;

function SafeReadRegString(Root: HKEY; const Key, Name: string): string;
var
  Reg: TRegistry;
begin
  Result := '';
  Reg := TRegistry.Create;
  try
    Reg.RootKey := Root;
    if Reg.OpenKeyReadOnly(Key) then
    begin
      if Reg.ValueExists(Name) then
        Result := Trim(Reg.ReadString(Name));
      Reg.CloseKey;
    end;
  except
    Result := '';
  end;
  Reg.Free;
end;

function SafeReadRegInteger(Root: HKEY; const Key, Name: string): Integer;
var
  Reg: TRegistry;
begin
  Result := 0;
  Reg := TRegistry.Create;
  try
    Reg.RootKey := Root;
    if Reg.OpenKeyReadOnly(Key) then
    begin
      if Reg.ValueExists(Name) then
        Result := Reg.ReadInteger(Name);
      Reg.CloseKey;
    end;
  except
    Result := 0;
  end;
  Reg.Free;
end;

function IsCPUIDSupported: Boolean;
var
  Supported: DWORD;
begin
  Supported := 0;
  try
    asm
      pushfd
      pop eax
      mov ecx, eax
      xor eax, $200000
      push eax
      popfd
      pushfd
      pop eax
      xor eax, ecx
      jz @NoCPUID
      mov Supported, 1
    @NoCPUID:
      push ecx
      popfd
    end;
  except
    Supported := 0;
  end;
  Result := (Supported = 1);
end;

procedure ExecuteCPUID(Leaf: DWORD; var rEAX, rEBX, rECX, rEDX: DWORD);
var
  tEAX, tEBX, tECX, tEDX: DWORD;
begin
  tEAX := 0; tEBX := 0; tECX := 0; tEDX := 0;
  asm
    push ebx
    push ecx
    push edx
    mov eax, Leaf
    xor ecx, ecx
    dw $A20F // CPUID
    mov tEAX, eax
    mov tEBX, ebx
    mov tECX, ecx
    mov tEDX, edx
    pop edx
    pop ecx
    pop ebx
  end;
  rEAX := tEAX;
  rEBX := tEBX;
  rECX := tECX;
  rEDX := tEDX;
end;

{ Direct hardware Brand String extraction from CPUID (0x80000002..0x80000004) }
{ Works in Windows 95/98 even when OS reports only "GenuineIntel" }
function TForm1.GetCPUBrandStringFromCPUID: string;
var
  MaxExt, rEAX, rEBX, rECX, rEDX: DWORD;
  Buf: array[0..48] of AnsiChar;
  Leaf: DWORD;
  Offset: Integer;
begin
  Result := '';
  if not IsCPUIDSupported then Exit;

  try
    ExecuteCPUID($80000000, MaxExt, rEBX, rECX, rEDX);
    if MaxExt >= $80000004 then
    begin
      FillChar(Buf, SizeOf(Buf), 0);
      Offset := 0;
      for Leaf := $80000002 to $80000004 do
      begin
        ExecuteCPUID(Leaf, rEAX, rEBX, rECX, rEDX);
        Move(rEAX, Buf[Offset], 4);
        Move(rEBX, Buf[Offset + 4], 4);
        Move(rECX, Buf[Offset + 8], 4);
        Move(rEDX, Buf[Offset + 12], 4);
        Inc(Offset, 16);
      end;
      Result := Trim(string(Buf));
      while Pos('  ', Result) > 0 do
        Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
    end;
  except
    Result := '';
  end;
end;

{ Built-in database for legacy CPUs (Pentium I/II/III, K6, Athlon XP, etc.) without Brand String }
function TForm1.GetCPUFallbackNameBySignature(const Vendor: string;
  Family, Model, Stepping, BrandID: Cardinal): string;
begin
  Result := '';
  if Pos('Intel', Vendor) > 0 then
  begin
    case Family of
      4: Result := 'Intel i486 Series';
      5: case Model of
           1, 2, 7: Result := 'Intel Pentium (P5 / P54C)';
           4, 8: Result := 'Intel Pentium MMX (P55C)';
         else
           Result := 'Intel Pentium';
         end;
      6: case Model of
           1: Result := 'Intel Pentium Pro';
           3, 5: begin
                   if BrandID = 1 then Result := 'Intel Celeron (Covington/Mendocino)'
                   else if BrandID = 3 then Result := 'Intel Pentium II Xeon'
                   else Result := 'Intel Pentium II';
                 end;
           6: Result := 'Intel Celeron (Mendocino)';
           7, 8, 10, 11: begin
                   if (BrandID = 1) or (BrandID = 7) then Result := 'Intel Celeron (Coppermine/Tualatin)'
                   else if (BrandID = 3) or (BrandID = 4) then Result := 'Intel Pentium III Xeon'
                   else Result := 'Intel Pentium III';
                 end;
           9, 13: Result := 'Intel Pentium M (Banias / Dothan)';
           14: Result := 'Intel Core Duo / Solo (Yonah)';
           15: Result := 'Intel Core 2 / Xeon (Conroe / Clovertown)';
           23: Result := 'Intel Core 2 / Xeon (Penryn / Harpertown)';
           26, 30, 44: Result := 'Intel Core i7 / Xeon (Nehalem / Westmere)';
         else
           Result := Format('Intel P6 / Core Family (Model %d)', [Model]);
         end;
      15: begin
            if (BrandID = 8) or (BrandID = 9) or (BrandID = 10) then
              Result := 'Intel Celeron (NetBurst)'
            else if (BrandID = 11) or (BrandID = 12) or (BrandID = 14) then
              Result := 'Intel Xeon (NetBurst)'
            else
              Result := 'Intel Pentium 4 / D (NetBurst)';
          end;
    end;
  end
  else if Pos('AMD', Vendor) > 0 then
  begin
    case Family of
      4: Result := 'AMD Am486 / Am5x86';
      5: case Model of
           0..3: Result := 'AMD K5';
           6, 7: Result := 'AMD K6';
           8: Result := 'AMD K6-2';
           9, 13: Result := 'AMD K6-III';
         else
           Result := 'AMD K6 Series';
         end;
      6: case Model of
           1, 2, 4: Result := 'AMD Athlon (K7)';
           3, 7: Result := 'AMD Duron';
           6, 8, 10: Result := 'AMD Athlon XP / MP / Sempron (K7)';
         else
           Result := 'AMD Athlon (K7 Architecture)';
         end;
      15: Result := 'AMD Athlon 64 / Opteron / Sempron (K8)';
    end;
  end
  else if (Pos('Centaur', Vendor) > 0) or (Pos('VIA', Vendor) > 0) then
  begin
    if Family = 5 then Result := 'IDT WinChip / WinChip 2'
    else if Family = 6 then Result := 'VIA C3 / C7 / Eden';
  end
  else if Pos('Cyrix', Vendor) > 0 then
    Result := 'Cyrix 6x86 / MII';
end;

function TForm1.GetOSInfo: string;
var
  OSVI: TOSVersionInfoA;
  hNtDll: THandle;
  RtlGetVersion: TRtlGetVersion;
  ProductName, EditionID, DisplayVer, BuildStr, CSD: string;
  Major, Minor, Build: DWORD;
begin
  FillChar(OSVI, SizeOf(OSVI), 0);
  OSVI.dwOSVersionInfoSize := SizeOf(OSVI);

  hNtDll := GetModuleHandle('ntdll.dll');
  if hNtDll <> 0 then
  begin
    @RtlGetVersion := GetProcAddress(hNtDll, 'RtlGetVersion');
    if Assigned(RtlGetVersion) then
      RtlGetVersion(OSVI)
    else
      GetVersionExA(OSVI);
  end
  else
    GetVersionExA(OSVI);

  Major := OSVI.dwMajorVersion;
  Minor := OSVI.dwMinorVersion;
  Build := OSVI.dwBuildNumber;
  CSD := Trim(string(OSVI.szCSDVersion));

  if OSVI.dwPlatformId = VER_PLATFORM_WIN32_WINDOWS then
  begin
    Build := Build and $FFFF;
    if (Major = 4) and (Minor = 0) then
    begin
      if Build >= 1111 then
        ProductName := 'Microsoft Windows 95 OSR2'
      else
        ProductName := 'Microsoft Windows 95';
    end
    else if (Major = 4) and (Minor = 10) then
    begin
      if Build >= 2222 then
        ProductName := 'Microsoft Windows 98 Second Edition (SE)'
      else
        ProductName := 'Microsoft Windows 98';
    end
    else if (Major = 4) and (Minor = 90) then
      ProductName := 'Microsoft Windows Millennium Edition (ME)'
    else
      ProductName := 'Microsoft Windows 9x';
  end
  else
  begin
    ProductName := SafeReadRegString(HKEY_LOCAL_MACHINE,
      'SOFTWARE\Microsoft\Windows NT\CurrentVersion', 'ProductName');
    EditionID := SafeReadRegString(HKEY_LOCAL_MACHINE,
      'SOFTWARE\Microsoft\Windows NT\CurrentVersion', 'EditionID');

    // Fix registry mismatch when Windows 10/11 was upgraded/activated from Enterprise to Pro
    if SameText(EditionID, 'Professional') and (Pos('Enterprise', ProductName) > 0) then
      ProductName := StringReplace(ProductName, 'Enterprise', 'Pro', [rfIgnoreCase])
    else if SameText(EditionID, 'Core') and (Pos('Enterprise', ProductName) > 0) then
      ProductName := StringReplace(ProductName, 'Enterprise', 'Home', [rfIgnoreCase]);

    if Build < 22000 then
      Build := StrToIntDef(SafeReadRegString(HKEY_LOCAL_MACHINE,
        'SOFTWARE\Microsoft\Windows NT\CurrentVersion', 'CurrentBuild'), Build);

    if (Major = 10) and (Build >= 22000) then
      ProductName := StringReplace(ProductName, 'Windows 10', 'Windows 11', [rfIgnoreCase]);

    DisplayVer := SafeReadRegString(HKEY_LOCAL_MACHINE,
      'SOFTWARE\Microsoft\Windows NT\CurrentVersion', 'DisplayVersion');
    if DisplayVer = '' then
      DisplayVer := SafeReadRegString(HKEY_LOCAL_MACHINE,
        'SOFTWARE\Microsoft\Windows NT\CurrentVersion', 'ReleaseId');

    if DisplayVer <> '' then
      ProductName := ProductName + ' (' + DisplayVer + ')';

    if ProductName = '' then
      ProductName := Format('Windows NT %d.%d', [Major, Minor]);
  end;

  BuildStr := Format('Version %d.%d (Build %d)', [Major, Minor, Build]);
  if CSD <> '' then
    BuildStr := BuildStr + ' [' + CSD + ']';

  Result := ProductName + #13#10 + '   ' + BuildStr;
end;

function TForm1.GetSystemExtraInfo: string;
var
  CompName, UserName: array[0..255] of AnsiChar;
  WinDir, SysDir, TempDir: array[0..MAX_PATH] of AnsiChar;
  Size: DWORD;
  hKernel: THandle;
  GetTickCount64: TGetTickCount64;
  IsWow64Process: TIsWow64Process;
  IsWow64: BOOL;
  UptimeMs: Int64;
  Days, Hours, Mins, Secs: Int64;
  ArchStr: string;
begin
  Size := SizeOf(CompName);
  if not GetComputerNameA(CompName, Size) then StrPCopy(CompName, 'Unknown');

  Size := SizeOf(UserName);
  if not GetUserNameA(UserName, Size) then StrPCopy(UserName, 'Unknown');

  GetWindowsDirectoryA(WinDir, MAX_PATH);
  GetSystemDirectoryA(SysDir, MAX_PATH);
  GetTempPathA(MAX_PATH, TempDir);

  hKernel := GetModuleHandle('kernel32.dll');
  IsWow64 := False;
  @IsWow64Process := GetProcAddress(hKernel, 'IsWow64Process');
  if Assigned(IsWow64Process) then
    IsWow64Process(GetCurrentProcess, IsWow64);

  if IsWow64 then
    ArchStr := '64-bit OS (x64)'
  else
    ArchStr := '32-bit OS (x86)';

  @GetTickCount64 := GetProcAddress(hKernel, 'GetTickCount64');
  if Assigned(GetTickCount64) then
    UptimeMs := GetTickCount64
  else
    UptimeMs := DWORD(GetTickCount);

  Secs := UptimeMs div 1000;
  Days := Secs div 86400;
  Hours := (Secs mod 86400) div 3600;
  Mins := (Secs mod 3600) div 60;
  Secs := Secs mod 60;

  Result := Format('OS Architecture : %s', [ArchStr]) + #13#10 +
            Format('   Computer / User : %s / %s', [string(CompName), string(UserName)]) + #13#10 +
            Format('   System Uptime   : %d d, %d h, %d m, %d s', [Days, Hours, Mins, Secs]) + #13#10 +
            Format('   Windows Folder  : %s', [string(WinDir)]) + #13#10 +
            Format('   System Folder   : %s', [string(SysDir)]);
end;

function TForm1.GetMoboBiosInfo: string;
var
  MoboManuf, MoboProd, BiosVendor, BiosVer, BiosDate: string;
begin
  MoboManuf := SafeReadRegString(HKEY_LOCAL_MACHINE,
    'HARDWARE\DESCRIPTION\System\BIOS', 'BaseBoardManufacturer');
  MoboProd := SafeReadRegString(HKEY_LOCAL_MACHINE,
    'HARDWARE\DESCRIPTION\System\BIOS', 'BaseBoardProduct');
  BiosVendor := SafeReadRegString(HKEY_LOCAL_MACHINE,
    'HARDWARE\DESCRIPTION\System\BIOS', 'BIOSVendor');
  BiosVer := SafeReadRegString(HKEY_LOCAL_MACHINE,
    'HARDWARE\DESCRIPTION\System\BIOS', 'BIOSVersion');
  BiosDate := SafeReadRegString(HKEY_LOCAL_MACHINE,
    'HARDWARE\DESCRIPTION\System\BIOS', 'BIOSReleaseDate');

  if BiosVer = '' then
    BiosVer := SafeReadRegString(HKEY_LOCAL_MACHINE,
      'HARDWARE\DESCRIPTION\System', 'SystemBiosVersion');
  if BiosDate = '' then
    BiosDate := SafeReadRegString(HKEY_LOCAL_MACHINE,
      'HARDWARE\DESCRIPTION\System', 'SystemBiosDate');

  if MoboManuf = '' then
    MoboManuf := SafeReadRegString(HKEY_LOCAL_MACHINE,
      'Enum\Root\*PNP0C01 0', 'BIOSName');

  Result := '';
  if (MoboManuf <> '') or (MoboProd <> '') then
    Result := Format('Motherboard     : %s %s', [Trim(MoboManuf), Trim(MoboProd)]) + #13#10 + '   ';

  if (BiosVendor <> '') or (BiosVer <> '') then
    Result := Result + Format('BIOS Version    : %s %s', [Trim(BiosVendor), Trim(BiosVer)])
  else
    Result := Result + 'BIOS Version    : Standard / Legacy BIOS';

  if BiosDate <> '' then
    Result := Result + Format(' (Date: %s)', [BiosDate]);
end;

function TForm1.MeasureCPUSpeedRDTSC: Cardinal;
var
  StartLow, StartHigh, EndLow, EndHigh: DWORD;
  StartTicks, EndTicks, ElapsedTicks: DWORD;
  Cycles, Freq: Int64;
  rEAX, rEBX, rECX, rEDX: DWORD;
begin
  Result := 0;
  if not IsCPUIDSupported then Exit;

  try
    ExecuteCPUID(1, rEAX, rEBX, rECX, rEDX);
    if (rEDX and $10) = 0 then Exit; // RDTSC not supported

    StartTicks := GetTickCount;
    while GetTickCount = StartTicks do;
    StartTicks := GetTickCount;

    asm
      dw $310F // RDTSC
      mov StartLow, eax
      mov StartHigh, edx
    end;

    repeat
      EndTicks := GetTickCount;
      ElapsedTicks := EndTicks - StartTicks;
    until ElapsedTicks >= 250;

    asm
      dw $310F // RDTSC
      mov EndLow, eax
      mov EndHigh, edx
    end;

    Cycles := ((Int64(EndHigh) shl 32) or EndLow) - ((Int64(StartHigh) shl 32) or StartLow);
    if (Cycles > 0) and (ElapsedTicks > 0) then
    begin
      Freq := (Cycles div ElapsedTicks) div 1000;
      Result := Cardinal(Freq);
    end;
  except
    Result := 0;
  end;
end;

function TForm1.GetCPUFeatures: string;
var
  rEAX, rEBX, rECX, rEDX: DWORD;
  Feat: string;
begin
  Result := 'None / Pre-CPUID';
  if not IsCPUIDSupported then Exit;

  try
    ExecuteCPUID(1, rEAX, rEBX, rECX, rEDX);
    Feat := '';
    if (rEDX and (1 shl 0)) <> 0 then Feat := Feat + 'FPU ';
    if (rEDX and (1 shl 4)) <> 0 then Feat := Feat + 'RDTSC ';
    if (rEDX and (1 shl 23)) <> 0 then Feat := Feat + 'MMX ';
    if (rEDX and (1 shl 25)) <> 0 then Feat := Feat + 'SSE ';
    if (rEDX and (1 shl 26)) <> 0 then Feat := Feat + 'SSE2 ';
    if (rECX and (1 shl 0)) <> 0 then Feat := Feat + 'SSE3 ';
    if (rECX and (1 shl 9)) <> 0 then Feat := Feat + 'SSSE3 ';
    if (rECX and (1 shl 19)) <> 0 then Feat := Feat + 'SSE4.1 ';
    if (rECX and (1 shl 20)) <> 0 then Feat := Feat + 'SSE4.2 ';
    if (rECX and (1 shl 25)) <> 0 then Feat := Feat + 'AES ';
    if (rECX and (1 shl 28)) <> 0 then Feat := Feat + 'AVX ';

    if Trim(Feat) <> '' then
      Result := Trim(Feat);
  except
  end;
end;

function TForm1.GetCPUInfo: string;
var
  SysInfo: TSystemInfo;
  CPUName, Vendor, SigStr: string;
  VendorBuf: array[0..12] of AnsiChar;
  rEAX, rEBX, rECX, rEDX: DWORD;
  Family, Model, Stepping, ExtFamily, ExtModel, BrandID: Cardinal;
  MHz: Integer;
begin
  GetSystemInfo(SysInfo);
  Vendor := '';
  SigStr := '';
  Family := 0; Model := 0; Stepping := 0; BrandID := 0;

  // 1. Read Vendor and Family/Model/Stepping directly from CPUID Leaf 0 and 1
  if IsCPUIDSupported then
  begin
    try
      ExecuteCPUID(0, rEAX, rEBX, rECX, rEDX);
      FillChar(VendorBuf, SizeOf(VendorBuf), 0);
      Move(rEBX, VendorBuf[0], 4);
      Move(rEDX, VendorBuf[4], 4);
      Move(rECX, VendorBuf[8], 4);
      Vendor := Trim(string(VendorBuf));

      if rEAX >= 1 then
      begin
        ExecuteCPUID(1, rEAX, rEBX, rECX, rEDX);
        Stepping := rEAX and $0F;
        Model := (rEAX shr 4) and $0F;
        Family := (rEAX shr 8) and $0F;
        ExtModel := (rEAX shr 16) and $0F;
        ExtFamily := (rEAX shr 20) and $FF;
        BrandID := rEBX and $FF;

        if Family = 15 then
          Family := Family + ExtFamily;
        if (Family = 6) or (Family = 15) then
          Model := (ExtModel shl 4) + Model;

        SigStr := Format('Family %d (0x%X), Model %d (0x%X), Stepping %d',
          [Family, Family, Model, Model, Stepping]);
      end;
    except
    end;
  end;

  // 2. Primary source: Hardware CPUID Brand String (works on Xeon X5670 even in Windows 98!)
  CPUName := GetCPUBrandStringFromCPUID;

  // 3. Secondary source: Windows Registry (for NT/XP/10/11)
  if CPUName = '' then
    CPUName := SafeReadRegString(HKEY_LOCAL_MACHINE,
      'HARDWARE\DESCRIPTION\System\CentralProcessor ', 'ProcessorNameString');

  // 4. Tertiary source: Built-in CPUID signature database (for Pentium I/II/III, K6, Athlon XP)
  if (CPUName = '') and (Family > 0) then
    CPUName := GetCPUFallbackNameBySignature(Vendor, Family, Model, Stepping, BrandID);

  // 5. Fallback to Registry Identifier or TSystemInfo
  if CPUName = '' then
    CPUName := SafeReadRegString(HKEY_LOCAL_MACHINE,
      'HARDWARE\DESCRIPTION\System\CentralProcessor ', 'Identifier');

  if CPUName = '' then
    CPUName := Format('x86 Processor (Level %d, Revision %d)',
      [SysInfo.wProcessorLevel, SysInfo.wProcessorRevision]);

  if Vendor = '' then
    Vendor := SafeReadRegString(HKEY_LOCAL_MACHINE,
      'HARDWARE\DESCRIPTION\System\CentralProcessor ', 'VendorIdentifier');

  while Pos('  ', CPUName) > 0 do
    CPUName := StringReplace(CPUName, '  ', ' ', [rfReplaceAll]);

  MHz := SafeReadRegInteger(HKEY_LOCAL_MACHINE,
    'HARDWARE\DESCRIPTION\System\CentralProcessor ', '~MHz');

  if MHz <= 0 then
    MHz := MeasureCPUSpeedRDTSC;

  Result := 'Model           : ' + CPUName;
  if Vendor <> '' then
    Result := Result + ' [' + Vendor + ']';

  if SigStr <> '' then
    Result := Result + #13#10 + '   CPUID Signature : ' + SigStr;

  if MHz > 0 then
    Result := Result + #13#10 + Format('   Clock & Cores   : ~%d MHz | Logical Cores: %d',
      [MHz, SysInfo.dwNumberOfProcessors])
  else
    Result := Result + #13#10 + Format('   Clock & Cores   : Unknown MHz | Logical Cores: %d',
      [SysInfo.dwNumberOfProcessors]);

  Result := Result + #13#10 + '   Instructions    : ' + GetCPUFeatures;
end;

function TForm1.GetMemoryInfo: string;
var
  hKernel: THandle;
  GlobalMemoryStatusEx: TGlobalMemoryStatusEx;
  MemEx: TMemoryStatusEx;
  MemOld: TMemoryStatus;
  TotalPhysMB, AvailPhysMB, TotalPageMB, AvailPageMB: Int64;
  LoadPct: DWORD;
begin
  TotalPhysMB := 0; AvailPhysMB := 0;
  TotalPageMB := 0; AvailPageMB := 0;
  LoadPct := 0;

  hKernel := GetModuleHandle('kernel32.dll');
  @GlobalMemoryStatusEx := GetProcAddress(hKernel, 'GlobalMemoryStatusEx');

  if Assigned(GlobalMemoryStatusEx) then
  begin
    FillChar(MemEx, SizeOf(MemEx), 0);
    MemEx.dwLength := SizeOf(MemEx);
    if GlobalMemoryStatusEx(MemEx) then
    begin
      TotalPhysMB := MemEx.ullTotalPhys div (1024 * 1024);
      AvailPhysMB := MemEx.ullAvailPhys div (1024 * 1024);
      TotalPageMB := MemEx.ullTotalPageFile div (1024 * 1024);
      AvailPageMB := MemEx.ullAvailPageFile div (1024 * 1024);
      LoadPct := MemEx.dwMemoryLoad;
    end;
  end;

  if TotalPhysMB = 0 then
  begin
    FillChar(MemOld, SizeOf(MemOld), 0);
    MemOld.dwLength := SizeOf(MemOld);
    GlobalMemoryStatus(MemOld);
    TotalPhysMB := Int64(MemOld.dwTotalPhys) div (1024 * 1024);
    AvailPhysMB := Int64(MemOld.dwAvailPhys) div (1024 * 1024);
    TotalPageMB := Int64(MemOld.dwTotalPageFile) div (1024 * 1024);
    AvailPageMB := Int64(MemOld.dwAvailPageFile) div (1024 * 1024);
    LoadPct := MemOld.dwMemoryLoad;
  end;

  Result := Format('Physical RAM    : %d MB Total | %d MB Free (%d%% Load)',
    [TotalPhysMB, AvailPhysMB, LoadPct]) + #13#10 +
            Format('   Page / Commit   : %d MB Total | %d MB Free',
    [TotalPageMB, AvailPageMB]);
end;

function TForm1.GetVideoInfo: string;
var
  hUser32: THandle;
  EnumDisplayDevicesA: TEnumDisplayDevicesA;
  DispDev: TDisplayDeviceA;
  i: DWORD;
  VideoList: TStringList;
  Reg: TRegistry;
  SubKeys: TStringList;
  j: Integer;
  CardDesc: string;
begin
  VideoList := TStringList.Create;
  try
    hUser32 := GetModuleHandle('user32.dll');
    @EnumDisplayDevicesA := GetProcAddress(hUser32, 'EnumDisplayDevicesA');

    if Assigned(EnumDisplayDevicesA) then
    begin
      i := 0;
      FillChar(DispDev, SizeOf(DispDev), 0);
      DispDev.cb := SizeOf(DispDev);

      while EnumDisplayDevicesA(nil, i, DispDev, 0) do
      begin
        if (DispDev.StateFlags and $00000008) = 0 then
        begin
          CardDesc := Trim(string(DispDev.DeviceString));
          if (CardDesc <> '') and (VideoList.IndexOf(CardDesc) = -1) then
            VideoList.Add(CardDesc);
        end;
        Inc(i);
        FillChar(DispDev, SizeOf(DispDev), 0);
        DispDev.cb := SizeOf(DispDev);
      end;
    end;

    // Fallback for Windows 95
    if VideoList.Count = 0 then
    begin
      Reg := TRegistry.Create;
      SubKeys := TStringList.Create;
      try
        Reg.RootKey := HKEY_LOCAL_MACHINE;
        if Reg.OpenKeyReadOnly('System\CurrentControlSet\Services\Class\Display') then
        begin
          Reg.GetKeyNames(SubKeys);
          Reg.CloseKey;
          for j := 0 to SubKeys.Count - 1 do
          begin
            CardDesc := SafeReadRegString(HKEY_LOCAL_MACHINE,
              'System\CurrentControlSet\Services\Class\Display' + SubKeys[j], 'DriverDesc');
            if (CardDesc <> '') and (VideoList.IndexOf(CardDesc) = -1) then
              VideoList.Add(CardDesc);
          end;
        end;
      except
      end;
      SubKeys.Free;
      Reg.Free;
    end;

    if VideoList.Count > 0 then
      Result := Trim(VideoList.Text)
    else
      Result := 'Standard Display Adapter (Unknown Model)';
  finally
    VideoList.Free;
  end;
end;

function TForm1.GetScreenInfo: string;
var
  DC: HDC;
  WidthPx, HeightPx, BPP, Planes, RefreshRate: Integer;
begin
  DC := GetDC(0);
  try
    WidthPx := GetDeviceCaps(DC, HORZRES);
    HeightPx := GetDeviceCaps(DC, VERTRES);
    Planes := GetDeviceCaps(DC, PLANES);
    if Planes < 1 then
      Planes := 1;
    BPP := GetDeviceCaps(DC, BITSPIXEL) * Planes;
    RefreshRate := GetDeviceCaps(DC, VREFRESH);
  finally
    ReleaseDC(0, DC);
  end;

  if RefreshRate > 1 then
    Result := Format('%d x %d pixels, %d bit (%d Hz)', [WidthPx, HeightPx, BPP, RefreshRate])
  else
    Result := Format('%d x %d pixels, %d bit', [WidthPx, HeightPx, BPP]);
end;

function TForm1.GetDrivesInfo: string;
var
  DrivesMask: DWORD;
  DriveLetter: Char;
  RootPath, TypeStr, VolLabel, FSName: string;
  DType: UINT;
  VolNameBuf, FSNameBuf: array[0..255] of AnsiChar;
  SerialNum, MaxCompLen, FSFlags: DWORD;
  hKernel: THandle;
  GetDiskFreeSpaceExA: TGetDiskFreeSpaceExA;
  FreeAvail, TotalBytes, TotalFree: Int64;
  SecPerClus, BytesPerSec, FreeClus, TotalClus: DWORD;
  Lines: TStringList;
  OldErrMode: UINT;
begin
  Lines := TStringList.Create;
  OldErrMode := SetErrorMode(SEM_FAILCRITICALERRORS);
  try
    hKernel := GetModuleHandle('kernel32.dll');
    @GetDiskFreeSpaceExA := GetProcAddress(hKernel, 'GetDiskFreeSpaceExA');

    DrivesMask := GetLogicalDrives;
    for DriveLetter := 'A' to 'Z' do
    begin
      if (DrivesMask and (1 shl (Ord(DriveLetter) - Ord('A')))) <> 0 then
      begin
        RootPath := DriveLetter + ':';
        DType := GetDriveTypeA(PAnsiChar(RootPath));
        case DType of
          DRIVE_REMOVABLE: TypeStr := 'Removable';
          DRIVE_FIXED:     TypeStr := 'Fixed HDD/SSD';
          DRIVE_REMOTE:    TypeStr := 'Network';
          DRIVE_CDROM:     TypeStr := 'CD/DVD-ROM';
          DRIVE_RAMDISK:   TypeStr := 'RAM Disk';
        else
          TypeStr := 'Unknown';
        end;

        FillChar(VolNameBuf, SizeOf(VolNameBuf), 0);
        FillChar(FSNameBuf, SizeOf(FSNameBuf), 0);
        VolLabel := '';
        FSName := '';

        if GetVolumeInformationA(PAnsiChar(RootPath), VolNameBuf, SizeOf(VolNameBuf),
          @SerialNum, MaxCompLen, FSFlags, FSNameBuf, SizeOf(FSNameBuf)) then
        begin
          VolLabel := Trim(string(VolNameBuf));
          FSName := Trim(string(FSNameBuf));
        end;

        TotalBytes := 0;
        TotalFree := 0;
        if Assigned(GetDiskFreeSpaceExA) then
        begin
          if not GetDiskFreeSpaceExA(PAnsiChar(RootPath), FreeAvail, TotalBytes, TotalFree) then
          begin
            TotalBytes := 0;
            TotalFree := 0;
          end;
        end
        else
        begin
          if GetDiskFreeSpaceA(PAnsiChar(RootPath), SecPerClus, BytesPerSec, FreeClus, TotalClus) then
          begin
            TotalBytes := Int64(TotalClus) * SecPerClus * BytesPerSec;
            TotalFree := Int64(FreeClus) * SecPerClus * BytesPerSec;
          end;
        end;

        if VolLabel = '' then
          VolLabel := 'No Label';
        if FSName = '' then
          FSName := 'N/A';

        if TotalBytes > 0 then
          Lines.Add(Format('%s [%s] (%s, %s) - Total: %d MB | Free: %d MB',
            [RootPath, TypeStr, VolLabel, FSName,
             TotalBytes div (1024 * 1024), TotalFree div (1024 * 1024)]))
        else
          Lines.Add(Format('%s [%s] (%s) - Media not ready / Empty',
            [RootPath, TypeStr, VolLabel]));
      end;
    end;

    if Lines.Count > 0 then
      Result := Trim(Lines.Text)
    else
      Result := 'No logical drives detected';
  finally
    SetErrorMode(OldErrMode);
    Lines.Free;
  end;
end;

procedure TForm1.CollectSystemInfo;
begin
  Memo1.Lines.BeginUpdate;
  try
    Memo1.Clear;
    Memo1.Lines.Add('===============================================================');
    Memo1.Lines.Add('   SysInfo by MarkFH v2.1  |  User-Mode Hardware Diagnostics');
    Memo1.Lines.Add('===============================================================');
    Memo1.Lines.Add('');
    Memo1.Lines.Add('[OPERATING SYSTEM]');
    Memo1.Lines.Add('   ' + GetOSInfo);
    Memo1.Lines.Add('   ' + GetSystemExtraInfo);
    Memo1.Lines.Add('');
    Memo1.Lines.Add('[MOTHERBOARD & BIOS]');
    Memo1.Lines.Add('   ' + GetMoboBiosInfo);
    Memo1.Lines.Add('');
    Memo1.Lines.Add('[PROCESSOR (CPU)]');
    Memo1.Lines.Add('   ' + GetCPUInfo);
    Memo1.Lines.Add('');
    Memo1.Lines.Add('[MEMORY & PAGEFILE]');
    Memo1.Lines.Add('   ' + GetMemoryInfo);
    Memo1.Lines.Add('');
    Memo1.Lines.Add('[VIDEO ADAPTER & DISPLAY]');
    Memo1.Lines.Add('   Adapter         : ' + StringReplace(GetVideoInfo, #13#10, #13#10'                     ', [rfReplaceAll]));
    Memo1.Lines.Add('   Current Mode    : ' + GetScreenInfo);
    Memo1.Lines.Add('');
    Memo1.Lines.Add('[STORAGE DRIVES]');
    Memo1.Lines.Add('   ' + StringReplace(GetDrivesInfo, #13#10, #13#10'   ', [rfReplaceAll]));
    Memo1.Lines.Add('');
    Memo1.Lines.Add('===============================================================');
  finally
    Memo1.Lines.EndUpdate;
  end;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  CollectSystemInfo;
end;

procedure TForm1.Button1Click(Sender: TObject);
begin
  Button1.Enabled := False;
  try
    CollectSystemInfo;
  finally
    Button1.Enabled := True;
  end;
end;

procedure TForm1.Button2Click(Sender: TObject);
var
  SaveDlg: TSaveDialog;
begin
  SaveDlg := TSaveDialog.Create(Self);
  try
    SaveDlg.Title := 'Save Hardware Diagnostic Report';
    SaveDlg.Filter := 'Text Files (*.txt)|*.txt|All Files (*.*)|*.*';
    SaveDlg.DefaultExt := 'txt';
    SaveDlg.FileName := 'SysInfo_Report.txt';
    if SaveDlg.Execute then
    begin
      Memo1.Lines.SaveToFile(SaveDlg.FileName);
      ShowMessage('Report saved successfully!');
    end;
  finally
    SaveDlg.Free;
  end;
end;

procedure TForm1.Button3Click(Sender: TObject);
begin
  Clipboard.AsText := Memo1.Lines.Text;
  ShowMessage('Report copied to clipboard!');
end;

end.
