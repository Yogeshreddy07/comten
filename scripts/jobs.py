"""Run with the same backend environment. Intended for a Railway cron service."""
import sys,time,asyncio
from pathlib import Path
from datetime import datetime,timedelta,timezone
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'backend'))
from app.store import db,all_rows,get
from app.messaging import notify,dispatch_pending
from app.config import settings
from firebase_admin import messaging

def run():
    now=datetime.now(timezone(timedelta(hours=5,minutes=30)))
    dispatch_pending()
    from app.delivery import event,dispatch_emails
    # Stable notification IDs deduplicate scheduler retries, including direct SDK writes.
    for item in all_rows('notifications'):
        created=item.get('createdAt')
        if isinstance(created,str):
            try: created=datetime.fromisoformat(created.replace('Z','+00:00'))
            except ValueError: continue
        if not isinstance(created,datetime) or created.timestamp()<time.time()-86400: continue
        if 'APPROV' in item.get('type','') or 'REJECT' in item.get('type',''):
            event(item['userId'],'approval','notification-'+str(item['id']),message=item.get('message','Review your approval in Comten.'))
    asyncio.run(dispatch_emails())
    for person in ([] if now.weekday()==6 else all_rows('employees')):
        if not person.get('active') or person['role'] not in ('EMPLOYEE','TEAM_LEADER'):continue
        key=f"reminder-{person['id']}-{now.date()}"
        ref=db.collection('job-runs').document(key)
        try:ref.create({'id':key,'expires':time.time()+30*86400})
        except Exception as e:
            from google.api_core.exceptions import AlreadyExists
            if isinstance(e,AlreadyExists):continue
            raise
        notify(person['id'],'Daily timesheet reminder','Review and submit your working hours.','TIMESHEET_REMINDER',int(time.time()*1000000))
    for collection in ('recovery','phone-challenges','phone-rate-limits','provider-deliveries','email-outbox','file-rate-limits'):
        for data in all_rows(collection):
            if data.get('expires',data.get('sent',0)+600)<time.time()-86400:
                db.collection(collection).document(str(data['id'])).delete()
    if settings.r2_endpoint and settings.r2_bucket:
        from app.storage import cleanup_abandoned
        cleanup_abandoned()

if __name__=='__main__':run();print('Scheduled job completed')
