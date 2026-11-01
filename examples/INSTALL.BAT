@echo off
rem Install the release files into a *slow-boot* Windows 1.01 tree.
rem This assumes the files are on A: and Windows is in C:\WINDOWS.
rem
rem A fast-boot install (WIN100.BIN/WIN100.OVL) links USER/GDI/DISPLAY
rem into the binary; copying these files is not enough.  Use SETUP for a
rem fast-boot installation, or convert the tree to slow-boot first.
rem
rem Back up the originals before running this.

if not exist C:\WINDOWS\KERNEL.EXE goto fastboot
if not exist C:\WINDOWS\USER.EXE goto fastboot
if not exist C:\WINDOWS\GDI.EXE goto fastboot

echo Backing up stock files to C:\WINDOWS\*.STK ...
if not exist C:\WINDOWS\USER.STK  copy C:\WINDOWS\USER.EXE  C:\WINDOWS\USER.STK
if not exist C:\WINDOWS\GDI.STK   copy C:\WINDOWS\GDI.EXE   C:\WINDOWS\GDI.STK
if not exist C:\WINDOWS\FONTS.STK copy C:\WINDOWS\FONTS.FON C:\WINDOWS\FONTS.STK
if not exist C:\WINDOWS\MSDOS.STK copy C:\WINDOWS\MSDOS.EXE C:\WINDOWS\MSDOS.STK

echo Installing overlap USER/GDI ...
copy /y A:\USER.EXE  C:\WINDOWS\USER.EXE
copy /y A:\GDI.EXE   C:\WINDOWS\GDI.EXE
echo Installing proportional System + Fixedsys ...
copy /y A:\FONTS.FON C:\WINDOWS\FONTS.FON
copy /y A:\MSDOS.EXE C:\WINDOWS\MSDOS.EXE
echo Installing VGA 640x480 driver ...
copy /y A:\VGAHIRES.DRV C:\WINDOWS\DISPLAY.DRV

echo Done. Reboot Windows.
goto end

:fastboot
echo This does not look like a slow-boot tree (KERNEL/USER/GDI .EXE missing).
echo Use Windows 1.01 SETUP; see docs/INSTALL.md.

:end
