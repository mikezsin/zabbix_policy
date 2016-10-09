#!/usr/bin/env python
# -*- coding: utf-8 -*-
#/var/lib/zabbixsrv/alertscripts/mail.py
import string
import re
import subprocess
import sys
import time
import os

# функция для отправки писем, ищем готовую, переделываем для себя
def send_mail(recipient, subject, body):
    import smtplib
    from email.MIMEText import MIMEText
    from email.Header import Header
    from email.Utils import formatdate
    encoding='utf-8'
    SMTP_SERVER = 'smtp'
    SENDER_NAME = u'Zabbix Alert'
    session = None
    msg = MIMEText(body, 'plain', encoding)
    msg['Subject'] = Header(subject, encoding)
    msg['From'] = Header(SENDER_NAME, encoding)
    msg['To'] = recipient
    msg['Date'] = formatdate()
    try:
        session = smtplib.SMTP(SMTP_SERVER)
        session.sendmail(SENDER_NAME, recipient, msg.as_string())
    except Exception as e:
        raise e
    finally:
                # close session
        if session:
            session.quit()

# Zabbix не должен ждать выполнения скрипта, поэтому делаем так, чтобы скрипт работал в фоне.(ищем  готовый пример, переделываем для себя) 			
def daemonize (stdin='/dev/null', stdout='/dev/null', stderr='/dev/null'):
     try:
         pid = os.fork()
         if pid > 0:
             sys.exit(0)
     except OSError, e:
         sys.stderr.write("fork #1 failed: (%d) %s\n" % (e.errno, e.strerror))
         sys.exit(1)
     os.chdir("/")
     os.umask(0)
     os.setsid()
     try:
         pid = os.fork()
         if pid > 0:
            sys.exit(0)
     except OSError, e:
        sys.stderr.write("fork #2 failed: (%d) %s\n" % (e.errno, e.strerror))
        sys.exit(1)
     for f in sys.stdout, sys.stderr: f.flush()
     si = file(stdin, 'r')
     so = file(stdout, 'a+')
     se = file(stderr, 'a+', 0)
     os.dup2(si.fileno(), sys.stdin.fileno())
     os.dup2(so.fileno(), sys.stdout.fileno())
     os.dup2(se.fileno(), sys.stderr.fileno())
#Добавляем в оповещение модель харда 
def hddsmart():
    m=re.search('MYparsBLOCK\:\S+\:\s+HIP\:(?P<hostip>\S+)\:KKEY\:(?P<kkey>\S+)',a3)
    hostip,kkey= m.group('hostip'),m.group('kkey')
    p = subprocess.Popen('zabbix_get -s '+hostip+' -k '+kkey, shell=True,stdout=subprocess.PIPE)
    bb = a3[0:string.find(a3,'MYparsBLOCK')] + 'HDD: ' + p.stdout.read()
    send_mail(sys.argv[1],a2,bb)
#Подготовка списка машин на удаление. Удалять будем через api в отдельном скрипте
def remove_offline():
    if 'PROBLEM:' in a2:
        m=re.search('MYparsBLOCK\:\S+\:\s+HID\:(?P<hostid>\S+)',a3)
        hostid = m.group('hostid') + '\n'
        hidf=open('/var/log/zabbixsrv/2del_ids', 'a')
        hidf.write(hostid)
        hidf.close
        send_mail(sys.argv[1],a2,a3[0:string.find(a3,'MYparsBLOCK')])

# Костыль, который возвращает к жизни драйвер для упса. Перезапускаем девайс с помощью  утилиты microsoft devcon.
def nutpt():
    if 'PROBLEM:' in a2:
        m=re.search('MYparsBLOCK\:\S+\:\s+HIP\:(?P<hostip>\S+)',a3)
        hostip = m.group('hostip')
        log = ''
        i = 0
        while i < 5:
            p = subprocess.Popen("""zabbix_get -s %s -k 'system.run[net stop "Network UPS Tools"]'"""%(hostip), shell=True,stdout=subprocess.PIPE)
            log +=p.stdout.read()
            time.sleep(10)
            p = subprocess.Popen("""zabbix_get -s %s -k system.run['cd "C:\Program Files\Zabbix\cmd\"&devcon.exe restart USB\VID_051D*']"""%(hostip), shell=True,stdout=subprocess.PIPE)
            log +=p.stdout.read()
            time.sleep(30)
            p = subprocess.Popen("""zabbix_get -s %s -k 'system.run[net start "Network UPS Tools"]'"""%(hostip), shell=True,stdout=subprocess.PIPE)
            log +=p.stdout.read()
            i += 1
            p = subprocess.Popen("""zabbix_get -s %s -k 'ups.status'"""%(hostip), shell=True,stdout=subprocess.PIPE)
            if 'Error' not in p.stdout.read():
                 i = 8
        if i <> 8:
            send_mail(sys.argv[1],a2,log)
#набор действий при авторегистрации клиента. Пока это только включение smart с помощью smartctl.exe --scan-open
def firstrun():
    m=re.search('MYparsBLOCK\:\S+\:\s+HIP\:(?P<hostip>\S+)',a3)
    hostip = m.group('hostip')
    p = subprocess.Popen("""zabbix_get -s %s -k system.run['cd "C:\Program Files\Zabbix\extra\smart\"&smartctl.exe --scan-open']"""%(hostip), shell=True,stdout=subprocess.PIPE)
    log = p.stdout.read()
    send_mail(sys.argv[1],a2,log)

daemonize(stdout='/var/log/zabbixsrv/script_out.log', stderr='/var/log/zabbixsrv/script_err.log')
try:
    a1,a2,a3 = sys.argv[1],sys.argv[2],sys.argv[3]
	#debug(строчку ниже при необходимости можно раскомментировать ) 
    #os.system('echo "' + a1+'  '+a2+'  '+a3 +'" >> /var/log/zabbixsrv/script_dbg.log')
    if 'MYparsBLOCK' in a3:
        eval(re.search('MYparsBLOCK\:(?P<myfunc>\S+)\:',a3).group('myfunc'))() # запуск функции полученной из триггера
	else:
        send_mail(sys.argv[1],a2,a3)


except:
    #print sys.exc_info()
    send_mail('admin@domain.local', 'Error in script', str(sys.exc_info()))
