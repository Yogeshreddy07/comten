"""Shared OTP attempt and resend lockout policy, persisted with each challenge."""
import math
from fastapi import HTTPException

MAX_ATTEMPTS = 3
LOCKOUT_SECONDS = 15 * 60
LOCKED = 'No attempts left. Please try again after 15 minutes.'


def wrong_otp(attempts):
    left = MAX_ATTEMPTS - attempts
    return LOCKED if left <= 0 else f'Incorrect OTP. {left} attempt{"s" if left != 1 else ""} left.'


def check_lock(state, now):
    remaining = math.ceil(state.get('lockedUntil', 0) - now)
    if remaining > 0:
        raise HTTPException(429, LOCKED, headers={'Retry-After': str(remaining)})
