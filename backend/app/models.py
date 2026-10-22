from typing import Literal
import re
from pydantic import BaseModel, ConfigDict, Field,field_validator

Role = Literal['CAPTAIN', 'PROJECT_CONTROLLER', 'TEAM_LEADER', 'EMPLOYEE']


def valid_password(value):
    return isinstance(value,str) and 8<=len(value)<=128 and all(re.search(p,value) for p in (r'[A-Z]',r'[a-z]',r'\d',r'[@$!%*?&]'))


class EmployeeCreate(BaseModel):
    model_config = ConfigDict(extra='forbid')
    employeeCode: str = Field(pattern=r'^[A-Za-z0-9_-]{2,30}$')
    name: str = Field(min_length=1, max_length=100)
    email: str = Field(max_length=254, pattern=r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
    phone: str = Field(default='', max_length=16)
    role: Role
    password: str | None = Field(default=None, min_length=8, max_length=128)

    @field_validator('password')
    @classmethod
    def password_policy(cls,value):
        if value is not None and not valid_password(value):raise ValueError('Password must match the existing complexity policy')
        return value
