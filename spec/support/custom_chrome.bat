set DIRPATH=%~dp0
type nul >> %DIRPATH%\custom_chrome_called
set /p CHROME=<%DIRPATH%\chrome_path
rem echo %CHROME% %* > %DIRPATH%\chrome_executed
"%CHROME%" %*
