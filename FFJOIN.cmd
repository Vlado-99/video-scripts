@echo off
setlocal EnableExtensions EnableDelayedExpansion
title JOIN using ffmpeg

set "OUT=%~1\joined.ts"
if exist "%OUT%" (
	echo File already exists: "%OUT%"
	pause
	goto :EOF
)

rem set TMPFILE=%TEMP%\FFJOIN-%RANDOM%.txt
rem (for %%f in ("%~1\*.ts") do @echo file '%%f') > "%TMPFILE%"
rem type "%TMPFILE%"
rem pause

rem @echo on
rem "c:\mediatools\ffmpeg\bin\ffmpeg" -hide_banner ^
rem   -f concat -safe 0 -i "%TMPFILE%" ^
rem   -vcodec copy -c:a copy ^
rem   -map 0 ^
rem   "%OUT%"
rem @echo off

rem echo.
rem echo.
rem @pause
rem goto :EOF

set FILES=
rem set MAPS= # mame len jeden vstup, vysledok concat operacie
set N=0
for %%f in ("%~1\*.ts") do (
	set "FILES=!FILES!|%%f"
	rem set "MAPS=!MAPS! -map %N%"
	set /A N=N+1
)
set "FILES=%FILES:~1%"

@echo on
"c:\mediatools\ffmpeg\bin\ffmpeg" -hide_banner ^
  -i "concat:%FILES%" ^
  -vcodec copy -c:a copy ^
  -map 0:1 -map 0:4 ^
  "%OUT%"
@echo off

echo.
echo.
@pause
