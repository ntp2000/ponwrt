@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem Pure CMD. Server and bounded endpoint header capture run in separate windows.
set "mode=%~1"
if /i "!mode!"=="server" goto server
if /i "!mode!"=="capture" goto capture
if /i "!mode!"=="cpu" goto cpu
goto usage
:server
set "output=%~2"
set "iperf=%~3"
if not defined iperf set "iperf=iperf3.exe"
if not defined output goto usage
if not "%~4"=="" goto usage
call :newdir
if errorlevel 1 exit /b 2
"!iperf!" --version >"!output!\version.txt" 2>&1
if errorlevel 1 exit /b 2
"!iperf!" --help >"!output!\help.txt" 2>&1
set "flush="
findstr /l /c:"--forceflush" "!output!\help.txt" >nul && set "flush=--forceflush"
call :metadata before
>"!output!\server.txt" echo !DATE! !TIME! command="!iperf!" -s -p 5201 -i 1 !flush!
echo Server running. Stop with Ctrl+C after ALL tests of this topology.
echo Keep this directory even if CMD asks to terminate the batch job.
"!iperf!" -s -p 5201 -i 1 !flush! >>"!output!\server.txt" 2>&1
set "rc=!errorlevel!"
call :metadata after
>>"!output!\server.txt" echo !DATE! !TIME! server_exit=!rc!
exit /b !rc!
:capture
set "nic=%~2"
set "peer=%~3"
set "output=%~4"
set "seconds=%~5"
if not defined seconds set "seconds=300"
if not defined nic goto usage
if not defined peer goto usage
if not defined output goto usage
for /f "delims=0123456789" %%V in ("!nic!") do goto usage
for /f "delims=0123456789." %%V in ("!peer!") do goto usage
for /f "delims=0123456789" %%V in ("!seconds!") do goto usage
if !seconds! LSS 30 goto usage
if !seconds! GTR 600 goto usage
if not "%~6"=="" goto usage
set "dumpcap=%ProgramFiles%\Wireshark\dumpcap.exe"
if not exist "!dumpcap!" set "dumpcap=dumpcap.exe"
call :newdir
if errorlevel 1 exit /b 2
"!dumpcap!" -v >"!output!\capture-version.txt" 2>&1
if errorlevel 1 (
 echo ERROR: Install Wireshark with Npcap, or put dumpcap.exe on PATH.
 exit /b 2
)
"!dumpcap!" -D >"!output!\capture-interfaces.txt" 2>&1
"!dumpcap!" -i !nic! -L >"!output!\capture-ready.txt" 2>&1
if errorlevel 1 (
 echo ERROR: Capture interface is unavailable. Keep capture-ready.txt.
 exit /b 2
)
call :metadata before
>"!output!\capture.txt" (
 echo !DATE! !TIME! interface=!nic! peer=!peer! seconds=!seconds!
 echo snaplen=128 ring_files=8 file_kib=524288 scope=TCP5201
 echo TSO/RSC may merge endpoint packets; checksum offload is not corruption proof.
 echo Capture is endpoint traffic, not router hardware-forwarding visibility.
)
echo Capturing TCP headers for !seconds! seconds; this window stops automatically.
"!dumpcap!" -i !nic! -f "host !peer! and tcp port 5201" -s 128 -B 16 -b filesize:524288 -b files:8 -a duration:!seconds! -w "!output!\tcp.pcapng" >>"!output!\capture.txt" 2>&1
set "rc=!errorlevel!"
call :metadata after
>>"!output!\capture.txt" echo !DATE! !TIME! capture_exit=!rc!
exit /b !rc!
rem Finite endpoint CPU sampling; typeperf counter names depend on Windows locale.
:cpu
set "output=%~2"
set "seconds=%~3"
if not defined seconds set "seconds=300"
if not defined output goto usage
if not "%~4"=="" goto usage
for /f "delims=0123456789" %%V in ("!seconds!") do goto usage
if !seconds! LSS 30 goto usage
if !seconds! GTR 600 goto usage
call :newdir
if errorlevel 1 exit /b 2
call :metadata before
tasklist >"!output!\processes.txt" 2>&1
>"!output!\cpu-status.txt" echo start=!DATE! !TIME! seconds=!seconds! source=typeperf
rem %% is a literal percent in a BAT file. Keep errors, never substitute zero CPU.
typeperf "\Processor(_Total)\%% Processor Time" -si 1 -sc !seconds! -f CSV -o "!output!\cpu.csv" >"!output!\typeperf.txt" 2>&1
set "rc=!errorlevel!"
>>"!output!\cpu-status.txt" echo end=!DATE! !TIME! exit_code=!rc!
if not "!rc!"=="0" (
 >>"!output!\cpu-status.txt" echo unavailable=counter_locale_or_typeperf_failure
 typeperf -qx >"!output!\available-counters.txt" 2>&1
)
exit /b !rc!
:newdir
if exist "!output!" (
 echo ERROR: Use a new directory; existing evidence is preserved.
 exit /b 2
)
mkdir "!output!" 2>nul
exit /b !errorlevel!
:metadata
>"!output!\%~1.txt" (
 echo local_time=!DATE! !TIME!
 tzutil /g
 w32tm /query /status
 ipconfig /all
 netsh interface tcp show global
 netsh interface ipv4 show subinterfaces
 netstat -e
 netstat -s -p tcp
)
exit /b 0
:usage
echo Usage: %~nx0 server NEW_DIR [PATH_TO_IPERF3.EXE]
echo        %~nx0 capture NIC_INDEX TEST_SERVER_IPV4 NEW_DIR [SECONDS_30_TO_600]
echo        %~nx0 cpu NEW_DIR [SECONDS_30_TO_600]
echo Find NIC_INDEX using "%%ProgramFiles%%\Wireshark\dumpcap.exe" -D
exit /b 2
