 
# Внимание!!
# Для хранения логов у меня используется абсолютный путь c:\temp, который уже создан на всех машинах другой политикой
# Для использования %TMP%(это обязательно надо учесть в конфигурации zabbix агента, насколько я помню, он переменные не понимает) 
# или создания с:\temp необходимо внести соответсвующие правки. 

# функция обращения к SQL-серверу
function Invoke-Sqlcmd($conn,$Query,[Int32]$QueryTimeout=30)
	{
	$cmd=new-object system.Data.SqlClient.SqlCommand($Query,$conn)
	$cmd.CommandTimeout=$QueryTimeout
	$ds=New-Object system.Data.DataSet
	$da=New-Object system.Data.SqlClient.SqlDataAdapter($cmd)
	[void]$da.fill($ds)
	$ds.Tables[0]
	}
#--------------------------------------------------------------------------------------------
function report-mail($zv) 
	{
	#E-Mail
	$sender = 'ZabbixInstall@domain.local'
	$recipient = 'admin@domain.local'
	$SMTPserver = 'smtp'
	$subject = "At $HostName PS_version =  $CurrentPS_Version"
	if ($zv -eq 1) {$subject = "p***a #powershell install zabbix deployment aborted"} 
	$body = "$HostName`t$OSName`t$OSVersion`t$OSLang`t$OSArchitecture`t$Date"
	$msg = New-Object System.Net.Mail.MailMessage $sender, $recipient, $subject, $body
	$client = New-Object System.Net.Mail.SmtpClient $SMTPserver
	$client.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
	$client.Send($msg)
	}
#--------------------------------------------------------------------------------------------
#функция завершения процесса:
#Kill-Process  "msiexec"
function Kill-Process([string[]]$ProcessNames) 
	{
	if ($ProcessNames -eq $null) 
		{
		Write-Error 'The parametre "ProcessNames" cannot be empty';
		break
		}
	else
		{
		$pr=(Get-Process $ProcessNames -ErrorAction SilentlyContinue)  
		$pr.kill()
		}
	}
#--------------------------------------------------------------------------------------------
#функция Установки NUT:
#NUT-Install  -pth $pnut -pth2 $pnut2 -globalpath $globalpath
function NUT-Install() 
	{
	Param([string]$pth,[string]$pth2,[string]$pth3,[string]$globalpath)  
	$ErrorActionPreference="SilentlyContinue"
	Copy-Item  "$globalpath\driver\APC-UPS\InstallDriver.exe" -Destination "c:\temp\InstallDriver.exe" -Force -Verbose
	Start-process "c:\temp\InstallDriver.exe" #Ставим драйвер для упсов. У нас везде используются упсы APC, поэтому и exe файл один.
	$processid = (Start-process msiexec -args "/quiet /passive /norestart /log c:\temp\inst_nutlog.txt /I $globalpath\nut.msi" -PassThru).id
	do 
		# при silent установке NUT вываливается интерактивный exe, прибиваем. 
		{
		Write-Host "target_pid" $processid
		[array]$msiexecid = Get-Process -Name msiexec | % {$_.id}
		[array]$xer = Get-Process -Name wdi-simple 
		if 	($xer.count -gt 0) 
			{Kill-Process "wdi-simple"}
		Write-Host "rem_proc" $msiexecid
		Start-Sleep -Milliseconds 1000
		[array]$proccount+=1
		Write-Host "pcount" $proccount.count
		Start-Sleep -Milliseconds 1000
		}			
			
	while(($msiexecid -contains $processid)-and($proccount.count -lt "90")) 
	#в разных версиях NUT криво работают разные exe, поэтому берем только лучшее. Файлы позже выложу на git. 
	Copy-Item  $globalpath\nut_sbin\* -Destination $pth3 -Force -Verbose
	Copy-Item  $globalpath\nut_etc\* -Destination $pth -Force -Verbose #конфиг
	Copy-Item  $globalpath\nut_bin\* -Destination $pth2 -Force -Verbose
		Start-Sleep -Milliseconds 15000
	#Запускаем службу и пишем результат в лог. Все логи будем обновлять с помощью MERGE, т. к. километры логов никому не нужны. 
	$nut_inst_err=(Get-WmiObject Win32_Service -Filter "Name='Network UPS Tools'").InvokeMethod("StartService",$null)
	Invoke-Sqlcmd $conn "MERGE [zabbix].[dbo].[zabbix_log]
USING (values('$HostName','$nut_inst_err','$today')) AS foo (machine,nut_inst_err,nut_inst_run)
ON (zabbix.dbo.zabbix_log.machine = foo.machine)
WHEN MATCHED THEN
    UPDATE SET zabbix.dbo.zabbix_log.nut_inst_err = foo.nut_inst_err, zabbix.dbo.zabbix_log.nut_inst_run = foo.nut_inst_run;"
	}
