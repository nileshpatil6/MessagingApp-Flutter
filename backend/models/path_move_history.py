from app.database import execute, fetchall


async def insert(data: dict):
    await execute(
        """INSERT INTO path_move_history (WATCHED_ID, START_TIME, END_TIME, DATE, PATH_MOVE)
           VALUES (%s,%s,%s,%s,%s)""",
        (
            data.get("watched_id"),
            data.get("start_time"),
            data.get("end_time"),
            data.get("date"),
            data.get("path_move"),
        ),
    )


async def list_by_date(watched_id: str, date: str) -> list:
    rows = await fetchall(
        "SELECT * FROM path_move_history WHERE WATCHED_ID=%s AND DATE=%s",
        (watched_id, date),
    )
    return rows or []


async def get_dates(watched_id: str) -> list:
    rows = await fetchall(
        "SELECT DISTINCT DATE FROM path_move_history WHERE WATCHED_ID=%s ORDER BY DATE DESC",
        (watched_id,),
    )
    return [r["DATE"] for r in rows] if rows else []
