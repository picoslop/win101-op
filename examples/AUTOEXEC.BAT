@echo off
rem Example AUTOEXEC.BAT for a slow-boot Windows 1.01 disk.
rem MOUSE.COM /C1 /R1 forces a Microsoft serial mouse on COM1 at 30 Hz,
rem avoiding the driver's Inport/PS2 probe.  Remove or change the line if
rem your machine uses a different mouse.
C:\WINDOWS\MOUSE.COM /C1 /R1
cd c:\windows
win
