"""Finite native UI checks against the normal development APK on one phone."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time
import base64
import xml.etree.ElementTree as ET
import uiautomator2 as u2

sys.stdout.reconfigure(encoding='utf-8',errors='replace')
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--device',required=True);parser.add_argument('--inspect',action='store_true');args=parser.parse_args()
ADB=r'D:\SDKs\Android\platform-tools\adb.exe'
PACKAGE='com.crompton.pms.frontend'
OUT=ROOT/'tests/android'
checks=[]
limitations=[]
stage='install normal development APK'
original_rotation=None
rotation_locked=None


def adb(*items):
    return subprocess.run([ADB,'-s',args.device,*items],capture_output=True,check=True).stdout


def check(label):
    checks.append(label);print('NATIVE: '+label,flush=True)
    persist()


def persist():
    (OUT/'native-lifecycle-results.json').write_text(json.dumps({'checks':checks,'limitations':limitations,'passed':False,'stage':stage},indent=2))


def screen():
    return ET.fromstring(d.dump_hierarchy())


def click(label,timeout=30):
    end=time.time()+timeout
    while time.time()<end:
        nodes=list(screen().iter('node'))
        candidates=[n for n in nodes if n.attrib.get('text')==label or n.attrib.get('content-desc','').split('\n')[0]==label]
        if candidates:
            selected=next((n for n in candidates if n.attrib.get('clickable')=='true'),candidates[-1])
            bounds=list(map(int,re.findall(r'\d+',selected.attrib['bounds'])))
            d.click((bounds[0]+bounds[2])//2,(bounds[1]+bounds[3])//2)
            time.sleep(.6);return
        time.sleep(.3)
    raise RuntimeError('Required native control missing')


def wait_text(label,timeout=30):
    end=time.time()+timeout
    while time.time()<end:
        if any(n.attrib.get('text')==label or n.attrib.get('content-desc')==label for n in screen().iter('node')):return
        time.sleep(.3)
    raise RuntimeError('Expected native screen not reached')


def screenshot(name):
    if d.app_current()['package']!=PACKAGE:raise RuntimeError('Refusing to capture another application')
    shot=d.screenshot()
    # Exclude system status/navigation bars and unrelated notification previews.
    shot.crop((0,int(shot.height*.04),shot.width,int(shot.height*.95))).save(str(OUT/(name+'.png')))


def phone_token():
    # Read only this debuggable application's FCM preferences, never personal data.
    preferences=ET.fromstring(adb('shell','run-as',PACKAGE,'cat','shared_prefs/com.google.android.gms.appid.xml'))
    for item in preferences.findall('string'):
        if '|T|' in item.attrib.get('name',''):
            value=json.loads(item.text or '{}')
            if value.get('token'):return value['token']
    raise RuntimeError('No current token in application preferences')


def registered(token):
    key=base64.urlsafe_b64encode(token.encode()).decode()
    row=db.collection('device-tokens').document(key).get().to_dict()
    return bool(row and row.get('userId')==4 and row.get('token')==token)


def push(state):
    token=phone_token()
    end=time.time()+45
    while not registered(token) and time.time()<end:time.sleep(1)
    if not registered(token):raise RuntimeError('Current physical phone token not registered to synthetic UID 4')
    title='Crompton physical '+state+' test'
    messaging.send(messaging.Message(token=token,
        notification=messaging.Notification(title=title,body='Synthetic development notification'),
        data={'type':'TIMESHEET_APPROVED'},
        android=messaging.AndroidConfig(priority='high',notification=messaging.AndroidNotification(channel_id='comten_notifications'))))
    check('FCM accepted for this phone in '+state+' state; delivery not yet asserted')
    # Inspect only the matching notification, never capture the user's shade.
    d.open_notification()
    click(title,45)
    if state=='terminated':
        wait_text('App Locked')
        check('Terminated FCM tap respects PIN gate')
        for digit in '1234':click(digit,3)
    wait_text('My Timesheets',45)
    check('Actual '+state+' notification received, tapped and deep-linked to My Timesheets')
    screenshot('native-push-'+state)
    d.press('back');wait_text('Quick Access')
    return token


passed=False
try:
    apk=ROOT/'mobile/build/app/outputs/flutter-apk/app-development-debug.apk'
    build=json.loads((OUT/'build.json').read_text())
    if hashlib.sha256(apk.read_bytes()).hexdigest()!=build['sha256']:raise RuntimeError('Unexpected APK')
    adb('install','-r','-t',str(apk))
    adb('reverse','tcp:8007','tcp:8007')
    d=u2.connect(args.device)
    original_rotation=d.info.get('displayRotation',0)
    rotation_locked=adb('shell','settings','get','system','accelerometer_rotation').strip()==b'0'
    d.app_start(PACKAGE,stop=True)
    time.sleep(4)
    screenshot('native-normal-start')
    nodes=list(screen().iter('node'))
    labels=[n.attrib.get('text') or n.attrib.get('content-desc') for n in nodes if n.attrib.get('package')==PACKAGE]
    print(json.dumps({'normalAppStarted':d.app_current()['package']==PACKAGE,'nativeLabels':[x for x in labels if x and len(x)<80][:35]}),flush=True)
    if args.inspect:
        passed=True
    else:
        import firebase_admin
        from firebase_admin import credentials,firestore,messaging
        identity=ROOT/'.local/development-service-account.json'
        if json.loads(identity.read_text())['project_id']!='crompton-pms-dev-20261015':raise RuntimeError('Unexpected Firebase project')
        firebase_admin.initialize_app(credentials.Certificate(str(identity)))
        db=firestore.client()
        stage='native employee login'
        click('Login')
        fields=d(className='android.widget.EditText')
        if not fields.wait(timeout=15):raise RuntimeError('Native login fields unavailable')
        credentials=json.loads((ROOT/'.local/development-logins.json').read_text())['EMP001']
        stage='employee code entry'
        fields[0].click();time.sleep(.5);fields[0].set_text('EMP001')
        stage='employee password entry'
        fields[1].click();time.sleep(.5);fields[1].set_text(credentials['password'])
        keyboard=adb('shell','dumpsys','input_method').decode(errors='replace')
        if 'mInputShown=true' in keyboard:d.press('back')
        click('Login')
        deadline=time.time()+50
        while time.time()<deadline:
            nodes=list(screen().iter('node'));labels={n.attrib.get('text') or n.attrib.get('content-desc') for n in nodes}
            if 'Quick Access' in labels:break
            if 'Enter PIN' in labels:
                stage='native PIN onboarding'
                pins=d(className='android.widget.EditText')
                pins[0].click();time.sleep(.5);pins[0].set_text('1234')
                pins[1].click();time.sleep(.5);pins[1].set_text('1234')
                if 'mInputShown=true' in adb('shell','dumpsys','input_method').decode(errors='replace'):d.press('back')
                click('Continue',3)
            elif 'Skip' in labels:click('Skip',2)
            elif 'Continue' in labels:click('Continue',2)
            else:time.sleep(.5)
        wait_text('Quick Access')
        check('Normal native app logs in to synthetic employee account')
        screenshot('native-employee-dashboard')
        stage='physical rotation and responsive layout'
        try:
            d.set_orientation('l');time.sleep(2)
            wait_text('Quick Access')
            if d.window_size()[0]<=d.window_size()[1]:raise RuntimeError('Landscape rotation did not occur')
            screenshot('native-employee-landscape')
            check('Physical landscape rotation retains the employee dashboard')
        finally:
            d.set_orientation({0:'n',1:'l',2:'u',3:'r'}[original_rotation])
            d.freeze_rotation(rotation_locked)
        wait_text('Quick Access')
        stage='background and process restart'
        before=adb('shell','pidof',PACKAGE).decode().strip()
        d.press('home');time.sleep(2);d.app_start(PACKAGE);wait_text('Quick Access')
        check('Native background/foreground preserves the current employee screen')
        adb('shell','am','force-stop',PACKAGE)
        d.app_start(PACKAGE);wait_text('App Locked')
        check('Real process death restores the PIN gate before account access')
        for digit in '1234':click(digit,3)
        wait_text('Quick Access')
        after=adb('shell','pidof',PACKAGE).decode().strip()
        if before==after:raise RuntimeError('Process did not restart')
        check('PIN unlock restores employee identity after a new Android process')
        screenshot('native-restored-dashboard')
        stage='native notification delivery and deep links'
        original_token=push('foreground')
        d.press('home');time.sleep(2)
        push('background')
        d.press('home');time.sleep(2)
        adb('shell','am','kill',PACKAGE)
        time.sleep(2)
        if subprocess.run([ADB,'-s',args.device,'shell','pidof',PACKAGE],capture_output=True).stdout.strip():
            raise RuntimeError('Cached process did not terminate; cold-start test cannot be claimed')
        push('terminated')
        package_info=adb('shell','dumpsys','package',PACKAGE).decode(errors='replace')
        flag_line=next((line for line in package_info.splitlines() if 'pkgFlags=' in line),'')
        if 'ALLOW_BACKUP' in flag_line:raise RuntimeError('Backup unexpectedly enabled')
        check('Installed Android package disables OS backup')
        stage='native logout and token invalidation'
        click('Settings')
        for unused in range(5):
            if d(text='Logout').exists or d(description='Logout').exists:break
            d.swipe_ext('up',scale=.65);time.sleep(.3)
        click('Logout');click('Logout')
        wait_text('Welcome to Comten')
        if registered(original_token):raise RuntimeError('Device token remains registered after logout')
        check('Native logout removes this phone token from its employee account')
        passed=True
except Exception as error:
    # UI framework errors may contain typed values: never print their messages.
    print(json.dumps({'passed':False,'stage':stage,'errorType':type(error).__name__}),flush=True)
finally:
    if original_rotation is not None:
        try:
            d.set_orientation({0:'n',1:'l',2:'u',3:'r'}[original_rotation]);d.freeze_rotation(rotation_locked)
        except Exception:limitations.append('Device orientation restoration unavailable after disconnect')
    result={'checks':checks,'limitations':limitations,'passed':passed,'stage':stage}
    (OUT/'native-lifecycle-results.json').write_text(json.dumps(result,indent=2))
raise SystemExit(0 if passed else 1)
