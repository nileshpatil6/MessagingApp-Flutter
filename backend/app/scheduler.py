import json
from datetime import datetime
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger

scheduler = AsyncIOScheduler()


def init_scheduler(sio):
    @scheduler.scheduled_job(CronTrigger(minute=0))  # every hour at :00
    async def delete_expired_messages():
        from models.messages import get_expired, remove_by_list
        now = datetime.now()
        expired = await get_expired(now)
        if not expired:
            return
        # Group by room_id
        by_room: dict = {}
        for row in expired:
            rid = str(row["ROOM_ID"])
            by_room.setdefault(rid, []).append(row["MESSAGE_ID"])
        # Delete and notify
        for room_id, ids in by_room.items():
            await remove_by_list(ids)
            for mid in ids:
                await sio.emit("pv_messageDeleted",
                               json.dumps({"room_id": room_id, "message_id": mid}),
                               room=room_id)

    scheduler.start()
    print("[OK] Scheduler started")
