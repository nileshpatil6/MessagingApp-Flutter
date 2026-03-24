from typing import Optional
import re
import sqlite3
import aiosqlite

DB_PATH = "messaging.db"
_db: aiosqlite.Connection = None

# ── SQL compatibility shims ────────────────────────────────────────────────
_DATE_SUB_RE = re.compile(
    r"DATE_SUB\(NOW\(\)\s*,\s*INTERVAL\s+(\d+)\s+DAY\)", re.IGNORECASE
)

def _adapt(sql: str) -> str:
    """Convert MySQL-flavoured SQL to SQLite-compatible SQL."""
    sql = sql.replace("%s", "?")
    sql = _DATE_SUB_RE.sub(lambda m: f"datetime('now', '-{m.group(1)} days')", sql)
    sql = re.sub(r"\bNOW\(\)", "datetime('now')", sql, flags=re.IGNORECASE)
    return sql

# ── Schema ─────────────────────────────────────────────────────────────────
_SCHEMA = """
CREATE TABLE IF NOT EXISTS user_followers (
    USER_ID   INTEGER PRIMARY KEY AUTOINCREMENT,
    USER_NAME TEXT,
    TOKEN     TEXT,
    PASSWORD  TEXT
);

CREATE TABLE IF NOT EXISTS user_watched (
    WATCHED_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    WATCHED_DEVICE_ID   TEXT UNIQUE,
    WATCHED_MOBILE_NUM  TEXT,
    WATCHED_MOBILE_TYPE TEXT,
    WATCHED_NAME        TEXT,
    WATCHED_STATUS      TEXT DEFAULT 'ON',
    SOCKET_ID           TEXT,
    USER_TYPE           TEXT,
    WATCHED_ROOM        TEXT,
    BATTERY             TEXT,
    FCM_TOKEN           TEXT,
    ICON                TEXT,
    ACTIVED_AT          TEXT,
    OS_VERSION          TEXT
);

CREATE TABLE IF NOT EXISTS private_rooms (
    ROOM_ID           INTEGER PRIMARY KEY AUTOINCREMENT,
    SENDER_DEVICE_ID  TEXT,
    RECEIVER_DEVICE_ID TEXT,
    CREATED_AT        TEXT
);

CREATE TABLE IF NOT EXISTS messages (
    MESSAGE_ID       INTEGER PRIMARY KEY AUTOINCREMENT,
    ROOM_ID          INTEGER,
    MESSAGE_CONTENT  TEXT,
    DEAD_TIME        TEXT,
    DEAD_TIME_SETTING TEXT,
    SENDER_DEVICE_ID TEXT,
    TYPE_MESSAGE     INTEGER DEFAULT 0,
    CREATED_AT       TEXT,
    REPLY_MESSAGE_ID INTEGER,
    IS_PIN           INTEGER DEFAULT 0,
    PIN_TIME         TEXT
);

CREATE TABLE IF NOT EXISTS call_history (
    CALL_ID        INTEGER PRIMARY KEY AUTOINCREMENT,
    CALL_USER_ID   TEXT,
    CALL_WATCHED_ID TEXT,
    CALL_LENGTH    TEXT,
    CALL_TYPE      TEXT,
    FILE_PATH      TEXT,
    DATE           TEXT
);

CREATE TABLE IF NOT EXISTS area_limited (
    ID              INTEGER PRIMARY KEY AUTOINCREMENT,
    USER_ID         TEXT,
    WATCHED_ID      TEXT,
    FCM_TOKEN       TEXT,
    LAT_LNG_LIST    TEXT,
    DISTANCE_ALERT  TEXT,
    WT_DISPLAY_NAME TEXT,
    IN_AREA         TEXT DEFAULT 'false'
);

CREATE TABLE IF NOT EXISTS path_move_history (
    ID         INTEGER PRIMARY KEY AUTOINCREMENT,
    WATCHED_ID TEXT,
    START_TIME TEXT,
    END_TIME   TEXT,
    DATE       TEXT,
    PATH_MOVE  TEXT
);

CREATE TABLE IF NOT EXISTS upload_info (
    ID       INTEGER PRIMARY KEY AUTOINCREMENT,
    FILENAME TEXT,
    URL      TEXT,
    CREATED_AT TEXT
);
"""

# ── Connection helpers ─────────────────────────────────────────────────────

async def init_db():
    global _db
    _db = await aiosqlite.connect(DB_PATH)
    _db.row_factory = sqlite3.Row
    await _db.executescript(_SCHEMA)
    await _db.commit()
    print("[OK] SQLite database initialised")


async def get_conn():
    return _db


def release_conn(conn):
    pass  # no-op for SQLite single connection


def _row_to_dict(row) -> Optional[dict]:
    if row is None:
        return None
    return dict(row)


async def execute(sql: str, args=None) -> int:
    sql = _adapt(sql)
    cursor = await _db.execute(sql, args or ())
    await _db.commit()
    return cursor.lastrowid


async def fetchone(sql: str, args=None) -> Optional[dict]:
    sql = _adapt(sql)
    cursor = await _db.execute(sql, args or ())
    row = await cursor.fetchone()
    return _row_to_dict(row)


async def fetchall(sql: str, args=None) -> list[dict]:
    sql = _adapt(sql)
    cursor = await _db.execute(sql, args or ())
    rows = await cursor.fetchall()
    return [_row_to_dict(r) for r in rows]
