@echo off
if x%1 == x goto default
if %1 == --default-nativecomp goto nativecomp
if %1 == --clean goto clean
if %1 == --clean-all goto cleanall
if %1==--help goto help
if %1==-h goto help
if %1==-? goto help
goto run

:cleanall
cd %~dp0 && for %%i in (git build zips pkg) do if exist %%i rmdir /S /Q %%i
goto:eof

:clean
cd %~dp0 && for %%i in (build pkg) do if exist %%i rmdir /S /Q %%i
goto:eof

:default
emacs-build.cmd --clone --deps --build --pack-emacs --pdf-tools --mu --isync --aspell --pack-all
goto:eof

:nativecomp
emacs-build.cmd --nativecomp --clone --deps --build --pack-emacs --pdf-tools --mu --isync --aspell --pack-all
goto:eof

:help
cd %~dp0
powershell -noprofile -c scripts\setup-msys2.ps1
.\scripts\msys2.cmd -c "./emacs-build.sh --help"
goto:eof

:run
cd %~dp0
powershell -noprofile -c scripts\setup-msys2.ps1
.\scripts\msys2.cmd -c "./emacs-build.sh %*"