#--------------------------------------------------------------------------------------------
#функция обновления NUT:
function NUT-Update() 
	{
	Param([string]$pth,[string]$pth2,[string]$pth3,[string]$globalpath)  
	(Get-WmiObject Win32_Service -Filter "Name='Network UPS Tools'").InvokeMethod("StopService",$null)
	Start-Sleep -Milliseconds 15000
	Copy-Item  $globalpath\nut_etc\* -Destination $pth -Force -Verbose
	Copy-Item  $globalpath\nut_bin\* -Destination $pth2 -Force -Verbose
	Copy-Item  $globalpath\nut_sbin\* -Destination $pth3 -Force -Verbose
	Start-Sleep -Milliseconds 15000
	$nut_upd_err=(Get-WmiObject Win32_Service -Filter "Name='Network UPS Tools'").InvokeMethod("StartService",$null)
	Invoke-Sqlcmd $conn "MERGE [zabbix].[dbo].[zabbix_log]
USING (values('$HostName','$nut_upd_err','$today')) AS foo (machine,nut_upd_err,nut_upd_run)
ON (zabbix.dbo.zabbix_log.machine = foo.machine)
WHEN MATCHED THEN
    UPDATE SET zabbix.dbo.zabbix_log.nut_upd_err = foo.nut_upd_err, zabbix.dbo.zabbix_log.nut_upd_run = foo.nut_upd_run;"
	}
