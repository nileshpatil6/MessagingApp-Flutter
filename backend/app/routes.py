import os
import json
import shutil
from datetime import datetime
from pathlib import Path

from fastapi import APIRouter, File, UploadFile, Request, HTTPException
from fastapi.responses import FileResponse, JSONResponse

import models.user_watched as user_model
import models.call_history as call_model
import models.area_limited as area_model
import models.path_move_history as path_model
from app.database import fetchone, fetchall, execute

router = APIRouter()

UPLOADS_DIR = Path("uploads")
PUBLIC_DIR = Path("uploads/public")
UPLOADS_DIR.mkdir(exist_ok=True)
PUBLIC_DIR.mkdir(exist_ok=True)


# ── AUTH ──────────────────────────────────────

@router.post("/register")
async def register(request: Request):
    body = await request.json()
    username = body.get("username", "")
    password = body.get("password", "")
    existing = await fetchone(
        "SELECT USER_ID FROM user_followers WHERE USER_NAME=%s", (username,)
    )
    if existing:
        return JSONResponse({"errorCode": "username exits"}, status_code=400)
    token = username + password
    await execute(
        "INSERT INTO user_followers (USER_NAME, TOKEN, PASSWORD) VALUES (%s,%s,%s)",
        (username, token, password),
    )
    return {"success": "user registered successfully"}


@router.post("/login")
async def login(request: Request):
    body = await request.json()
    username = body.get("username", "")
    password = body.get("password", "")
    user = await fetchone("SELECT * FROM user_followers WHERE USER_NAME=%s", (username,))
    if not user:
        return JSONResponse({"errorCode": "user not found"}, status_code=402)
    if user["PASSWORD"] != password:
        return JSONResponse({"errorCode": "wrong password"}, status_code=402)
    return {"success": dict(user)}


# ── USERS ─────────────────────────────────────

@router.get("/listUsersOnline")
async def list_users_online():
    rows = await fetchall(
        "SELECT * FROM user_watched WHERE USER_TYPE='WT' AND ACTIVED_AT >= DATE_SUB(NOW(), INTERVAL 7 DAY)"
    )
    return rows or []


@router.post("/getUserHistoryInfo")
async def get_user_history_info(request: Request):
    body = await request.json()
    follower_id = body.get("followerId")
    rows = await fetchall(
        "SELECT DISTINCT CALL_WATCHED_ID as WATCHED_ID, '' as WATCHED_NAME FROM call_history WHERE CALL_USER_ID=%s",
        (follower_id,),
    )
    return rows or []


@router.post("/changeWatchedInfo")
async def change_watched_info(request: Request):
    body = await request.json()
    watched_id = body.get("watchedId")
    data = {}
    if "watchedName" in body:
        data["watched_name"] = body["watchedName"]
    if "icon" in body:
        data["icon"] = body["icon"]
    if "fcmToken" in body:
        data["fcm_token"] = body["fcmToken"]
    if data and watched_id:
        await user_model.update_by_watched_id(watched_id, data)
    return {"success": "update to user_watched success"}


# ── CALL HISTORY ──────────────────────────────

@router.post("/listCallHistory")
async def list_call_history(request: Request):
    body = await request.json()
    token = body.get("token")
    watched_id = body.get("watchedId")
    follower_id = body.get("followerId")
    user = await fetchone("SELECT USER_ID FROM user_followers WHERE TOKEN=%s", (token,))
    if not user:
        return JSONResponse({"errorCode": "invalid token"}, status_code=401)
    rows = await call_model.list_by_user(follower_id, watched_id)
    return rows or []


@router.post("/deletePhoneCallInfo")
async def delete_call_info(request: Request):
    body = await request.json()
    call_id = body.get("callId")
    await call_model.delete_by_id(call_id)
    return {"success": "deleted"}


# ── FILE UPLOAD ───────────────────────────────

@router.post("/upload_file")
async def upload_file(files: list[UploadFile] = File(...)):
    saved = []
    for f in files:
        dest = UPLOADS_DIR / f.filename
        with open(dest, "wb") as out:
            shutil.copyfileobj(f.file, out)
        saved.append({"filename": f.filename, "size": dest.stat().st_size})
    return {"success": True, "files": saved}


@router.post("/upload_file_chat")
async def upload_file_chat(files: UploadFile = File(...)):
    f = files
    stem = Path(f.filename).stem
    suffix = Path(f.filename).suffix
    ts = int(datetime.now().timestamp() * 1000)
    filename = f"{stem}_{ts}{suffix}"
    dest = PUBLIC_DIR / filename
    count = 0
    while dest.exists():
        count += 1
        filename = f"{stem}_{ts}_{count}{suffix}"
        dest = PUBLIC_DIR / filename
    with open(dest, "wb") as out:
        shutil.copyfileobj(f.file, out)
    return {"success": True, "files": [{"filename": filename, "url": f"/public/{filename}"}]}


@router.get("/download_file/{file_id}")
async def download_file(file_id: str):
    path = UPLOADS_DIR / file_id
    if not path.exists():
        raise HTTPException(status_code=404, detail="File not found")

    async def cleanup():
        try:
            path.unlink()
        except Exception:
            pass

    response = FileResponse(path, filename=file_id)
    # Delete after send (background task)
    from fastapi import BackgroundTasks
    return response  # file deleted by caller or we use background


@router.get("/public/{name}")
async def get_public_file(name: str):
    path = PUBLIC_DIR / name
    if not path.exists():
        raise HTTPException(status_code=404, detail="File not found")
    return FileResponse(path, headers={"Content-Disposition": "inline"})


@router.get("/getListFileUpload")
async def get_file_upload_list():
    rows = await fetchall("SELECT * FROM upload_info")
    return rows or []


# ── LOCATION ──────────────────────────────────

@router.post("/getListPathMoveHistory")
async def get_path_history(request: Request):
    body = await request.json()
    rows = await path_model.list_by_date(body.get("watchedId"), body.get("date"))
    return rows


@router.post("/getListPathMoveHistoryDates")
async def get_path_dates(request: Request):
    body = await request.json()
    dates = await path_model.get_dates(body.get("watchedId"))
    return dates


@router.post("/getListAreaLimited")
@router.get("/getListAreaLimited")
async def get_area_limited(request: Request):
    try:
        body = await request.json()
        watched_id = body.get("watchedId")
    except Exception:
        watched_id = request.query_params.get("watchedId")
    rows = await area_model.get_by_watched(watched_id)
    return rows


@router.post("/addAreaLimited")
async def add_area_limited(request: Request):
    body = await request.json()
    area = await area_model.insert({
        "user_id": body.get("userId"),
        "watched_id": body.get("watchedId"),
        "fcm_token": body.get("fcmToken"),
        "lat_lng_list": body.get("latLngList"),
        "distance_alert": body.get("distanceAlert"),
        "wt_display_name": body.get("wtDisplayName"),
    })
    return area
