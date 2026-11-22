# SysInfo_by_MarkFH
User-Mode Hardware diagnostics written in delphi 7 (win95 to win11)

KNOWN BUGS
## Why User-Mode?
Classic tools like AIDA32 or EVEREST use low-level kernel drivers, which often cause a BSOD (Blue Screen of Death) when running Windows 98 on modern hardware. SysInfo_by_MarkFH works strictly in User-Mode (using standard Win32 APIs), making it completely safe to run on modern PCs without crashing the system.
