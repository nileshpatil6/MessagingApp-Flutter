import asyncio
import sys
print("step 1: importing", flush=True)
from app.database import init_db, fetchall
print("step 2: imported", flush=True)

async def main():
    print("step 3: calling init_db", flush=True)
    await init_db()
    print("step 4: init done", flush=True)
    rows = await fetchall("SELECT name FROM sqlite_master WHERE type='table'")
    print("Tables:", [r['name'] for r in rows], flush=True)

asyncio.run(main())
print("done", flush=True)
