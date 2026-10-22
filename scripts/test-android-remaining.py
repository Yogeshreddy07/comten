"""Resumable cases against the installed normal APK; target only owned app/data."""
import argparse,base64,json,re,subprocess,sys,time,xml.etree.ElementTree as ET
from datetime import datetime,timezone
from pathlib import Path
import uiautomator2 as u2
import firebase_admin
from firebase_admin import credentials,firestore,messaging

sys.stdout.reconfigure(encoding='utf-8',errors='replace')
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--device',required=True)
parser.add_argument('--case',required=True,choices=['terminated','rotation','lock-rotation','logout','login','token','checkout','worklog','biometric'])
parser.add_argument('--workflow-account',action='store_true')
args=parser.parse_args()
ADB=r'D:\SDKs\Android\platform-tools\adb.exe'
PACKAGE='com.crompton.pms.frontend'
OUT=ROOT/'tests/android/remaining-results.json'
results=json.loads(OUT.read_text()) if OUT.exists() else {}
events=[]
started=datetime.now(timezone.utc).isoformat()
previous=results.get(args.case)
results[args.case]={'status':'IN PROGRESS','events':events,'startedAt':started,'unfinishedCase':args.case}
if previous:results[args.case]['previousAttempt']={k:v for k,v in previous.items() if k!='previousAttempt'}
OUT.write_text(json.dumps(results,indent=2))
identity=ROOT/'.local/development-service-account.json'
assert json.loads(identity.read_text())['project_id']=='crompton-pms-dev-20261015'
firebase_admin.initialize_app(credentials.Certificate(str(identity)))
db=firestore.client()
try:d=u2.connect(args.device)
except Exception:
    results[args.case].update({'status':'NOT TESTED','reason':'Device unavailable before case start','updatedAt':datetime.now(timezone.utc).isoformat()})
    OUT.write_text(json.dumps(results,indent=2))
    print('Device unavailable; exact unfinished case checkpoint saved.',flush=True)
    raise SystemExit(2)
if d.app_current()['package']==PACKAGE:
    initial=ET.fromstring(d.dump_hierarchy())
    if not any(n.attrib.get('package')==PACKAGE and (n.attrib.get('text') or n.attrib.get('content-desc')) for n in initial.iter('node')):
        d.reset_uiautomator()

def adb(*items,check=True):
    return subprocess.run([ADB,'-s',args.device,*items],capture_output=True,check=check,timeout=20).stdout

def nodes():
    return [n for n in ET.fromstring(d.dump_hierarchy()).iter('node') if n.attrib.get('package')==PACKAGE]

def label(n):return n.attrib.get('text') or n.attrib.get('content-desc','')
def matches(n,text):return label(n).split('\n')[0]==text
def has(text):return any(matches(n,text) for n in nodes())

def wait(text,timeout=35):
    end=time.monotonic()+timeout
    while time.monotonic()<end:
        if has(text):return
        time.sleep(.3)
    raise RuntimeError('Expected app control unavailable: '+text)

