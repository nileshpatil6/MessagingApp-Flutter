from datetime import datetime
from app.database import execute, fetchall


async def insert(data: dict) -> int:
    return await execute(
        """INSERT INTO call_history (CALL_USER_ID, CALL_WATCHED_ID, CALL_LENGTH, CALL_TYPE, FILE_PATH, DATE)
           VALUES (%s, %s, %s, %s, %s, %s)""",
        (
            data.get("call_user_id"),
            data.get("call_watched_id"),
            data.get("call_length"),
            data.get("call_type"),
            data.get("file_path"),
            data.get("date") or str(datetime.now()),
        ),
    )


async def list_by_user(follower_id: str, watched_id: str) -> list:
    rows = await fetchall(
        "SELECT * FROM call_history WHERE CALL_USER_ID=%s AND CALL_WATCHED_ID=%s ORDER BY CALL_ID DESC",
        (follower_id, watched_id),
    )
    return rows or []


async def delete_by_id(call_id: int):
    await execute("DELETE FROM call_history WHERE CALL_ID=%s", (call_id,))
