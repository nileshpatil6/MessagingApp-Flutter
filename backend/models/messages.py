from datetime import datetime, timedelta
from app.database import execute, fetchone, fetchall


def _format(row: dict) -> dict:
    if not row:
        return None
    return {
        "message_id": row.get("MESSAGE_ID"),
        "room_id": row.get("ROOM_ID"),
        "message_content": row.get("MESSAGE_CONTENT"),
        "dead_time": row.get("DEAD_TIME"),
        "sender_device_id": row.get("SENDER_DEVICE_ID"),
        "type_message": row.get("TYPE_MESSAGE"),
        "created_at": row.get("CREATED_AT"),
        "reply_message_id": row.get("REPLY_MESSAGE_ID"),
        "is_pin": row.get("IS_PIN", 0),
        "pin_time": row.get("PIN_TIME"),
    }


def _compute_dead_time_setting(dead_time: str) -> datetime | None:
    if not dead_time or dead_time == "OFF":
        return None
    now = datetime.now()
    mapping = {
        "ONE_DAY_LATER": timedelta(days=1),
        "ONE_WEEK_LATER": timedelta(weeks=1),
        "ONE_MONTH_LATER": timedelta(days=30),
        "FIVE_SECONDS": timedelta(seconds=5),
        "THIRTY_SECONDS": timedelta(seconds=30),
        "ONE_MINUTE": timedelta(minutes=1),
        "FIVE_MINUTES": timedelta(minutes=5),
        "THIRTY_MINUTES": timedelta(minutes=30),
        "ONE_HOUR": timedelta(hours=1),
    }
    if dead_time in mapping:
        return now + mapping[dead_time]
    if dead_time.startswith("CUSTOM:"):
        try:
            secs = int(dead_time.split(":")[1])
            return now + timedelta(seconds=secs)
        except Exception:
            pass
    try:
        days = float(dead_time)
        return now + timedelta(days=days)
    except Exception:
        pass
    return None


async def insert(message: dict) -> dict:
    dead_time_setting = _compute_dead_time_setting(message.get("dead_time"))
    last_id = await execute(
        """INSERT INTO messages
           (ROOM_ID, MESSAGE_CONTENT, DEAD_TIME, DEAD_TIME_SETTING,
            SENDER_DEVICE_ID, TYPE_MESSAGE, CREATED_AT, REPLY_MESSAGE_ID)
           VALUES (%s, %s, %s, %s, %s, %s, %s, %s)""",
        (
            message.get("room_id"),
            message.get("message_content"),
            message.get("dead_time"),
            dead_time_setting,
            message.get("sender_device_id"),
            message.get("type_message", 0),
            message.get("created_at") or datetime.now(),
            message.get("reply_message_id"),
        ),
    )
    return await get_by_id(last_id)


async def get_by_id(message_id: int) -> dict:
    row = await fetchone("SELECT * FROM messages WHERE MESSAGE_ID = %s", (message_id,))
    msg = _format(row)
    if msg and msg.get("reply_message_id"):
        reply = await get_reply(msg["reply_message_id"])
        msg["reply_message"] = reply
        del msg["reply_message_id"]
    return msg


async def get_reply(message_id: int) -> dict | None:
    row = await fetchone("SELECT * FROM messages WHERE MESSAGE_ID = %s", (message_id,))
    if not row:
        return None
    msg = _format(row)
    if msg:
        del msg["reply_message_id"]
    return msg


async def get_by_room(room_id) -> dict:
    rows = await fetchall(
        "SELECT * FROM messages WHERE ROOM_ID = %s ORDER BY CREATED_AT ASC, MESSAGE_ID ASC",
        (room_id,),
    )
    messages = []
    for row in rows:
        msg = _format(row)
        if msg.get("reply_message_id"):
            reply = await get_reply(msg["reply_message_id"])
            msg["reply_message"] = reply
            del msg["reply_message_id"]
        messages.append(msg)
    return {"room_id": room_id, "messages": messages}


async def remove_by_list(message_ids: list) -> bool:
    if not message_ids:
        return False
    placeholders = ",".join(["%s"] * len(message_ids))
    await execute(f"DELETE FROM messages WHERE MESSAGE_ID IN ({placeholders})", message_ids)
    return True


async def get_expired(current_time: datetime) -> list:
    rows = await fetchall(
        "SELECT MESSAGE_ID, ROOM_ID FROM messages WHERE DEAD_TIME_SETTING IS NOT NULL AND DEAD_TIME_SETTING <= %s",
        (current_time,),
    )
    return rows or []


async def pin_message(room_id, message_id: int, is_pin: int, pin_time=None) -> dict:
    pt = pin_time if is_pin == 1 else None
    await execute(
        "UPDATE messages SET IS_PIN = %s, PIN_TIME = %s WHERE MESSAGE_ID = %s",
        (is_pin, pt, message_id),
    )
    return await get_pin_list(room_id)


async def get_pin_list(room_id) -> dict:
    rows = await fetchall(
        "SELECT * FROM messages WHERE ROOM_ID = %s AND IS_PIN = 1 ORDER BY PIN_TIME DESC",
        (room_id,),
    )
    messages = [_format(r) for r in rows]
    for m in messages:
        if "reply_message_id" in m:
            del m["reply_message_id"]
    return {"room_id": room_id, "messages": messages}


async def forward_message(params: dict) -> dict:
    last_id = await execute(
        """INSERT INTO messages (ROOM_ID, MESSAGE_CONTENT, SENDER_DEVICE_ID, DEAD_TIME,
           DEAD_TIME_SETTING, TYPE_MESSAGE, CREATED_AT)
           SELECT %s, MESSAGE_CONTENT, %s, DEAD_TIME, DEAD_TIME_SETTING, TYPE_MESSAGE, %s
           FROM messages WHERE MESSAGE_ID = %s""",
        (
            params["room_id"],
            params["sender_device_id"],
            params.get("created_at") or datetime.now(),
            params["message_id"],
        ),
    )
    return await get_by_id(last_id)