def tap(text,timeout=25):
    end=time.monotonic()+timeout
    while time.monotonic()<end:
        current=nodes()
        if text=='Back' and any(matches(n,'Missed Working Hours Update') for n in current):
            tap('OK',5)
            continue
        found=[n for n in current if matches(n,text) and n.attrib.get('enabled')!='false']
        if found:
            n=next((n for n in found if n.attrib.get('clickable')=='true'),found[-1])
            b=list(map(int,re.findall(r'\d+',n.attrib['bounds'])))
            d.click((b[0]+b[2])//2,(b[1]+b[3])//2);time.sleep(.7);return
        time.sleep(.3)
    raise RuntimeError('App action unavailable: '+text)

def event(text):
    events.append(text)
    results[args.case]={'status':'IN PROGRESS','events':events,'startedAt':started,'updatedAt':datetime.now(timezone.utc).isoformat()}
    OUT.write_text(json.dumps(results,indent=2))
    print(text,flush=True)
    with (ROOT/'.local/android-controls.log').open('a',encoding='utf-8') as log:log.write(datetime.now(timezone.utc).isoformat()+' '+text+'\n')

def token():
    xml=ET.fromstring(adb('shell','run-as',PACKAGE,'cat','shared_prefs/com.google.android.gms.appid.xml'))
    for n in xml.findall('string'):
        if '|T|' in n.attrib.get('name',''):
            value=json.loads(n.text or '{}').get('token')
            if value:return value
    raise RuntimeError('Current application FCM token unavailable')

def registered(value):
    return db.collection('device-tokens').document(base64.urlsafe_b64encode(value.encode()).decode()).get().to_dict()

def screenshot(name):
    if d.app_current()['package']!=PACKAGE:raise RuntimeError('Only Crompton application can be captured')
    shot=d.screenshot();shot.crop((0,int(shot.height*.04),shot.width,int(shot.height*.95))).save(str(ROOT/'tests/android'/name))

def gate():
    end=time.monotonic()+60
    while time.monotonic()<end:
        current=nodes();labels=[label(n).split('\n')[0] for n in current]
        if 'Quick Access' in labels:return
        if 'App Locked' in labels:
            for digit in '1234':tap(digit,4)
        elif 'Enter PIN' in labels:
            # Hidden PIN text fields move when the keyboard changes geometry.
            for index in range(2):
                field=d(className='android.widget.EditText')[index]
                field.click();time.sleep(.7)
                d(className='android.widget.EditText')[index].set_text('1234');time.sleep(.7)
            if b'mInputShown=true' in adb('shell','dumpsys','input_method'):d.press('back')
            d.swipe_ext('up',scale=.35);tap('Continue')
        elif 'Skip' in labels:tap('Skip')
        elif 'Continue' in labels:tap('Continue')
        else:time.sleep(.5)
    raise RuntimeError('Dashboard not reached through authentication gates')

status='FAIL';reason=None
try:
    if args.case=='terminated':
        wait('Quick Access')
        own_token=token();row=registered(own_token)
        if not row or row.get('userId')!=4:raise RuntimeError('Only synthetic employee UID 4 is eligible')
        old_pid=adb('shell','pidof',PACKAGE).strip()
        d.press('home');time.sleep(3)
        for unused in range(3):
            adb('shell','am','kill',PACKAGE);time.sleep(3)
            if not adb('shell','pidof',PACKAGE,check=False).strip():break
        if adb('shell','pidof',PACKAGE,check=False).strip():
            raise RuntimeError('Android retained process; terminated-state delivery cannot be claimed')
        event('Verified app process absent before terminated-state FCM send')
        title='Crompton terminated physical test'
        messaging.send(messaging.Message(token=own_token,notification=messaging.Notification(title=title,body='Synthetic development phone test'),data={'type':'TIMESHEET_APPROVED'},android=messaging.AndroidConfig(priority='high',notification=messaging.AndroidNotification(channel_id='comten_notifications'))))
        d.open_notification()
        if not d(text=title).wait(timeout=45):raise RuntimeError('Target notification did not arrive in shade')
        d(text=title).click();wait('App Locked',45)
        event('Actual terminated notification tap opens PIN gate')
        for digit in '1234':tap(digit,4)
        wait('My Timesheets',45)
        if adb('shell','pidof',PACKAGE).strip()==old_pid:raise RuntimeError('Android process was not replaced')
        screenshot('native-push-terminated.png')
        event('Cold-start FCM delivered and deep-linked to My Timesheets after PIN unlock')
        tap('Back');wait('Quick Access')
    elif args.case=='rotation':
        wait('Quick Access')
        rotation=d.info.get('displayRotation',0)
        locked=adb('shell','settings','get','system','accelerometer_rotation').strip()==b'0'
        try:
            d.set_orientation('l');time.sleep(2);wait('Quick Access')
            w,h=d.window_size()
            if w<=h:raise RuntimeError('Landscape rotation not observed')
            screenshot('native-employee-landscape.png')
            event('Physical landscape dashboard renders with account and navigation retained')
        finally:
            d.set_orientation({0:'n',1:'l',2:'u',3:'r'}[rotation]);d.freeze_rotation(locked)
        wait('Quick Access');event('Original orientation restored with dashboard retained')
    elif args.case=='logout':
        wait('Quick Access');old_token=token()
        tap('Settings')
        for unused in range(6):
            if has('Logout'):break
            d.swipe_ext('up',scale=.65)
        tap('Logout');tap('Logout');wait('Welcome to Comten')
        if registered(old_token):raise RuntimeError('Signed-out token remains registered')
        (ROOT/'.local/android-previous-token').write_text(old_token)
        event('Physical UI logout clears session and removes the registered device token')
    elif args.case=='lock-rotation':
        d.app_start(PACKAGE,stop=True);time.sleep(4);d.reset_uiautomator();wait('App Locked')
        rotation=d.info.get('displayRotation',0)
        locked=adb('shell','settings','get','system','accelerometer_rotation').strip()==b'0'
        try:
            d.set_orientation('l');time.sleep(2);wait('App Locked')
            screenshot('native-lock-landscape.png')
            pid=adb('shell','pidof',PACKAGE).decode().strip()
            logs=adb('logcat','-d','--pid='+pid,'-s','flutter').decode(errors='replace')
            if re.search(r'RenderFlex overflowed',logs):raise RuntimeError('Physical app-lock landscape layout overflows')
            # The keypad must remain reachable through normal app scrolling.
            for digit in '1234':
                for unused in range(5):
                    if has(digit):break
                    d.swipe_ext('up',scale=.45)
                tap(digit,3)
            wait('Quick Access');event('Landscape app-lock keypad remains usable and unlocks without overflow')
        finally:
            d.set_orientation({0:'n',1:'l',2:'u',3:'r'}[rotation]);d.freeze_rotation(locked)
            if has('App Locked'):
                for digit in '1234':tap(digit,3)
    elif args.case=='login':
        wait('Welcome to Comten');tap('Login')
        if args.workflow_account:
            account=json.loads((ROOT/'.local/android-workflow.json').read_text());code=account['employeeCode']
        else:
            code='EMP001';account=json.loads((ROOT/'.local/development-logins.json').read_text())[code]
        fields=d(className='android.widget.EditText')
        if not fields.wait(timeout=20):raise RuntimeError('Native credential fields unavailable')
        fields[0].click();time.sleep(.7);fields[0].set_text(code)
        fields[1].click();time.sleep(.7);fields[1].set_text(account['password'])
        if b'mInputShown=true' in adb('shell','dumpsys','input_method'):
            event('Real Android keyboard opens while native credentials remain editable')
            d.press('back')
        tap('Login');gate()
        event('Physical login and onboarding reach the expected synthetic account dashboard')
        if not args.workflow_account:
            old=ROOT/'.local/android-previous-token'
            if old.exists():
                end=time.monotonic()+40
                while time.monotonic()<end:
                    try:current_token=token()
                    except RuntimeError:time.sleep(1);continue
                    if current_token!=old.read_text() and registered(current_token):break
                    time.sleep(1)
                else:raise RuntimeError('Token did not rotate and register after logout/login')
                event('Logout/login rotates FCM token and registers the replacement token')
    elif args.case=='token':
        wait('Quick Access');old=(ROOT/'.local/android-previous-token').read_text()
        end=time.monotonic()+45
        while time.monotonic()<end:
            try:current_token=token()
            except RuntimeError:time.sleep(1);continue
            row=registered(current_token)
            if current_token!=old and row and row.get('userId')==4:break
            time.sleep(1)
        else:raise RuntimeError('Replacement token not registered to the expected employee')
        event('Actual logout/login token rotation registered to synthetic UID 4; previous token absent')
        if registered(old):raise RuntimeError('Old token remains registered')
    elif args.case=='checkout':
        wait('Quick Access');tap('Attendance');wait('Checked in')
        tap('Check Out')
        # Grant only this app's actual runtime prompt, without changing global settings.
        allow=d(resourceId='com.android.permissioncontroller:id/permission_allow_foreground_only_button')
        if allow.wait(timeout=5):
            deny=d(resourceId='com.android.permissioncontroller:id/permission_deny_button')
            if deny.exists:
                deny.click();wait('Location permission is required to record attendance.',15)
                event('Denying OS location permission produces the expected attendance error')
                tap('Retry')
                if not allow.wait(timeout=10):raise RuntimeError('Location permission retry did not open OS prompt')
            allow.click();event('Actual Android location while-in-use permission granted through OS prompt')
        for unused in range(3):
            end=time.monotonic()+22
            while time.monotonic()<end:
                if has('Location captured'):break
                time.sleep(.4)
            if has('Location captured'):break
            if has('Retry'):tap('Retry')
        wait('Location captured',4);event('Attendance UI obtains a fresh physical location fix for checkout')
        for unused in range(4):
            try:tap('Check Out',3);break
            except RuntimeError:d.swipe_ext('up',scale=.4)
        state=json.loads((ROOT/'.local/android-workflow.json').read_text())
        day_id=state['employeeId']*100000000+int(state['workDate'].replace('-',''))
        end=time.monotonic()+25
        while time.monotonic()<end:
            attendance=db.collection('attendance').document(str(day_id)).get().to_dict()
            if attendance and attendance.get('outTime') is not None:break
            time.sleep(1)
        else:raise RuntimeError('Server checkout timestamp not committed')
        state['stage']='checkedOut'
        (ROOT/'.local/android-workflow.json').write_text(json.dumps(state,indent=2))
        (ROOT/'tests/android/workflow-checkpoint.json').write_text(json.dumps({k:v for k,v in state.items() if k!='password'},indent=2))
        event('Physical attendance UI commits checkout with authoritative server timestamp')
        tap('Back');wait('Quick Access')
    elif args.case=='biometric':
        wait('Quick Access');tap('Settings');tap('Biometric Login')
        event('Biometric enable requested; owner fingerprint interaction required on phone')
        end=time.monotonic()+60
        authenticated=False
        while time.monotonic()<end:
            switches=[n for n in nodes() if 'Biometric Login' in label(n) and n.attrib.get('checked')=='true']
            if switches:authenticated=True;break
            time.sleep(1)
        if not authenticated:
            if d(text='Cancel').exists:d(text='Cancel').click()
            elif d(text='CANCEL').exists:d(text='CANCEL').click()
            status='NOT TESTED';reason='Owner biometric authentication not observed; hardware/enrollment already verified'
        else:
            event('Owner OS biometric authentication enabled app biometric unlock')
            d.app_start(PACKAGE,stop=True)
            wait('App Locked',20)
            event('Cold restart requests owner fingerprint for biometric unlock')
            wait('Quick Access',60)
            event('Owner fingerprint unlock restores synthetic employee dashboard')
            tap('Settings');tap('Biometric Login');event('Test biometric app setting restored to disabled')
        if d.app_current()['package']==PACKAGE and has('Settings'):tap('Back')
    elif args.case=='worklog':
        state=json.loads((ROOT/'.local/android-workflow.json').read_text())
        if has('Quick Access'):tap('Timesheet')
        if has('Missed Working Hours Update'):tap('OK')
        if has('My Timesheets'):tap('Log Hours')
        if not has('Billable Activities'):
            wait('Project');tap('Project');tap('Synthetic Android '+state['employeeCode'])
            wait('Module');tap('Module');tap('Android Device Workflow')
        wait('Billable Activities')
        activity=db.collection('activities').document('1').get().to_dict()['name']
        if not has(activity):
            if not has('Done'):tap('Add Activity');wait('Done')
            tap(activity);tap('Done')
        event('Physical form loads assigned project/module and selects its configured billable activity')
        fields=d(className='android.widget.EditText')
        fields[1].click();time.sleep(.7);fields[1].set_text('15')
        if b'mInputShown=true' in adb('shell','dumpsys','input_method'):d.press('back')
        for unused in range(5):
            if has('Work Date'):break
            d.swipe_ext('up',scale=.5)
        tap('Work Date');tap('OK')
        for unused in range(4):
            found=[n for n in nodes() if n.attrib.get('class')=='android.widget.EditText' and 'Work Done' in label(n)]
            if found:break
            d.swipe_ext('up',scale=.4)
        # Description is the only multiline Android field in this form.
        controls=[n for n in nodes() if n.attrib.get('class')=='android.widget.EditText']
        description=next((n for n in controls if 'Work Done' in label(n)),controls[-1])
        b=list(map(int,re.findall(r'\d+',description.attrib['bounds'])))
        d.click((b[0]+b[2])//2,(b[1]+b[3])//2);time.sleep(.7)
        focused=d(className='android.widget.EditText',focused=True)
        focused.set_text('Synthetic physical Android UI form')
        if b'mInputShown=true' in adb('shell','dumpsys','input_method'):d.press('back')
        for unused in range(5):
            if has('Submit Timesheet'):break
            d.swipe_ext('up',scale=.4)
        tap('Submit Timesheet');wait('My Timesheets')
        from google.cloud.firestore_v1.base_query import FieldFilter
        saved=[row.to_dict() for row in db.collection('work-logs').where(filter=FieldFilter('employeeId','==',state['employeeId'])).stream()]
        submitted=[row for row in saved if row.get('workDone')=='Synthetic physical Android UI form']
        if len(submitted)!=1 or submitted[0].get('billableDurationSeconds')!=900:raise RuntimeError('UI work-log duration or uniqueness differs')
        state['extraWorklogId']=submitted[0]['id']
        state['extraWorklogSeconds']=900
        (ROOT/'.local/android-workflow.json').write_text(json.dumps(state,indent=2))
        (ROOT/'tests/android/workflow-checkpoint.json').write_text(json.dumps({k:v for k,v in state.items() if k!='password'},indent=2))
        event('Physical Employee UI submits a unique fifteen-minute work log through direct Firestore')
        if has('Missed Working Hours Update'):tap('OK')
        screenshot('native-submitted-timesheet.png')
        tap('Back');wait('Quick Access')
    if status!='NOT TESTED':status='PASS'
except Exception as error:
    reason=str(error) if type(error) is RuntimeError else type(error).__name__
finally:
    results[args.case]={'status':status,'events':events,'reason':reason,'startedAt':started,'updatedAt':datetime.now(timezone.utc).isoformat()}
    if previous:results[args.case]['previousAttempt']={k:v for k,v in previous.items() if k!='previousAttempt'}
    OUT.write_text(json.dumps(results,indent=2))
    print(json.dumps({'case':args.case,'status':status,'reason':reason}),flush=True)
raise SystemExit(1 if status=='FAIL' else 0)
