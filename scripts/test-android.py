"""Run the development app on one explicitly selected physical Android device.

Transient loopback fixtures keep synthetic passwords out of the APK and logs.
The broker is stopped and its USB reverse removed when the test finishes.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT=Path(__file__).resolve().parents[1]
sys.stdout.reconfigure(encoding='utf-8',errors='replace')
parser=argparse.ArgumentParser()
parser.add_argument('--device',required=True)
parser.add_argument('--resume',action='store_true',help='Skip completed Captain/Controller and resume at Team Leader Settings')
parser.add_argument('--workflow-only',action='store_true',help='Run remaining native GPS/attestation/business workflow without repeating completed navigation')
args=parser.parse_args()
ADB=Path(r'D:\SDKs\Android\platform-tools\adb.exe')
FLUTTER=Path(r'D:\SDKs\flutter\3.47.6\bin\flutter.bat')
PACKAGE='com.crompton.pms.frontend'
OUT=ROOT/'tests/android'
OUT.mkdir(parents=True,exist_ok=True)
archive=OUT/'runs'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
for name in ('native-results.json','device-results.json'):
    previous=OUT/name
    if previous.exists():
        archive.mkdir(parents=True,exist_ok=True)
        (archive/name).write_bytes(previous.read_bytes())
fixture=json.loads((ROOT/'.local/development-logins.json').read_text())
redactions=[item['password'] for item in fixture.values()]
workflow_file=ROOT/'.local/android-workflow.json'
if workflow_file.exists():redactions.append(json.loads(workflow_file.read_text())['password'])
checks=[]
native=[]
started=datetime.now(timezone.utc).isoformat()
result=1
stop_reason=None


def checkpoint():
    (OUT/'native-results.json').write_text(json.dumps({
        'startedAt':started,'updatedAt':datetime.now(timezone.utc).isoformat(),
        'native':native,'stages':checks,'exitCode':result,
        'stopReason':stop_reason,
    },indent=2))


def send_device_push(token):
    import base64
    import firebase_admin
    from firebase_admin import credentials,firestore,messaging
    if not firebase_admin._apps:
        identity=ROOT/'.local/development-service-account.json'
        if json.loads(identity.read_text())['project_id']!='crompton-pms-dev-20261015':
            raise RuntimeError('Unexpected Firebase project')
        firebase_admin.initialize_app(credentials.Certificate(str(identity)))
    key=base64.urlsafe_b64encode(token.encode()).decode()
    row=firestore.client().collection('device-tokens').document(key).get().to_dict()
    if not row or row.get('userId')!=4 or row.get('token')!=token:
        raise RuntimeError('Only the registered synthetic employee device is eligible')
    messaging.send(messaging.Message(token=token,
        notification=messaging.Notification(title='Crompton synthetic device test',body='Development phone notification verification'),
        data={'type':'TIMESHEET_APPROVED'},
        android=messaging.AndroidConfig(priority='high',notification=messaging.AndroidNotification(channel_id='comten_notifications'))))


def adb(*command):
    return subprocess.run([str(ADB),'-s',args.device,*command],capture_output=True,check=True).stdout


def sanitize(line):
    for secret in redactions:
        line=line.replace(secret,'[REDACTED]')
    if re.search(r'DebugAppCheckProvider|debug token|Bearer |eyJ[A-Za-z0-9_-]+\.',line,re.I):
        return 'Native credential diagnostic redacted.\n'
    return line


def native_action(action):
    # Only the app's permission prompt and its disposable document are targeted.
    import uiautomator2 as u2
    d=u2.connect(args.device)
    if action=='location-permission':
        import xml.etree.ElementTree as ET
        deadline=time.time()+40
        while time.time()<deadline:
            nodes=ET.fromstring(d.dump_hierarchy()).iter('node')
            candidates=[n for n in nodes if n.attrib.get('resource-id','').endswith('/permission_allow_foreground_only_button')]
            if candidates:
                d(resourceId=candidates[0].attrib['resource-id']).click()
                native.append('Location while-in-use native permission accepted')
                return
            time.sleep(.5)
        native.append('Location native prompt not observed')
    elif action=='background':
        d.press('home');time.sleep(2)
        # Reopen only our app; never inspect the user's launcher contents.
        d.app_start(PACKAGE)
        native.append('Physical app background/foreground cycle executed')


class Handler(BaseHTTPRequestHandler):
    def log_message(self,*unused):
        pass

    def respond(self,value):
        data=json.dumps(value).encode()
        self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)

    def do_GET(self):
        if self.path=='/fixtures':
            self.respond(fixture)
        elif self.path=='/workflow':
            saved=ROOT/'.local/android-workflow.json'
            self.respond(json.loads(saved.read_text()) if saved.exists() else None)
        else:
            self.send_error(404)

    def do_POST(self):
        data=self.rfile.read(min(int(self.headers.get('Content-Length','0')),4*1024*1024))
        if self.path=='/stage':
            value=json.loads(data)
            stage=str(value.get('name',''))[:160]
            print('DEVICE: '+stage,flush=True)
            checks.append(stage)
            checkpoint()
            self.respond({'ok':True})
        elif self.path.startswith('/native/'):
            action=self.path.removeprefix('/native/')
            if action not in ('location-permission','background'):
                self.send_error(404);return
            def run():
                try:native_action(action)
                except Exception:native.append(action+' unavailable; details suppressed')
            threading.Thread(target=run,daemon=True).start()
            self.respond({'ok':True})
        elif self.path=='/workflow':
            value=json.loads(data)
            if not str(value.get('employeeCode','')).startswith('AND'):
                self.send_error(400);return
            (ROOT/'.local/android-workflow.json').write_text(json.dumps(value,indent=2))
            (OUT/'workflow-checkpoint.json').write_text(json.dumps({k:v for k,v in value.items() if k!='password'},indent=2))
            self.respond({'ok':True})
        elif self.path.startswith('/screenshot/') and re.fullmatch(r'[a-zA-Z0-9_-]+',self.path.split('/')[-1]):
            # Screenshots originate only from the instrumented Flutter app.
            (OUT/(self.path.split('/')[-1]+'.png')).write_bytes(data)
            self.respond({'ok':True})
        elif self.path=='/result':
            value=json.loads(data)
            (OUT/'device-results.json').write_text(json.dumps(value,indent=2))
            self.respond({'ok':True})
        elif self.path=='/push':
            value=json.loads(data)
            try:
                send_device_push(value['token'])
                native.append('Finite FCM test accepted for registered synthetic UID 4 on this phone')
                self.respond({'accepted':True})
            except Exception:
                self.respond({'accepted':False})
        else:self.send_error(404)


server=None
command=[str(FLUTTER),'test','integration_test/device_test.dart','-d',args.device,'--no-uninstall','--dart-define-from-file=../firebase/development.mobile.json','--dart-define=BASE_URL=http://127.0.0.1:8007/api','--reporter=expanded']
if args.resume:command.append('--dart-define=DEVICE_RESUME=true')
if args.workflow_only:command.append('--dart-define=DEVICE_WORKFLOW_ONLY=true')
process=None
try:
    if adb('get-state').strip()!=b'device':
        raise RuntimeError('Selected Android device is unavailable')
    checkpoint()
    server=ThreadingHTTPServer(('127.0.0.1',8011),Handler)
    threading.Thread(target=server.serve_forever,daemon=True).start()
    for port in (8007,8011):adb('reverse',f'tcp:{port}',f'tcp:{port}')
    process=subprocess.Popen(command,cwd=ROOT/'mobile',stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace')
    def watch_device():
        global stop_reason
        missing=0
        deadline=time.monotonic()+20*60
        while process.poll() is None:
            try:
                state=subprocess.run([str(ADB),'-s',args.device,'get-state'],capture_output=True,timeout=8)
                missing=0 if state.returncode==0 and state.stdout.strip()==b'device' else missing+1
            except subprocess.TimeoutExpired:
                missing+=1
            if missing>=3 or time.monotonic()>deadline:
                stop_reason='Android device disconnected' if missing>=3 else 'Native run exceeded 20 minutes'
                checkpoint()
                subprocess.run(['taskkill','/PID',str(process.pid),'/T','/F'],capture_output=True)
                return
            time.sleep(5)
    threading.Thread(target=watch_device,daemon=True).start()
    with (ROOT/'.local/android-test.log').open('w',encoding='utf-8') as log:
        for line in process.stdout:
            safe=sanitize(line)
            log.write(safe);log.flush()
            print(safe,end='',flush=True)
    result=process.wait()
finally:
    if process is not None and process.poll() is None:
        subprocess.run(['taskkill','/PID',str(process.pid),'/T','/F'],capture_output=True)
    if server is not None:
        server.shutdown()
        server.server_close()
    evidence=OUT/'device-results.json'
    if evidence.exists():
        value=json.loads(evidence.read_text())
        value['runnerExitCode']=result
        value['passed']=bool(value.get('passed') and result==0)
        evidence.write_text(json.dumps(value,indent=2))
    # Cleanup must preserve results even when USB is disconnected.
    subprocess.run([str(ADB),'-s',args.device,'reverse','--remove','tcp:8011'],capture_output=True,timeout=10)
    checkpoint()
raise SystemExit(result)
