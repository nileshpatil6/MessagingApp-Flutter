from typing import Optional
from datetime import datetime
from app.database import execute, fetchone


def _format(row: dict) -> dict:
    if not row:
        return None
    return {
        "room_id": row.get("ROOM_ID"),
        "sender_device_id": row.get("SENDER_DEVICE_ID"),
        "receiver_device_id": row.get("RECEIVER_DEVICE_ID"),
        "created_at": row.get("CREATED_AT"),
    }


async def get(sender_id: str, receiver_id: str) -> Optional[dict]:
    row = await fetchone(
        """SELECT * FROM private_rooms
           WHERE (SENDER_DEVICE_ID = %s AND RECEIVER_DEVICE_ID = %s)
              OR (SENDER_DEVICE_ID = %s AND RECEIVER_DEVICE_ID = %s)""",
        (sender_id, receiver_id, receiver_id, sender_id),
    )
    return _format(row)


async def insert(sender_id: str, receiver_id: str) -> dict:
    last_id = await execute(
        "INSERT INTO private_rooms (SENDER_DEVICE_ID, RECEIVER_DEVICE_ID, CREATED_AT) VALUES (%s, %s, %s)",
        (sender_id, receiver_id, datetime.now()),
    )
    row = await fetchone("SELECT * FROM private_rooms WHERE ROOM_ID = %s", (last_id,))
    return _format(row)


async def get_or_create(sender_id: str, receiver_id: str) -> dict:
    room = await get(sender_id, receiver_id)
    if room:
        return room
    return await insert(sender_id, receiver_id)


async def get_by_id(room_id: int) -> Optional[dict]:
    row = await fetchone("SELECT * FROM private_rooms WHERE ROOM_ID = %s", (room_id,))
    return _format(row)
