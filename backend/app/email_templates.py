"""Escaped transactional content. Credentials never appear in queued email data."""
from html import escape


def render(kind, name, **values):
    titles={'invitation':'Welcome to Comten - Your Account is Ready','activation_otp':'Comten - Verify your email to activate your account','activation':'Your Comten account is active','recovery':'Comten password recovery','security':'Comten account security update','approval':'Comten approval update'}
    title=titles[kind]
    if kind=='activation_otp':
        message=f"Your employee code is {values['code']}. Your email verification OTP is {values['otp']}. It expires in 10 minutes. Enter your employee code in Activate Account, verify the OTP, then set your password and log in. Do not share this code."
    elif kind=='recovery':
        message=f"Your verification code is {values['otp']}. It expires in 10 minutes. Do not share this code with anyone."
    elif kind=='invitation':
        message=f"Your employee account {values['code']} has been created. Open Activate Account, enter your employee code and verify the OTP sent to your registered email. Then set your password and log in."
    elif kind=='activation': message='Your account has been activated. Sign in to Comten using your existing credentials.'
    elif kind=='security': message=values.get('message','Your account security settings changed. Contact your administrator immediately if you did not request this change.')
    else: message=values.get('message','An approval has been updated. Open Comten to review the details.')
    text=f"Hello {name},\n\n{message}\n\nComten PMS\nThis is an automated transactional message."
    html=f'''<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;background:#f4f6f9;font-family:Arial,sans-serif;color:#0B2545">
<table role="presentation" width="100%"><tr><td style="padding:24px 12px"><table role="presentation" width="100%" style="max-width:600px;margin:auto;background:white;border-radius:8px"><tr><td style="padding:28px">
<h1 style="font-size:22px;line-height:28px">{escape(title)}</h1><p>Hello {escape(name)},</p>
<p style="font-size:16px;line-height:25px">{escape(message)}</p><p style="font-size:12px;color:#596575">Comten PMS<br>This is an automated transactional message.</p>
</td></tr></table></td></tr></table></body></html>'''
    return title,html,text
