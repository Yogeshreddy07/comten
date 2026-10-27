"""Background push delivery and checkout reminders, run inside the API service."""
import asyncio
import logging
import time
from datetime import datetime, timedelta, timezone

from google.api_core.exceptions import AlreadyExists

from .messaging import dispatch_pending, notify
from .store import db, all_rows

IST = timezone(timedelta(hours=5, minutes=30))
# Matches the mobile app's in-app popup (AttendanceViewModel.checkoutReminderThresholdHours).
CHECKOUT_REMINDER_AFTER = timedelta(hours=9)
PUSH_INTERVAL_SECONDS = 30
REMINDER_INTERVAL_SECONDS = 300


def _as_datetime(value):
    if isinstance(value, str):
        try: value = datetime.fromisoformat(value.replace('Z', '+00:00'))
        except ValueError: return None
    return value if isinstance(value, datetime) else None


def checkout_reminders(now=None):
    """Remind each employee once per attendance day when they've been checked
    in for 9+ hours without checking out. Returns the reminders sent."""
    now = now or datetime.now(timezone.utc)
    today = now.astimezone(IST).date()
    sent = []
    for day in (today, today - timedelta(days=1)):
        for row in all_rows('attendance', [('attendanceDate', day.isoformat())]):
            in_time = _as_datetime(row.get('inTime'))
            if row.get('outTime') is not None or in_time is None or now - in_time < CHECKOUT_REMINDER_AFTER:
                continue
            # The job-run marker makes the reminder once-only across passes and replicas.
            key = f"checkout-reminder-{row['id']}"
            try: db.collection('job-runs').document(key).create({'id': key, 'expires': time.time() + 30 * 86400})
            except AlreadyExists: continue
            notify(row['employeeId'], 'Checkout Reminder',
                   'You checked in over 9 hours ago and have not checked out yet.',
                   'CHECKOUT_REMINDER', time.time_ns() // 1000, attendanceId=row['id'])
            sent.append(row['id'])
    return sent


async def push_worker():
    """Deliver pending pushes every 30s and check for overdue checkouts every 5 min."""
    last_reminder = 0.0
    while True:
        try:
            await asyncio.to_thread(dispatch_pending)
            if time.monotonic() - last_reminder >= REMINDER_INTERVAL_SECONDS:
                await asyncio.to_thread(checkout_reminders)
                last_reminder = time.monotonic()
        except Exception:
            logging.getLogger('crompton').warning('Push worker will retry')
        await asyncio.sleep(PUSH_INTERVAL_SECONDS)
