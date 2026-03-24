from datetime import datetime
from app.database import execute, fetchone, fetchall


def _format(row: dict) -> dict:
    if not row:
        return None
    return {
        "watched_id": row.get("WATCHED_ID"),
        "watched_device_id": row.get("WATCHED_DEVICE_ID"),
        "watched_mobile_num": row.get("WATCHED_MOBILE_NUM"),
        "watched_mobile_type": row.get("WATCHED_MOBILE_TYPE"),
        "watched_name": row.get("WATCHED_NAME"),
        "watched_status": row.get("WATCHED_STATUS"),
        "socket_id": row.get("SOCKET_ID"),
        "user_type": row.get("USER_TYPE"),
        "watched_room": row.get("WATCHED_ROOM"),
        "battery": row.get("BATTERY"),
        "fcm_token": row.get("FCM_TOKEN"),
        "icon": row.get("ICON"),
        "actived_at": row.get("ACTIVED_AT"),
        "os_version": row.get("OS_VERSION"),
    }


async def insert_or_update(user: dict) -> int:
    existing = await fetchone(
        "SELECT WATCHED_ID FROM user_watched WHERE WATCHED_DEVICE_ID = %s",
        (user.get("watched_device_id"),),
    )
    if existing:
        await execute(
            """UPDATE user_watched SET WATCHED_NAME=%s, WATCHED_MOBILE_TYPE=%s,
               SOCKET_ID=%s, USER_TYPE=%s, FCM_TOKEN=%s, OS_VERSION=%s, ACTIVED_AT=NOW()
               WHERE WATCHED_DEVICE_ID=%s""",
            (
                user.get("watched_name"),
                user.get("watched_mobile_type"),
                user.get("socket_id"),
                user.get("user_type"),
                user.get("fcm_token"),
                user.get("os_version"),
                user.get("watched_device_id"),
            ),
        )
        return existing["WATCHED_ID"]
    else:
        return await execute(
            """INSERT INTO user_watched
               (WATCHED_DEVICE_ID, WATCHED_MOBILE_NUM, WATCHED_MOBILE_TYPE, WATCHED_NAME,
                WATCHED_STATUS, SOCKET_ID, USER_TYPE, FCM_TOKEN, OS_VERSION, ACTIVED_AT)
               VALUES (%s,%s,%s,%s,'ON',%s,%s,%s,%s,NOW())""",
            (
                user.get("watched_device_id"),
                user.get("watched_mobile_num"),
                user.get("watched_mobile_type"),
                user.get("watched_name"),
                user.get("socket_id"),
                user.get("user_type"),
                user.get("fcm_token"),
                user.get("os_version"),
            ),
        )


async def update_battery(device_id: str, battery: str):
    await execute(
        "UPDATE user_watched SET BATTERY=%s, ACTIVED_AT=NOW() WHERE WATCHED_DEVICE_ID=%s",
        (battery, device_id),
    )


async def update_socket(device_id: str, socket_id: str):
    await execute(
        "UPDATE user_watched SET SOCKET_ID=%s, ACTIVED_AT=NOW() WHERE WATCHED_DEVICE_ID=%s",
        (socket_id, device_id),
    )


async def get_by_device_id(device_id: str) -> dict | None:
    row = await fetchone(
        "SELECT * FROM user_watched WHERE WATCHED_DEVICE_ID=%s", (device_id,)
    )
    return _format(row)


async def get_by_socket_id(socket_id: str) -> dict | None:
    row = await fetchone("SELECT * FROM user_watched WHERE SOCKET_ID=%s", (socket_id,))
    return _format(row)


async def update_by_watched_id(watched_id: int, data: dict):
    fields = []
    values = []
    for col, val in data.items():
        fields.append(f"{col.upper()}=%s")
        values.append(val)
    values.append(watched_id)
    await execute(
        f"UPDATE user_watched SET {', '.join(fields)} WHERE WATCHED_ID=%s", values
    )
