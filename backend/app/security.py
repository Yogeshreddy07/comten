from fastapi import Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from firebase_admin import auth
from .store import get

bearer = HTTPBearer(auto_error=False)
ROLES = {'CAPTAIN', 'PROJECT_CONTROLLER', 'TEAM_LEADER', 'EMPLOYEE'}


def current_user(credentials: HTTPAuthorizationCredentials = Depends(bearer)):
    if not credentials:
        raise HTTPException(401, 'Authentication required')
    try:
        token = auth.verify_id_token(credentials.credentials, check_revoked=True)
        user = get('employees', token['uid'])
    except Exception:
        raise HTTPException(401, 'Session expired') from None
    if not user or not user.get('active') or user.get('activationStatus') == 'PENDING' or user.get('role') not in ROLES:
        raise HTTPException(403, 'Account is inactive')
    return user


def require(user, *roles):
    if user['role'] not in roles:
        raise HTTPException(403, 'Permission denied')


def manager(user):
    require(user, 'CAPTAIN', 'PROJECT_CONTROLLER')
