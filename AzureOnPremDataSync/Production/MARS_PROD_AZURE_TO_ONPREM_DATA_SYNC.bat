@ECHO OFF
cd /d %~dp0
SET THISPATH=D:\Apps\MARSScripts\AzureOnPremDataSync\Production

SET SRC_SERVER=summitprod.database.windows.net
SET SRC_DB=MARS
SET SRC_LOGIN=simsa
SET SRC_PASSWORD="D3n^3r#$Pr0d"

SET TGT_SERVER=SIM-SVR07\SIMGP
SET TGT_DB=MARS
SET TGT_LOGIN=SummitAdmin
SET TGT_PASSWORD=Summ1t4dm1n

for /f %%I in ('wmic os get localdatetime ^|find "20"') do set dt=%%I
set YYYYMMDD=%dt:~0,4%%dt:~4,2%%dt:~6,2%
set MMDDYYYYHHmmSS=%dt:~4,2%/%dt:~6,2%/%dt:~0,4% %dt:~8,2%:%dt:~10,2%:%dt:~12,2%

SET LogFile="%THISPATH%\MARS_PROD_AZURE_TO_ONPREM_DATA_SYNC_%YYYYMMDD%.log"
CALL :dataCompare 
CALL :cleanOldfiles 
CALL :callPS PSSqlWriterScript
CALL :updateAsOfDate 
exit /b

:callPS label
ECHO Calling local powershell script %1  >> %LogFile% 2>&1
powerShell.exe -ExecutionPolicy RemoteSigned -Command "$script = Get-Content '%~f0'; Invoke-Expression -Command ($script[(($script | select-string '::%1::').LineNumber)..(($script | select-string '::%1End::').LineNumber-2)] -join [environment]::NewLine)"
ECHO Local powershell script %1 completed  >> %LogFile% 2>&1
EXIT /b

----------------

::PSSqlWriterScript::
"SET NOCOUNT ON;
DECLARE @AsOfId INT;
DECLARE @NowInDenver DATETIME;
SET @NowInDenver = CONVERT( DATETIME, '$(Get-Date -format 'G')');

SELECT @AsOfId = AsOfId FROM dbo.tbl_DBAsof 
WHERE AsOfDate BETWEEN CAST(DATEADD(DD, -1, @NowInDenver) AS DATE) AND CAST(@NowInDenver AS DATE);
IF (@AsOfId IS NULL) BEGIN
	INSERT dbo.tbl_DBAsof (AsOfDate) VALUES (@NowInDenver);
END ELSE BEGIN
	UPDATE dbo.tbl_DBAsof 
		SET AsOfDate = @NowInDenver 
	WHERE AsOfId = @AsOfId;
END
DELETE FROM dbo.tbl_DBAsof WHERE AsOfDate < CAST(DATEADD(DD, -1, @NowInDenver) AS DATE);
" > UPDATE_AsOfDate.sql
::PSSqlWriterScriptEnd::

:dataCompare

REM "D:\Program Files\Devart\Compare Bundle for SQL Server Professional\dbForge Data Compare for SQL Server\datacompare.com" /datacompare /source connection:"Data Source=%SRC_SERVER%;Encrypt=False;Enlist=False;Initial Catalog=%SRC_DB%;Integrated Security=False;Password=D3n^3r#$Pr0d;User ID=%SRC_LOGIN%;Pooling=False;Transaction Scope Local=True" /target connection:"Data Source=%TGT_SERVER%;Encrypt=False;Enlist=False;Initial Catalog=%TGT_DB%;Integrated Security=False;Password=%TGT_PASSWORD%;User ID=%TGT_LOGIN%;Pooling=False;Transaction Scope Local=True" /report:"%THISPATH%\MARS_PROD_AZURE_TO_ONPREM_DATA_SYNC.xls" /reportformat:xls /groupby:status /log:%LogFile% /ExcludeObjectsByMask:*tbl_BaseExpense*,*tbl_SvcPeriodBal* /sync /CreateBackupFolder:No /NeedCompressBackup:No /AddTransactionIsolationLevel:No /UseSchemaNamePrefix:No /DisableForeignKeys:No /DisableDmlTriggers:No
"D:\Program Files\Devart\Compare Bundle for SQL Server Professional\dbForge Data Compare for SQL Server\datacompare.com" /datacompare /source connection:"Data Source=%SRC_SERVER%;Encrypt=False;Enlist=False;Initial Catalog=%SRC_DB%;Integrated Security=False;Password=D3n^3r#$Pr0d;User ID=%SRC_LOGIN%;Pooling=False;Transaction Scope Local=True" /target connection:"Data Source=%TGT_SERVER%;Encrypt=False;Enlist=False;Initial Catalog=%TGT_DB%;Integrated Security=False;Password=%TGT_PASSWORD%;User ID=%TGT_LOGIN%;Pooling=False;Transaction Scope Local=True" /report:"%THISPATH%\MARS_PROD_AZURE_TO_ONPREM_DATA_SYNC.xls" /reportformat:xls /groupby:status /log:%LogFile% /ExcludeObjectsByMask:*tbl_BaseExpense*,*tbl_SvcPeriodBal*,*tbl_MARSSvcCompare*,*tbl_Reminder*,*tbl_EmailNotificationQueue*,*relationshipcashflowhistory* /sync /CreateBackupFolder:No /NeedCompressBackup:No /AddTransactionIsolationLevel:No /DisableDmlTriggers:Yes /DisableDdlTriggers:Yes
SET LEVEL=%ERRORLEVEL%
@Echo DataCompare (Second Try) returned RC=%LEVEL% >> %LogFile% 2>&1
IF %LEVEL% EQU 100 (GOTO OK)
IF %LEVEL% EQU 108 (GOTO OK)
IF %LEVEL% EQU 0 (GOTO OK)
@Echo WARNING! datacompare returned an error.... skipping clean old files and database AsOfDate update >> %LogFile% 2>&1
exit
:OK
exit /b
:cleanOldfiles
@Echo Cleaning log files older than 7 days old in path '%THISPATH%' >> %LogFile% 2>&1
forfiles -p "%THISPATH%" -m *.log -d -7 -C "cmd /C del @path" >> %LogFile% 2>&1
exit /b

:updateAsOfDate
SET SQLCMD="C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\110\Tools\Binn\SQLCMD.EXE"
@Echo Updating AsOfDate on Both Azure and OnPrem Databases >> %LogFile% 2>&1

%SQLCMD% -S "%TGT_SERVER%" -d "%TGT_DB%" -U "%TGT_LOGIN%" -P "%TGT_PASSWORD%" -i "%THISPATH%\UPDATE_AsOfDate.sql" 
%SQLCMD% -S "%SRC_SERVER%" -d "%SRC_DB%" -U "%SRC_LOGIN%" -P %SRC_PASSWORD% -i "%THISPATH%\UPDATE_AsOfDate.sql" 
exit /b