@echo off
set JAVA_HOME=C:\Program Files\Java\jdk-17
cd /d %~dp0\..
call gradlew.bat assembleRelease
if %ERRORLEVEL% EQU 0 (
    echo.
    echo APK built successfully!
    echo APK location: android\app\build\outputs\apk\release\app-release.apk
) else (
    echo Build failed!
    exit /b %ERRORLEVEL%
)

