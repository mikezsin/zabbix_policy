#!/usr/bin/python
#
# -*- coding: utf-8 -*-

import socket
from getpass import getpass
from pyzabbix import ZabbixAPI, ZabbixAPIException


zapi = ZabbixAPI(server='https://127.0.0.1/zabbix/')
zapi.session.verify = False
zapi.login('apirobot', '*******')

body = ''
err = ''

def send_mail(recipient, subject, body):

    import smtplib
    from email.MIMEText import MIMEText
    from email.Header import Header
    from email.Utils import formatdate
    encoding='utf-8'
    SMTP_SERVER = 'smtp'
    SENDER_NAME = u'zabbix@domain.local'
    MAIL_ACCOUNT = 'zabbix@domain.local'
    session = None
    msg = MIMEText(body, 'plain', encoding)
    msg['Subject'] = Header(subject, encoding)
    msg['From'] = Header(SENDER_NAME, encoding)
    msg['To'] = recipient
    msg['Date'] = formatdate()
    try:
        session = smtplib.SMTP(SMTP_SERVER)
        session.sendmail(MAIL_ACCOUNT, recipient, msg.as_string())
    except Exception as e:
        raise e
    finally:
                # close session
        if session:
            session.quit()


# Loop through all hosts interfaces, getting only "main" interfaces of type "agent"
for h in zapi.hostinterface.get(output=["dns","ip","useip"],selectHosts=["host"],filter={"main":1,"type":1}):
    #print h
    # Make sure the hosts are named according to their FQDN
    #
    if len(h['dns']) == 0:
        try:
            zapi.hostinterface.update(interfaceid=h['interfaceid'], dns = socket.gethostbyaddr(h['hosts'][0]['host'])[0])
        except:
            body += ('FQDN_UPD_ERR: ' + h['hosts'][0]['host']) + '\n'
    try:
        a = socket.gethostbyaddr(h['hosts'][0]['host'])[2][0]
        b = socket.gethostbyaddr(h['dns'])[2][0]
        if (a != b):
            body += ('Warning: %s has dns "%s"' % (h['hosts'][0]['host'], h['dns'])) + '\n'

    except:
        body += ('DNS_LOOKUP_ERR: ' + h['hosts'][0]['host']) + '\n'

    # Make sure they are using hostnames to connect rather than IPs (could be also filtered in the get request)
    if h['useip'] == '1':
        body += ('%s is using IP instead of hostname. Fixing.' % h['hosts'][0]['host']) + '\n'
        try:
            zapi.hostinterface.update(interfaceid=h['interfaceid'], useip=0)
        except ZabbixAPIException as e:
            #print(e)
            err += str(e)+'\n'
            err += '\n'
        continue

body += '\nZabbix Errors:' + err
if  len(body) > 16:
    send_mail('admin@domain.local','check agents',body)
