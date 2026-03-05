import os

from fastapi import APIRouter, Depends, Header, HTTPException

import database.notifications as notification_db
from models.other import SaveFcmTokenRequest
from utils.notifications import send_notification
from utils.other import endpoints as auth

router = APIRouter()


@router.post('/v1/users/fcm-token')
def save_token(
    data: SaveFcmTokenRequest,
    uid: str = Depends(auth.get_current_user_uid),
    x_app_platform: str = Header(None, alias='X-App-Platform'),
    x_device_id_hash: str = Header(None, alias='X-Device-Id-Hash'),
):
    platform = x_app_platform or 'unknown'
    device_hash = x_device_id_hash or 'default'
    device_key = f"{platform}_{device_hash}"

    token_data = data.dict()
    token_data['device_key'] = device_key
    notification_db.save_token(uid, token_data)
    return {'status': 'Ok'}


@router.post('/v1/notification')
def send_notification_to_user(data: dict, secret_key: str = Header(...)):
    if secret_key != os.getenv('ADMIN_KEY'):
        raise HTTPException(status_code=403, detail='You are not authorized to perform this action')
    if not data.get('uid'):
        raise HTTPException(status_code=400, detail='uid is required')
    uid = data['uid']
    send_notification(uid, data['title'], data['body'], data.get('data', {}))
    return {'status': 'Ok'}
