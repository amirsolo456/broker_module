@echo off
setlocal

set GRADLE_PROPS=android\gradle.properties
set DEBUG_DIR=%USERPROFILE%\.android
set DEBUG_KEYSTORE=%DEBUG_DIR%\debug.keystore

echo Adding Network fixes to %GRADLE_PROPS%...
echo org.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m >> %GRADLE_PROPS%
echo android.useAndroidX=true >> %GRADLE_PROPS%
echo android.enableJetifier=true >> %GRADLE_PROPS%

if not exist "%DEBUG_DIR%" mkdir "%DEBUG_DIR%"

if not exist "%DEBUG_KEYSTORE%" (
    echo Creating standard Android debug keystore...
    "%JAVA_HOME%\bin\keytool.exe" -genkeypair -v ^
        -keystore "%DEBUG_KEYSTORE%" ^
        -storepass android ^
        -alias AndroidDebugKey ^
        -keypass android ^
        -keyalg RSA ^
        -keysize 2048 ^
        -validity 10000 ^
        -dname "CN=Android Debug,O=Android,C=US"
    if errorlevel 1 (
        echo Failed to create debug keystore.
        echo Make sure JAVA_HOME points to a JDK installation.
        exit /b 1
    )
) else (
    echo Android debug keystore already exists.
)

echo Done.
pause
endlocal
