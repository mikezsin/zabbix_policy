#!/usr/bin/python
#
import os
from pyzabbix import ZabbixAPI, ZabbixAPIException
try:
    os.rename ('/var/log/zabbixsrv/2del_ids','/var/log/zabbixsrv/klist_pr')
except:
    pass
user='apirobot'
pwd='*******'
url = 'https://127.0.0.1/zabbix/'
zh = ZabbixAPI(url)
zh.session.verify = False
zh.login(user=user, password=pwd)

f = open('/var/log/zabbixsrv/klist_pr')


for hnm in f:
    try:
        hid = zh.host.get(filter={"host":hnm.replace('\n','')},output=['hostid'])[0]['hostid']
        #zh.host.delete(hostid = hid)  - API change
        zh.host.delete(int(hid))
    except:
        pass
f.close()
os.remove('/var/log/zabbixsrv/klist_pr')
