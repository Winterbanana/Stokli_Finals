@echo off
setlocal

set "ROOT=%~dp0"
set "XAMPP=C:\xampp"
set "MYSQL=%XAMPP%\mysql\bin\mysql.exe"
set "MYSQLADMIN=%XAMPP%\mysql\bin\mysqladmin.exe"
set "APACHE=%XAMPP%\apache\bin\httpd.exe"
set "SPACE=%%20"
set "API_LOCAL=http://127.0.0.1/Stokli%SPACE%BMC/api/index.php?action=health"

if not exist "%MYSQL%" (
  echo XAMPP MySQL was not found at %XAMPP%.
  echo Update the XAMPP path in launch_stokli.bat and try again.
  pause
  exit /b 1
)
if not exist "%APACHE%" (
  echo XAMPP Apache was not found at %XAMPP%.
  echo Update the XAMPP path in launch_stokli.bat and try again.
  pause
  exit /b 1
)
if not exist "%ROOT%database\stokli_bmc.sql" (
  echo The database import file is missing:
  echo %ROOT%database\stokli_bmc.sql
  pause
  exit /b 1
)

echo Starting XAMPP MySQL...
"%MYSQLADMIN%" -h 127.0.0.1 -uroot ping >nul 2>&1
if errorlevel 1 (
  pushd "%XAMPP%"
  start "Stokli MySQL" /min cmd /c "mysql\bin\mysqld --defaults-file=mysql\bin\my.ini --standalone"
  popd
)

for /L %%I in (1,1,30) do (
  "%MYSQLADMIN%" -h 127.0.0.1 -uroot ping >nul 2>&1
  if not errorlevel 1 goto MYSQL_READY
  timeout /t 1 /nobreak >nul
)
echo MySQL did not start. Check the XAMPP MySQL log and root account settings.
pause
exit /b 1

:MYSQL_READY
echo Checking Stokli database...
"%MYSQL%" -h 127.0.0.1 -uroot -N -e "SHOW DATABASES LIKE 'stokli_bmc';" 2>nul | findstr /x /c:"stokli_bmc" >nul
if errorlevel 1 (
  echo Importing the initial Stokli database...
  "%MYSQL%" -h 127.0.0.1 -uroot < "%ROOT%database\stokli_bmc.sql"
  if errorlevel 1 (
    echo Database import failed. Check the XAMPP MySQL credentials and SQL error above.
    pause
    exit /b 1
  )
)

echo Starting XAMPP Apache...
curl.exe --silent --fail --max-time 2 "%API_LOCAL%" >nul 2>&1
if errorlevel 1 (
  start "Stokli Apache" /min "%APACHE%" -f "%XAMPP%\apache\conf\httpd.conf"
)

for /L %%I in (1,1,30) do (
  curl.exe --silent --fail --max-time 2 "%API_LOCAL%" >nul 2>&1
  if not errorlevel 1 goto API_READY
  timeout /t 1 /nobreak >nul
)
echo The API did not respond. Check Apache, PHP, and api\config.php.
echo Local API: %API_LOCAL%
pause
exit /b 1

:API_READY
echo.
echo Stokli API and database are ready.
echo Local API: %API_LOCAL%
for /f "delims=" %%I in ('powershell -NoProfile -Command "foreach ($address in [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName())) { if ($address.AddressFamily -eq 2 -and $address.ToString() -notlike '127.*' -and $address.ToString() -notlike '169.254.*') { $address.ToString(); break } }"') do if not defined LAN_IP set "LAN_IP=%%I"
if defined LAN_IP echo Phone API: http://%LAN_IP%/Stokli%SPACE%BMC/api/index.php
echo.
echo On a phone, connect to the same Wi-Fi and use the Phone API address above.
echo Allow Apache through Windows Firewall on your private network if prompted.
echo.

if "%STOKLI_SKIP_FLUTTER%"=="1" exit /b 0

where.exe flutter >nul 2>&1
if errorlevel 1 (
  echo Flutter was not found on PATH. Install Flutter, connect an Android device,
  echo then run: cd mobile ^&^& flutter run
  pause
  exit /b 1
)

pushd "%ROOT%mobile"
flutter run
set "FLUTTER_EXIT=%ERRORLEVEL%"
popd
if not "%FLUTTER_EXIT%"=="0" (
  echo Flutter could not launch. Connect a phone with USB debugging enabled
  echo or start an Android emulator, then run launch_stokli.bat again.
  pause
  exit /b %FLUTTER_EXIT%
)
