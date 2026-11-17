@echo off
setlocal
rem ctbrec 5.4.4 fix-pack deploy script  (ASCII only, no encoding surprises)
rem Overwrites the jar that MANIFEST.MF actually names: lib\common-5.3.4.jar
rem Overwriting lib\common-5.4.4.jar does NOT take effect - that file is never loaded.
rem
rem usage:  deploy.bat "D:\ctbrec-fixed-544"
set TARGET=%~1
if "%TARGET%"=="" set TARGET=D:\ctbrec-fixed-544

if not exist "%TARGET%\lib" (
  echo [!] not a ctbrec install dir: %TARGET%
  echo     example: deploy.bat "D:\ctbrec-fixed-544"
  exit /b 1
)

if not exist "%~dp0dist\common-5.3.4.jar" (
  echo [!] missing %~dp0dist\common-5.3.4.jar
  exit /b 1
)

for %%F in (common-5.3.4.jar) do (
  if exist "%TARGET%\lib\%%F" (
    copy /Y "%TARGET%\lib\%%F" "%TARGET%\lib\%%F.bak" >nul
    echo [i] backed up -> %TARGET%\lib\%%F.bak
  )
)

copy /Y "%~dp0dist\common-5.3.4.jar" "%TARGET%\lib\common-5.3.4.jar"
if errorlevel 1 (
  echo [!] copy failed - is ctbrec still running? close it first.
  exit /b 1
)

echo [OK] deployed -^> %TARGET%\lib\common-5.3.4.jar
echo [i] verified key pair compiled as defaults:
echo        pkey    = NTK9aqcLmNFMWrpQ   ^(keyId sent in query string^)
echo        xorKey  = tOcYOap4Ty1l9Jzb   ^(decodes segment names^)
echo [i] optional: start with %TARGET%\ctbrec.bat  ^(not the old 05-15 install^)
endlocal
