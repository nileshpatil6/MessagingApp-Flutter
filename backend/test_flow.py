"""
End-to-end test: two clients exchange a message and verify status updates.
"""
import asyncio
import socketio

SERVER = "http://localhost:3000"

results = {}

async def run():
    sio1 = socketio.AsyncClient()  # sender
    sio2 = socketio.AsyncClient()  # receiver

    delivered_event = asyncio.Event()
    read_event = asyncio.Event()
    msg_sent_event = asyncio.Event()
    msg_recv_event = asyncio.Event()

    # ── Sender callbacks ──────────────────────────────────────────────────────
    @sio1.on("pv_messageSended")
    async def on_sent(data):
        import json
        d = json.loads(data) if isinstance(data, str) else data
        results["sent_msg"] = d
        print(f"[sender] pv_messageSended: id={d.get('message_id')} tempId={d.get('_tempId')}")
        msg_sent_event.set()

    @sio1.on("pv_messageDelivered")
    async def on_delivered(data):
        import json
        d = json.loads(data) if isinstance(data, str) else data
        results["delivered"] = d
        print(f"[sender] pv_messageDelivered: msg_id={d.get('message_id')}")
        delivered_event.set()

    @sio1.on("pv_messageRead")
    async def on_read(data):
        import json
        d = json.loads(data) if isinstance(data, str) else data
        results["read"] = d
        print(f"[sender] pv_messageRead: msg_id={d.get('message_id')}")
        read_event.set()

    # ── Receiver callbacks ────────────────────────────────────────────────────
    @sio2.on("pv_messageSended")
    async def on_recv(data):
        import json
        d = json.loads(data) if isinstance(data, str) else data
        msg_id = d.get("message_id")
        print(f"[receiver] got message id={msg_id}, sending delivered+read")
        # Simulate receiver acking delivered + read
        await sio2.emit("pv_messageDelivered", {
            "message_id": msg_id,
            "room_id": d.get("room_id"),
            "sender_device_id": "device_A",
        })
        await sio2.emit("pv_messageRead", {
            "message_id": msg_id,
            "room_id": d.get("room_id"),
            "sender_device_id": "device_A",
        })
        msg_recv_event.set()

    room_id_event = asyncio.Event()

    @sio1.on("pv_roomId")
    async def on_room_id(data):
        results["room_id"] = str(data)
        print(f"[sender] room_id={data}")
        room_id_event.set()

    @sio2.on("pv_autoJoinRoom")
    async def on_auto_join(data):
        print(f"[receiver] auto-joining room {data}")
        await sio2.emit("pv_autoJoinRoomClient", str(data))

    # ── Connect ───────────────────────────────────────────────────────────────
    await sio1.connect(SERVER, transports=["websocket"])
    await sio2.connect(SERVER, transports=["websocket"])

    # Register users
    await sio1.emit("pv_access", {"device_id": "device_A", "name": "Alice"})
    await sio2.emit("pv_access", {"device_id": "device_B", "name": "Bob"})
    await asyncio.sleep(0.3)

    # Join room
    await sio1.emit("pv_joinRoom", {
        "current_user": {"device_id": "device_A"},
        "partner": {"device_id": "device_B"},
    })
    await asyncio.wait_for(room_id_event.wait(), timeout=5)

    # Send message with _tempId
    await sio1.emit("pv_sendMessage", {
        "room_id": results["room_id"],
        "message_content": "Hello test!",
        "type_message": 0,
        "sender_device_id": "device_A",
        "receiver_device_id": "device_B",
        "_tempId": "sending_999",
    })

    # Wait for all events
    await asyncio.wait_for(msg_sent_event.wait(), timeout=5)
    await asyncio.wait_for(msg_recv_event.wait(), timeout=5)
    await asyncio.wait_for(delivered_event.wait(), timeout=5)
    await asyncio.wait_for(read_event.wait(), timeout=5)

    await sio1.disconnect()
    await sio2.disconnect()

    # ── Results ───────────────────────────────────────────────────────────────
    print("\n=== TEST RESULTS ===")
    sent = results.get("sent_msg", {})
    print(f"1. Message sent & echoed:   {'PASS' if sent.get('message_id') else 'FAIL'}")
    print(f"2. _tempId preserved:       {'PASS' if sent.get('_tempId') == 'sending_999' else 'FAIL'}")
    print(f"3. Delivered event fired:   {'PASS' if results.get('delivered') else 'FAIL'}")
    print(f"4. Read event fired:        {'PASS' if results.get('read') else 'FAIL'}")
    print(f"5. Status message_id match: {'PASS' if results.get('read', {}).get('message_id') == str(sent.get('message_id')) else 'FAIL'}")
    print("====================")

asyncio.run(run())