#--------------------------------------------------------------------------------------------
#функция установки zabbix:
function zabbix-inst($globalpath,$zbxbin)
	{
	Copy-Item $globalpath\Zabbix -Destination "C:\Program Files\" -Force -Recurse -Verbose
	Start-Sleep -Milliseconds 15000
	if ($zbxbin -eq "win32") {Copy-Item $globalpath\x86\Zabbix -Destination "C:\Program Files\" -Force -Recurse -Verbose}
	Start-Sleep -Milliseconds 11000
	$zconf = '"C:\Program Files\Zabbix\conf\zabbix_agentd.conf"'
    Start-Process -FilePath "C:\Program Files\Zabbix\bin\$zbxbin\zabbix_agentd.exe" -args "--config $zconf -i"
	Start-Sleep -Milliseconds 15000
	$zab_inst_err=(Get-WmiObject Win32_Service -Filter "Name='Zabbix Agent'").InvokeMethod("StartService",$null)
	Invoke-Sqlcmd $conn "MERGE [zabbix].[dbo].[zabbix_log]
USING (values('$HostName','$zab_inst_err','$today')) AS foo (machine,zab_inst_err,zab_inst_run)
ON (zabbix.dbo.zabbix_log.machine = foo.machine)
WHEN MATCHED THEN
    UPDATE SET zabbix.dbo.zabbix_log.zab_inst_err = foo.zab_inst_err, zabbix.dbo.zabbix_log.zab_inst_run = foo.zab_inst_run;"
	}

#--------------------------------------------------------------------------------------------
#функция обновления zabbix:
function zabbix-update($globalpath,$zbxbin,$part)
	{
	(Get-WmiObject Win32_Service -Filter "Name='Zabbix Agent'").InvokeMethod("StopService",$null)
	Start-Sleep -Milliseconds 15000
	Copy-Item $globalpath\Zabbix\$part -Destination "C:\Program Files\Zabbix" -Force -Recurse -Verbose
	Start-Sleep -Milliseconds 15000
	if (($zbxbin -eq "win32") -and (($part -eq "conf") -or ($part -eq "cmd"))) {Copy-Item $globalpath\x86\Zabbix -Destination "C:\Program Files\" -Force -Recurse -Verbose}
	Start-Sleep -Milliseconds 10000	
	$zab_upd_err=(Get-WmiObject Win32_Service -Filter "Name='Zabbix Agent'").InvokeMethod("StartService",$null)
	Invoke-Sqlcmd $conn "MERGE [zabbix].[dbo].[zabbix_log]
USING (values('$HostName','$zab_upd_err','$today')) AS foo (machine,zab_upd_err,zab_upd_run)
ON (zabbix.dbo.zabbix_log.machine = foo.machine)
WHEN MATCHED THEN
    UPDATE SET zabbix.dbo.zabbix_log.zab_upd_err = foo.zab_upd_err, zabbix.dbo.zabbix_log.zab_upd_run = foo.zab_upd_run;"
	}

## START
Start-Transcript -path c:\temp\zabbix_inst_debug.txt

$globalpath="\\domain.local\dfs\Zabbix_policy\zabbixinst" #путь, где лежит все наше добро, не забудьте дать права группе, куда включены компьютеры. 
$today=  get-date -Format "yyyyMMdd"
#
#Arch
$OSArchitecture = (Get-WmiObject -Class Win32_OperatingSystem -Namespace root/cimv2).OSArchitecture
if ($OSArchitecture -match "64-bit")
	{
	$zbxbin="win64"
	$pnut="c:\Program Files (x86)\NUT\etc\"
	$pnut2="c:\Program Files (x86)\NUT\bin\"
	$pnut3="c:\Program Files (x86)\NUT\sbin\"
	}
else 
	{
	$zbxbin="win32"
	$pnut="c:\Program Files\NUT\etc\"
	$pnut2="c:\Program Files\NUT\bin\"
	$pnut3="c:\Program Files\NUT\sbin\"
	}

#Подключение к SQL
$conn=new-object System.Data.SqlClient.SQLConnection
$conn.ConnectionString="Server={0};Database={1};Integrated Security=True" -f "server","Zabbix" 
$conn.Open()



# определение имени хоста на котором запустился скрипт.
$HostName = $env:COMPUTERNAME;

# сбор сведений об ОС
$OperatingSystem = Get-WmiObject Win32_OperatingSystem;
# определение прочих параметров ОС
$OSName = $OperatingSystem.caption; # имя ОС
$OSVersion = $OperatingSystem.version; # версия ОС
$OSLang = $OperatingSystem.oslanguage; # язык ОС
# MinimalPS_Major_Version
$MinimalPS_Major_Version = 2
# Определение версии PowerShell
$CurrentPS_Version = $host.version.major

# Если версиия PS подходящая, выполняем скрипт дальше
If ($CurrentPS_Version -ge $MinimalPS_Major_Version)
{
#main

#log
Invoke-Sqlcmd $conn "MERGE [zabbix].[dbo].[zabbix_log]
USING (values('$HostName','$OSName','$zbxbin','$today')) AS foo (machine,osname,osarch,lastrun)
ON (zabbix.dbo.zabbix_log.machine = foo.machine)
WHEN MATCHED THEN
    UPDATE SET zabbix.dbo.zabbix_log.osname = foo.osname, zabbix.dbo.zabbix_log.osarch = foo.osarch, zabbix.dbo.zabbix_log.lastrun = foo.lastrun
WHEN NOT MATCHED BY TARGET THEN
    INSERT (machine,osname,osarch,lastrun)
    values (machine,osname,osarch,lastrun);"
#	

$Query=		
"SELECT * FROM  [zabbix].[dbo].[zabbix_cfg]"	

$result= Invoke-Sqlcmd $conn $Query
[array]$testresult= $result
if ($testresult.count -ne 1 ) {	report-mail 1}

#получаем локальные версии
[int]$zabbix_bin = Get-Content -Path "C:\Program Files\Zabbix\bin\ver" -ErrorAction SilentlyContinue
[int]$zabbix_cmd = Get-Content -Path "C:\Program Files\Zabbix\cmd\ver" -ErrorAction SilentlyContinue
[int]$zabbix_conf = Get-Content -Path "C:\Program Files\Zabbix\conf\ver" -ErrorAction SilentlyContinue
[int]$zabbix_extra = Get-Content -Path "C:\Program Files\Zabbix\extra\ver" -ErrorAction SilentlyContinue
[int]$nut_bin = Get-Content -Path $pnut2"ver" -ErrorAction SilentlyContinue
[int]$nut_conf = Get-Content -Path $pnut"ver" -ErrorAction SilentlyContinue

#сверяем версии 
if (($zabbix_bin -lt 1) -and  ($zabbix_cmd -lt 1)  -and ($zabbix_conf -lt 1)  -and ($zabbix_extra -lt 1) -and ($nut_bin -lt 1) -and  ($nut_conf -lt 1) ) 
	{
	NUT-Install  -pth $pnut -pth2 $pnut2 -pth3 $pnut3 -globalpath $globalpath
	zabbix-inst $globalpath $zbxbin
	}
else
	{
	if ($zabbix_bin -lt $result.zabbix_bin) {zabbix-update $globalpath $zbxbin "bin"}
	if ($zabbix_cmd -lt $result.zabbix_cmd) {zabbix-update $globalpath $zbxbin "cmd"}
	if ($zabbix_conf -lt $result.zabbix_conf) {zabbix-update $globalpath $zbxbin "conf"}
	if ($zabbix_extra -lt $result.zabbix_extra) {zabbix-update $globalpath $zbxbin "extra"}
	if ($nut_bin -lt $result.nut_bin) {NUT-Install  -pth $pnut -pth2 $pnut2 -pth3 $pnut3 -globalpath $globalpath}
	elseif ($nut_conf -lt $result.nut_conf) {NUT-Update  -pth $pnut -pth2 $pnut2 -pth3 $pnut3 -globalpath $globalpath}
	}

}
else {
report-mail
}
#end main

#close connect	
$conn.Close()
Stop-Transcript
