unit Unit1;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  StdCtrls, ComCtrls, ExtCtrls, CommCtrl, Registry, Clipbrd;

type
  TForm1 = class(TForm)
    PanelTop: TPanel;
    LblTitle: TLabel;
    LblSubtitle: TLabel;
    PanelAccent: TPanel;
    PageControl1: TPageControl;
    TabOverview: TTabSheet;
    TabWindows: TTabSheet;
    TabProcessor: TTabSheet;
    TabMemory: TTabSheet;
    TabVideo: TTabSheet;
    TabDisks: TTabSheet;
    lvOverview: TListView;
    lvWindows: TListView;
    lvProcessor: TListView;
    lvMemory: TListView;
    lvVideo: TListView;
    lvDisks: TListView;
    Button1: TButton;
    Button2: TButton;
    Button3: TButton;
    StatusBar1: TStatusBar;
    procedure FormCreate(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure Button3Click(Sender: TObject);
    procedure StandardListCustomDrawItem(Sender: TCustomListView;
      Item: TListItem; State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure StandardListCustomDrawSubItem(Sender: TCustomListView;
      Item: TListItem; SubItem: Integer; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    procedure lvDisksAdvancedCustomDrawItem(Sender: TCustomListView;
      Item: TListItem; State: TCustomDrawState; Stage: TCustomDrawStage;
      var DefaultDraw: Boolean);
    procedure lvDisksAdvancedCustomDrawSubItem(Sender: TCustomListView;
      Item: TListItem; SubItem: Integer; State: TCustomDrawState;
      Stage: TCustomDrawStage; var DefaultDraw: Boolean);
  private
    FReportLines: TStringList;
    procedure AddRow(LV: TListView; const PropName, PropVal: string);
    procedure CollectAllData;
    function GetCPUBrandStringFromCPUID: string;
    function GetCPUFallbackNameBySignature(const Vendor: string; Family, Model, Stepping, BrandID: Cardinal): string;
    function GetCPUFeatures: string;
    function MeasureCPUSpeedRDTSC: Cardinal;
  public
    destructor Destroy; override;
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
  TGetProductInfo = function(dwOSMajorVersion, dwOSMinorVersion, dwSpMajorVersion,
    dwSpMinorVersion: DWORD; var pdwReturnedProductType: DWORD): BOOL; stdcall;

  TSystemLogicalProcessorInformation = record
    ProcessorMask: DWORD;
    Relationship: Integer;
    Reserved: array[0..1] of Int64;
  end;
  PSystemLogicalProcessorInformation = ^TSystemLogicalProcessorInformation;

  TGetLogicalProcessorInformation = function(Buffer: PSystemLogicalProcessorInformation;
    var ReturnLength: DWORD): BOOL; stdcall;

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

function GetPhysicalCoresCount(LogicalCount: Integer): Integer;
var
  hKernel: THandle;
  GetLPI: TGetLogicalProcessorInformation;
  Buf: array of Byte;
  ReturnLen, Offset: DWORD;
  Info: PSystemLogicalProcessorInformation;
  Cores: Integer;
begin
  Result := LogicalCount;
  hKernel := GetModuleHandle('kernel32.dll');
  if hKernel = 0 then Exit;

  @GetLPI := GetProcAddress(hKernel, 'GetLogicalProcessorInformation');
  if not Assigned(GetLPI) then Exit;

  ReturnLen := 0;
  GetLPI(nil, ReturnLen);
  if (GetLastError <> ERROR_INSUFFICIENT_BUFFER) or (ReturnLen = 0) then Exit;

  SetLength(Buf, ReturnLen);
  if GetLPI(@Buf[0], ReturnLen) then
  begin
    Cores := 0;
    Offset := 0;
    while Offset + SizeOf(TSystemLogicalProcessorInformation) <= ReturnLen do
    begin
      Info := PSystemLogicalProcessorInformation(@Buf[Offset]);
      if Info^.Relationship = 0 then
        Inc(Cores);
      Inc(Offset, SizeOf(TSystemLogicalProcessorInformation));
    end;
    if Cores > 0 then
      Result := Cores;
  end;
end;

procedure TForm1.AddRow(LV: TListView; const PropName, PropVal: string);
var
  Item: TListItem;
begin
  Item := LV.Items.Add;
  Item.Caption := PropName;
  Item.SubItems.Add(PropVal);
end;

procedure TForm1.StandardListCustomDrawItem(Sender: TCustomListView;
  Item: TListItem; State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  Sender.Canvas.Font.Name := 'MS Sans Serif';
  Sender.Canvas.Font.Size := 8;
  Sender.Canvas.Font.Style := [];
  if not (cdsSelected in State) then
  begin
    Sender.Canvas.Font.Color := clBlack;
    if Odd(Item.Index) then
      Sender.Canvas.Brush.Color := $00F9F5F0
    else
      Sender.Canvas.Brush.Color := clWhite;
  end;
  DefaultDraw := True;
end;

procedure TForm1.StandardListCustomDrawSubItem(Sender: TCustomListView;
  Item: TListItem; SubItem: Integer; State: TCustomDrawState;
  var DefaultDraw: Boolean);
begin
  Sender.Canvas.Font.Name := 'MS Sans Serif';
  Sender.Canvas.Font.Size := 8;
  Sender.Canvas.Font.Style := [];
  if not (cdsSelected in State) then
  begin
    Sender.Canvas.Font.Color := clBlack;
    if Odd(Item.Index) then
      Sender.Canvas.Brush.Color := $00F9F5F0
    else
      Sender.Canvas.Brush.Color := clWhite;
  end;
  DefaultDraw := True;
end;

procedure TForm1.lvDisksAdvancedCustomDrawItem(Sender: TCustomListView;
  Item: TListItem; State: TCustomDrawState; Stage: TCustomDrawStage;
  var DefaultDraw: Boolean);
begin
  Sender.Canvas.Font.Name := 'MS Sans Serif';
  Sender.Canvas.Font.Size := 8;
  Sender.Canvas.Font.Style := [];
  if not (cdsSelected in State) then
  begin
    Sender.Canvas.Font.Color := clBlack;
    if Odd(Item.Index) then
      Sender.Canvas.Brush.Color := $00F9F5F0
    else
      Sender.Canvas.Brush.Color := clWhite;
  end;
  DefaultDraw := True;
end;

procedure TForm1.lvDisksAdvancedCustomDrawSubItem(Sender: TCustomListView;
  Item: TListItem; SubItem: Integer; State: TCustomDrawState;
  Stage: TCustomDrawStage; var DefaultDraw: Boolean);
var
  R, BarRect, FillRectBox: TRect;
  Pct, FillW: Integer;
  PctText: string;
begin
  Sender.Canvas.Font.Name := 'MS Sans Serif';
  Sender.Canvas.Font.Size := 8;
  Sender.Canvas.Font.Style := [];

  if SubItem <> 5 then
  begin
    if not (cdsSelected in State) then
    begin
      Sender.Canvas.Font.Color := clBlack;
      if Odd(Item.Index) then
        Sender.Canvas.Brush.Color := $00F9F5F0
      else
        Sender.Canvas.Brush.Color := clWhite;
    end;
    DefaultDraw := True;
    Exit;
  end;

  if Stage = cdPrePaint then
  begin
    ListView_GetSubItemRect(Sender.Handle, Item.Index, SubItem, LVIR_BOUNDS, @R);

    if cdsSelected in State then
      Sender.Canvas.Brush.Color := clHighlight
    else if Odd(Item.Index) then
      Sender.Canvas.Brush.Color := $00F9F5F0
    else
      Sender.Canvas.Brush.Color := clWhite;
    Sender.Canvas.FillRect(R);

    BarRect := R;
    InflateRect(BarRect, -4, -2);

    Sender.Canvas.Brush.Color := $00E6E6E6;
    Sender.Canvas.Pen.Color := $00999999;
    Sender.Canvas.Rectangle(BarRect.Left, BarRect.Top, BarRect.Right, BarRect.Bottom);

    Pct := Integer(Item.Data);
    if Pct >= 0 then
    begin
      if Pct > 100 then Pct := 100;
      FillW := Round(((BarRect.Right - BarRect.Left - 2) * Pct) / 100);
      if FillW > 0 then
      begin
        FillRectBox := Rect(BarRect.Left + 1, BarRect.Top + 1,
          BarRect.Left + 1 + FillW, BarRect.Bottom - 1);
        if Pct > 90 then
          Sender.Canvas.Brush.Color := $002828E0 // Red (> 90%)
        else
          Sender.Canvas.Brush.Color := $00D6781A; // Blue (<= 90%)
        Sender.Canvas.FillRect(FillRectBox);
      end;
      PctText := IntToStr(Pct) + '%';
    end
    else
      PctText := 'N/A';

    SetBkMode(Sender.Canvas.Handle, TRANSPARENT);
    Sender.Canvas.Font.Name := 'MS Sans Serif';
    Sender.Canvas.Font.Size := 8;
    Sender.Canvas.Font.Style := [];
    Sender.Canvas.Font.Color := clBlack;
    DrawText(Sender.Canvas.Handle, PChar(PctText), Length(PctText), BarRect,
      DT_CENTER or DT_VCENTER or DT_SINGLELINE);

    DefaultDraw := False;
  end;
end;

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
      Result := Trim(string(PAnsiChar(@Buf[0])));
      while Pos('  ', Result) > 0 do
        Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
    end;
  except
    Result := '';
  end;
end;

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
    if (rEDX and $10) = 0 then Exit;

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

procedure TForm1.CollectAllData;
var
  OSVI: TOSVersionInfoA;
  hNtDll, hKernel, hUser32: THandle;
  RtlGetVersion: TRtlGetVersion;
  GetProductInfo: TGetProductInfo;
  GetTickCount64: TGetTickCount64;
  IsWow64Process: TIsWow64Process;
  GlobalMemoryStatusEx: TGlobalMemoryStatusEx;
  EnumDisplayDevicesA: TEnumDisplayDevicesA;
  GetDiskFreeSpaceExA: TGetDiskFreeSpaceExA;

  ProductName, EditionID, DisplayVer, BuildStr, CSD, ArchStr, UptimeStr: string;
  Major, Minor, Build, ProdType: DWORD;
  CompName, UserName: array[0..255] of AnsiChar;
  WinDir, SysDir: array[0..MAX_PATH] of AnsiChar;
  Size: DWORD;
  IsWow64: BOOL;
  UptimeMs, Days, Hours, Mins, Secs: Int64;

  MoboManuf, MoboProd, BiosVendor, BiosVer, BiosDate, MoboStr, BiosStr: string;

  SysInfo: TSystemInfo;
  CPUName, Vendor, SigStr, ClockStr, FeatStr: string;
  rEAX, rEBX, rECX, rEDX: DWORD;
  Family, Model, Stepping, ExtFamily, ExtModel, BrandID: Cardinal;
  MHz, PhysCores: Integer;

  MemEx: TMemoryStatusEx;
  MemOld: TMemoryStatus;
  TotalPhysMB, AvailPhysMB, UsedPhysMB, TotalPageMB, AvailPageMB, TotalVirtMB: Int64;
  LoadPct: DWORD;
  MemSummaryStr, GPUStr, ScreenStr: string;
  DispDev: TDisplayDeviceA;
  i: DWORD;
  VideoList, SubKeys: TStringList;
  Reg: TRegistry;
  j: Integer;
  CardDesc: string;
  DC: HDC;
  WidthPx, HeightPx, BPP, Planes, RefreshRate: Integer;

  DrivesMask: DWORD;
  DriveLetter: Char;
  RootPath, TypeStr, VolLabel, FSName, CapStr: string;
  DType: UINT;
  VolNameBuf, FSNameBuf: array[0..255] of AnsiChar;
  SerialNum, MaxCompLen, FSFlags: DWORD;
  FreeAvail, TotalBytes, TotalFree: Int64;
  SecPerClus, BytesPerSec, FreeClus, TotalClus: DWORD;
  OldErrMode: UINT;
  Item: TListItem;
  UsedPct: Integer;
begin
  lvOverview.Items.BeginUpdate;
  lvWindows.Items.BeginUpdate;
  lvProcessor.Items.BeginUpdate;
  lvMemory.Items.BeginUpdate;
  lvVideo.Items.BeginUpdate;
  lvDisks.Items.BeginUpdate;
  try
    lvOverview.Items.Clear;
    lvWindows.Items.Clear;
    lvProcessor.Items.Clear;
    lvMemory.Items.Clear;
    lvVideo.Items.Clear;
    lvDisks.Items.Clear;
    FReportLines.Clear;

    FReportLines.Add('===============================================================');
    FReportLines.Add('   SysInfo by MarkFH v2.6  |  User-Mode Hardware Diagnostics');
    FReportLines.Add('===============================================================');

    hKernel := GetModuleHandle('kernel32.dll');
    hNtDll := GetModuleHandle('ntdll.dll');
    hUser32 := GetModuleHandle('user32.dll');

    // ---------------- 1. WINDOWS ----------------
    FillChar(OSVI, SizeOf(OSVI), 0);
    OSVI.dwOSVersionInfoSize := SizeOf(OSVI);
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
        if Build >= 1111 then ProductName := 'Microsoft Windows 95 OSR2'
        else ProductName := 'Microsoft Windows 95';
      end
      else if (Major = 4) and (Minor = 10) then
      begin
        if Build >= 2222 then ProductName := 'Microsoft Windows 98 Second Edition (SE)'
        else ProductName := 'Microsoft Windows 98';
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

      ProdType := 0;
      @GetProductInfo := GetProcAddress(hKernel, 'GetProductInfo');
      if Assigned(GetProductInfo) and GetProductInfo(Major, Minor, 0, 0, ProdType) then
      begin
        case ProdType of
          $00000030, $00000031: EditionID := 'Professional';
          $00000004, $0000001B: EditionID := 'Enterprise';
          $00000065, $00000062: EditionID := 'Home';
          $00000079:            EditionID := 'Education';
        end;
      end;

      if SameText(EditionID, 'Professional') and (Pos('Enterprise', ProductName) > 0) then
        ProductName := StringReplace(ProductName, 'Enterprise', 'Pro', [rfIgnoreCase])
      else if SameText(EditionID, 'Home') and (Pos('Enterprise', ProductName) > 0) then
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

    BuildStr := Format('%d.%d (Build %d)', [Major, Minor, Build]);
    if CSD <> '' then
      BuildStr := BuildStr + ' [' + CSD + ']';

    IsWow64 := False;
    @IsWow64Process := GetProcAddress(hKernel, 'IsWow64Process');
    if Assigned(IsWow64Process) then
      IsWow64Process(GetCurrentProcess, IsWow64);
    if IsWow64 then ArchStr := '64-bit (x64)' else ArchStr := '32-bit (x86)';

    Size := SizeOf(CompName);
    if not GetComputerNameA(CompName, Size) then StrPCopy(CompName, 'Unknown');
    Size := SizeOf(UserName);
    if not GetUserNameA(UserName, Size) then StrPCopy(UserName, 'Unknown');

    GetWindowsDirectoryA(WinDir, MAX_PATH);
    GetSystemDirectoryA(SysDir, MAX_PATH);

    @GetTickCount64 := GetProcAddress(hKernel, 'GetTickCount64');
    if Assigned(GetTickCount64) then UptimeMs := GetTickCount64
    else UptimeMs := DWORD(GetTickCount);

    Secs := UptimeMs div 1000;
    Days := Secs div 86400;
    Hours := (Secs mod 86400) div 3600;
    Mins := (Secs mod 3600) div 60;
    Secs := Secs mod 60;
    UptimeStr := Format('%d d, %d h, %d m, %d s', [Days, Hours, Mins, Secs]);

    AddRow(lvWindows, 'Operating System', ProductName);
    AddRow(lvWindows, 'Kernel Version', BuildStr);
    AddRow(lvWindows, 'Architecture', ArchStr);
    AddRow(lvWindows, 'Computer Name', string(CompName));
    AddRow(lvWindows, 'Current User', string(UserName));
    AddRow(lvWindows, 'System Uptime', UptimeStr);
    AddRow(lvWindows, 'Windows Folder', string(WinDir));
    AddRow(lvWindows, 'System Folder', string(SysDir));

    // ---------------- 2. MOTHERBOARD & BIOS ----------------
    MoboManuf := SafeReadRegString(HKEY_LOCAL_MACHINE, 'HARDWARE\DESCRIPTION\System\BIOS', 'BaseBoardManufacturer');
    MoboProd := SafeReadRegString(HKEY_LOCAL_MACHINE, 'HARDWARE\DESCRIPTION\System\BIOS', 'BaseBoardProduct');
    BiosVendor := SafeReadRegString(HKEY_LOCAL_MACHINE, 'HARDWARE\DESCRIPTION\System\BIOS', 'BIOSVendor');
    BiosVer := SafeReadRegString(HKEY_LOCAL_MACHINE, 'HARDWARE\DESCRIPTION\System\BIOS', 'BIOSVersion');
    BiosDate := SafeReadRegString(HKEY_LOCAL_MACHINE, 'HARDWARE\DESCRIPTION\System\BIOS', 'BIOSReleaseDate');

    if BiosVer = '' then
      BiosVer := SafeReadRegString(HKEY_LOCAL_MACHINE, 'HARDWARE\DESCRIPTION\System', 'SystemBiosVersion');
    if BiosDate = '' then
      BiosDate := SafeReadRegString(HKEY_LOCAL_MACHINE, 'HARDWARE\DESCRIPTION\System', 'SystemBiosDate');
    if MoboManuf = '' then
      MoboManuf := SafeReadRegString(HKEY_LOCAL_MACHINE, 'Enum\Root\*PNP0C01 0', 'BIOSName');

    MoboStr := Trim(MoboManuf + ' ' + MoboProd);
    if MoboStr = '' then MoboStr := 'Unknown / Legacy Motherboard';

    BiosStr := Trim(BiosVendor + ' ' + BiosVer);
    if BiosStr = '' then BiosStr := 'Standard / Legacy BIOS';
    if BiosDate <> '' then BiosStr := BiosStr + ' (' + BiosDate + ')';

    // ---------------- 3. PROCESSOR ----------------
    GetSystemInfo(SysInfo);
    Vendor := ''; SigStr := '';
    Family := 0; Model := 0; Stepping := 0; BrandID := 0;

    if IsCPUIDSupported then
    begin
      try
        ExecuteCPUID(0, rEAX, rEBX, rECX, rEDX);
        SetLength(Vendor, 12);
        Move(rEBX, Vendor[1], 4);
        Move(rEDX, Vendor[5], 4);
        Move(rECX, Vendor[9], 4);
        Vendor := Trim(Vendor);

        if rEAX >= 1 then
        begin
          ExecuteCPUID(1, rEAX, rEBX, rECX, rEDX);
          Stepping := rEAX and $0F;
          Model := (rEAX shr 4) and $0F;
          Family := (rEAX shr 8) and $0F;
          ExtModel := (rEAX shr 16) and $0F;
          ExtFamily := (rEAX shr 20) and $FF;
          BrandID := rEBX and $FF;

          if Family = 15 then Family := Family + ExtFamily;
          if (Family = 6) or (Family = 15) then Model := (ExtModel shl 4) + Model;

          SigStr := Format('Family %d (0x%X), Model %d (0x%X), Stepping %d',
            [Family, Family, Model, Model, Stepping]);
        end;
      except
      end;
    end;

    CPUName := GetCPUBrandStringFromCPUID;
    if CPUName = '' then
      CPUName := SafeReadRegString(HKEY_LOCAL_MACHINE, 'HARDWARE\DESCRIPTION\System\CentralProcessor ', 'ProcessorNameString');
    if (CPUName = '') and (Family > 0) then
      CPUName := GetCPUFallbackNameBySignature(Vendor, Family, Model, Stepping, BrandID);
    if CPUName = '' then
      CPUName := SafeReadRegString(HKEY_LOCAL_MACHINE, 'HARDWARE\DESCRIPTION\System\CentralProcessor ', 'Identifier');
    if CPUName = '' then
      CPUName := Format('x86 Processor (Level %d, Rev %d)', [SysInfo.wProcessorLevel, SysInfo.wProcessorRevision]);

    if Vendor = '' then
      Vendor := SafeReadRegString(HKEY_LOCAL_MACHINE, 'HARDWARE\DESCRIPTION\System\CentralProcessor ', 'VendorIdentifier');

    while Pos('  ', CPUName) > 0 do
      CPUName := StringReplace(CPUName, '  ', ' ', [rfReplaceAll]);

    MHz := SafeReadRegInteger(HKEY_LOCAL_MACHINE, 'HARDWARE\DESCRIPTION\System\CentralProcessor ', '~MHz');
    if MHz <= 0 then
      MHz := MeasureCPUSpeedRDTSC;

    PhysCores := GetPhysicalCoresCount(SysInfo.dwNumberOfProcessors);
    if MHz > 0 then
      ClockStr := Format('~%d MHz (%d Cores / %d Threads)', [MHz, PhysCores, SysInfo.dwNumberOfProcessors])
    else
      ClockStr := Format('Unknown MHz (%d Cores / %d Threads)', [PhysCores, SysInfo.dwNumberOfProcessors]);

    FeatStr := GetCPUFeatures;

    AddRow(lvProcessor, 'Processor Model', CPUName);
    AddRow(lvProcessor, 'Vendor ID', Vendor);
    AddRow(lvProcessor, 'CPUID Signature', SigStr);
    AddRow(lvProcessor, 'Clock & Cores', ClockStr);
    AddRow(lvProcessor, 'Instruction Sets', FeatStr);
    AddRow(lvProcessor, 'Motherboard', MoboStr);
    AddRow(lvProcessor, 'BIOS Version', BiosStr);

    // ---------------- 4. MEMORY ----------------
    TotalPhysMB := 0; AvailPhysMB := 0;
    TotalPageMB := 0; AvailPageMB := 0; TotalVirtMB := 0; LoadPct := 0;

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
        TotalVirtMB := MemEx.ullTotalVirtual div (1024 * 1024);
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
      TotalVirtMB := Int64(MemOld.dwTotalVirtual) div (1024 * 1024);
      LoadPct := MemOld.dwMemoryLoad;
    end;

    UsedPhysMB := TotalPhysMB - AvailPhysMB;
    if UsedPhysMB < 0 then UsedPhysMB := 0;

    MemSummaryStr := Format('%d MB Total | %d MB Free (%d%% Load)', [TotalPhysMB, AvailPhysMB, LoadPct]);

    AddRow(lvMemory, 'Total Physical RAM', Format('%d MB', [TotalPhysMB]));
    AddRow(lvMemory, 'Used Physical RAM', Format('%d MB (%d%%)', [UsedPhysMB, LoadPct]));
    AddRow(lvMemory, 'Free Physical RAM', Format('%d MB', [AvailPhysMB]));
    AddRow(lvMemory, 'Page / Commit Total', Format('%d MB', [TotalPageMB]));
    AddRow(lvMemory, 'Page / Commit Free', Format('%d MB', [AvailPageMB]));
    AddRow(lvMemory, 'Virtual Address Space', Format('%d MB', [TotalVirtMB]));

    // ---------------- 5. VIDEO ----------------
    VideoList := TStringList.Create;
    try
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
        GPUStr := StringReplace(Trim(VideoList.Text), #13#10, ', ', [rfReplaceAll])
      else
        GPUStr := 'Standard Display Adapter';
    finally
      VideoList.Free;
    end;

    DC := GetDC(0);
    try
      WidthPx := GetDeviceCaps(DC, HORZRES);
      HeightPx := GetDeviceCaps(DC, VERTRES);
      BPP := GetDeviceCaps(DC, BITSPIXEL);
      Planes := GetDeviceCaps(DC, PLANES);
      if (BPP <= 8) and (Planes > 1) and (Planes <= 8) then
        BPP := BPP * Planes;
      RefreshRate := GetDeviceCaps(DC, VREFRESH);
    finally
      ReleaseDC(0, DC);
    end;

    if RefreshRate > 1 then
      ScreenStr := Format('%d x %d pixels, %d-bit (%d Hz)', [WidthPx, HeightPx, BPP, RefreshRate])
    else
      ScreenStr := Format('%d x %d pixels, %d-bit', [WidthPx, HeightPx, BPP]);

    AddRow(lvVideo, 'Graphics Adapter', GPUStr);
    AddRow(lvVideo, 'Screen Resolution', Format('%d x %d pixels', [WidthPx, HeightPx]));
    AddRow(lvVideo, 'Color Depth', Format('%d-bit', [BPP]));
    if RefreshRate > 1 then
      AddRow(lvVideo, 'Refresh Rate', Format('%d Hz', [RefreshRate]))
    else
      AddRow(lvVideo, 'Refresh Rate', 'Default / Hardware');

    // ---------------- OVERVIEW TAB ----------------
    AddRow(lvOverview, 'Operating System', ProductName + ' (' + ArchStr + ')');
    AddRow(lvOverview, 'Processor (CPU)', CPUName);
    AddRow(lvOverview, 'CPU Speed & Cores', ClockStr);
    AddRow(lvOverview, 'Motherboard', MoboStr);
    AddRow(lvOverview, 'BIOS', BiosStr);
    AddRow(lvOverview, 'Physical Memory', MemSummaryStr);
    AddRow(lvOverview, 'Video Adapter', GPUStr);
    AddRow(lvOverview, 'Display Mode', ScreenStr);
    AddRow(lvOverview, 'System Uptime', UptimeStr);

    // Text report
    FReportLines.Add('[WINDOWS]');
    FReportLines.Add('   OS           : ' + ProductName);
    FReportLines.Add('   Version      : ' + BuildStr + ' | ' + ArchStr);
    FReportLines.Add('   Computer/User: ' + string(CompName) + ' / ' + string(UserName));
    FReportLines.Add('   Uptime       : ' + UptimeStr);
    FReportLines.Add('');
    FReportLines.Add('[PROCESSOR & MOTHERBOARD]');
    FReportLines.Add('   Model        : ' + CPUName + ' [' + Vendor + ']');
    FReportLines.Add('   Signature    : ' + SigStr);
    FReportLines.Add('   Clock/Cores  : ' + ClockStr);
    FReportLines.Add('   Instructions : ' + FeatStr);
    FReportLines.Add('   Motherboard  : ' + MoboStr);
    FReportLines.Add('   BIOS         : ' + BiosStr);
    FReportLines.Add('');
    FReportLines.Add('[MEMORY]');
    FReportLines.Add('   Physical RAM : ' + MemSummaryStr);
    FReportLines.Add(Format('   Page File    : %d MB Total | %d MB Free', [TotalPageMB, AvailPageMB]));
    FReportLines.Add('');
    FReportLines.Add('[VIDEO]');
    FReportLines.Add('   Adapter      : ' + GPUStr);
    FReportLines.Add('   Display Mode : ' + ScreenStr);
    FReportLines.Add('');
    FReportLines.Add('[DISKS]');

    // ---------------- 6. DISKS ----------------
    OldErrMode := SetErrorMode(SEM_FAILCRITICALERRORS);
    try
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

          if VolLabel = '' then VolLabel := 'No Label';
          if FSName = '' then FSName := '-';

          if TotalBytes > 0 then
          begin
            CapStr := Format('%d MB / %d MB free',
              [TotalBytes div (1024 * 1024), TotalFree div (1024 * 1024)]);
            UsedPct := Round(((TotalBytes - TotalFree) * 100.0) / TotalBytes);
            if UsedPct < 0 then UsedPct := 0;
            if UsedPct > 100 then UsedPct := 100;
          end
          else
          begin
            CapStr := 'Media not ready';
            UsedPct := -1;
          end;

          Item := lvDisks.Items.Add;
          Item.Caption := DriveLetter + ':';
          Item.Data := Pointer(UsedPct);
          Item.SubItems.Add(TypeStr);
          Item.SubItems.Add(VolLabel);
          Item.SubItems.Add(FSName);
          Item.SubItems.Add(CapStr);
          if UsedPct >= 0 then
            Item.SubItems.Add(IntToStr(UsedPct) + '%')
          else
            Item.SubItems.Add('N/A');

          FReportLines.Add(Format('   %s [%s] (%s, %s) - %s',
            [DriveLetter + ':', TypeStr, VolLabel, FSName, CapStr]));
        end;
      end;
    finally
      SetErrorMode(OldErrMode);
    end;

    StatusBar1.Panels[0].Text := 'Scan complete | ' + ProductName;
  finally
    lvOverview.Items.EndUpdate;
    lvWindows.Items.EndUpdate;
    lvProcessor.Items.EndUpdate;
    lvMemory.Items.EndUpdate;
    lvVideo.Items.EndUpdate;
    lvDisks.Items.EndUpdate;
  end;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  FReportLines := TStringList.Create;
  CollectAllData;
end;

destructor TForm1.Destroy;
begin
  FReportLines.Free;
  inherited;
end;

procedure TForm1.Button1Click(Sender: TObject);
begin
  Button1.Enabled := False;
  StatusBar1.Panels[0].Text := 'Refreshing hardware info...';
  Application.ProcessMessages;
  try
    CollectAllData;
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
      FReportLines.SaveToFile(SaveDlg.FileName);
      StatusBar1.Panels[0].Text := 'Report saved to ' + ExtractFileName(SaveDlg.FileName);
    end;
  finally
    SaveDlg.Free;
  end;
end;

procedure TForm1.Button3Click(Sender: TObject);
begin
  Clipboard.AsText := FReportLines.Text;
  StatusBar1.Panels[0].Text := 'Report copied to clipboard!';
end;

end.
