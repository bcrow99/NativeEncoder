@echo off
rem Regression test for NativeWriter / NativeReader (Windows): as run_tests.sh.
rem
rem   test\run_tests.bat <image> [out_dir]
rem
rem Compiles everything, then for 1 band and 4 bands: NativeWriter writes the
rem image (test.Drive, Save's defaults), NativeReader decodes it (test.Decode),
rem and for bluejay.jpg (bcrow99/TestImages) the size and the decoded image's
rem MD5 are checked. Native methods must keep these the same.
setlocal enabledelayedexpansion
set HERE=%~dp0..
set IMAGE=%~f1
set OUT=%~2
if "%IMAGE%"=="" (echo usage: test\run_tests.bat ^<image^> [out_dir] & exit /b 1)
if "%OUT%"=="" set OUT=out
if not exist "%OUT%\classes" mkdir "%OUT%\classes"
javac --release 8 -nowarn -Xlint:-options -Xlint:-unchecked -encoding UTF-8 -d "%OUT%\classes" "%HERE%\*.java" "%HERE%\test\*.java" || exit /b 1
cd /d "%OUT%"
set SIZE_n1=61174
set SIZE_n4=62689
set MD5=7c41049db7c073c7026278bcf58b15a5
set FAIL=0
for %%j in (n1 n4) do (
	set JOB=%%j
	set BANDS=!JOB:~1!
	java -cp classes test.Drive NativeWriter "%IMAGE%" %%j.bin 30 bands=!BANDS! > %%j.log 2>&1
	if errorlevel 1 (echo %%j: writer failed, see %%j.log & set FAIL=1) else (
		for %%f in (%%j.bin) do set SIZE=%%~zf
		for /f "tokens=2" %%m in ('java -Djava.awt.headless=true -cp classes test.Decode %%j.bin 2^>nul') do set GOT=%%m
		set STATUS=ok
		if /i "%~nx1"=="bluejay.jpg" (
			if not "!SIZE!"=="!SIZE_%%j!" (set STATUS=FAILED: expected !SIZE_%%j! bytes & set FAIL=1)
			if not "!GOT!"=="%MD5%" (set STATUS=FAILED: decoded MD5 differs & set FAIL=1)
		)
		echo %%j  !BANDS! band^(s^)  !SIZE! bytes  !GOT!  !STATUS!
	)
)
exit /b %FAIL%
