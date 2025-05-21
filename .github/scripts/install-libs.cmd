@echo off

cd %~dp0
powershell -noprofile -c ..\..\scripts\setup-msys2.ps1
..\..\scripts\msys2.cmd -c "./install-libs.sh %*"
