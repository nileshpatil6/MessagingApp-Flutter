from app.database import execute, fetchall


async def update_in_area(user_id: str, watched_id: str, is_in_area: str):
    await execute(
        "UPDATE area_limited SET IN_AREA=%s WHERE USER_ID=%s AND WATCHED_ID=%s",
        (is_in_area, user_id, watched_id),
    )


async def get_by_watched(watched_id: str) -> list:
    rows = await fetchall("SELECT * FROM area_limited WHERE WATCHED_ID=%s", (watched_id,))
    return rows or []


async def insert(data: dict) -> dict:
    await execute(
        """INSERT INTO area_limited (USER_ID, WATCHED_ID, FCM_TOKEN, LAT_LNG_LIST, DISTANCE_ALERT, WT_DISPLAY_NAME, IN_AREA)
           VALUES (%s,%s,%s,%s,%s,%s,'false')""",
        (
            data.get("user_id"),
            data.get("watched_id"),
            data.get("fcm_token"),
            data.get("lat_lng_list"),
            data.get("distance_alert"),
            data.get("wt_display_name"),
        ),
    )
    rows = await get_by_watched(data.get("watched_id"))
    return rows[-1] if rows else {}
