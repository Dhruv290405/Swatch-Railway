@echo off
set JAVA_HOME=E:\android studio\jbr
set PATH=%JAVA_HOME%\bin;%PATH%
cd /d "E:\swach railways 1\app"
D:\flutter\bin\flutter.bat build apk --release --no-pub > E:\flutter_build.log 2>&1