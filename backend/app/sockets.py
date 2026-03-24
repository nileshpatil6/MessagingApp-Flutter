from typing import Optional
import socketio
import json
from datetime import datetime

import models.messages as msg_model
import models.private_room as room_model
import models.user_watched as user_model
import models.path_move_history as path_model

sio = socketio.AsyncServer(
    async_mode="asgi",
    cors_allowed_origins="*",
    logger=False,
    engineio_logger=False,
)

# In-memory connected users: device_id -> {device_id, name, socket_id, connected}
users: dict[str, dict] = {}


def _connected_users() -> list:
    return [u for u in users.values() if u.get("connected")]


def _find_socket(device_id: str) -> Optional[str]:
    u = users.get(device_id)
    if u and u.get("connected"):
        return u.get("socket_id")
    return None


async def _deliver_to_device(device_id: str, event: str, data):
    sid = _find_socket(device_id)
    if sid:
        await sio.emit(event, data, to=sid)


async def _deliver_to_all_except(exclude_device_id: str, event: str, data):
    for dev_id, u in users.items():
        if dev_id != exclude_device_id and u.get("connected") and u.get("socket_id"):
            await sio.emit(event, data, to=u["socket_id"])


# ──────────────────────────────────────────────
# CONNECTION
# ──────────────────────────────────────────────

@sio.event
async def connect(sid, environ):
    await sio.emit("id", sid, to=sid)
    # Heartbeat
    async def _ping():
        while True:
            await sio.sleep(10)
            try:
                await sio.emit("ping", {}, to=sid)
            except Exception:
                break
    sio.start_background_task(_ping)


@sio.event
async def disconnect(sid):
    for dev_id, u in list(users.items()):
        if u.get("socket_id") == sid:
            u["connected"] = False
            await sio.emit("pv_listUser", json.dumps(_connected_users()))
            break


@sio.on("leave")
async def on_leave(sid, data):
    await disconnect(sid)


# ──────────────────────────────────────────────
# USER MANAGEMENT
# ──────────────────────────────────────────────

@sio.on("pv_access")
async def on_pv_access(sid, data):
    if isinstance(data, str):
        data = json.loads(data)
    device_id = data.get("device_id")
    name = data.get("name", "")
    if not device_id:
        return
    # Check duplicate name
    for dev_id, u in users.items():
        if u.get("name") == name and dev_id != device_id and u.get("connected"):
            await sio.emit("pv_error_duplicate_name", {}, to=sid)
            return
    users[device_id] = {
        "device_id": device_id,
        "name": name,
        "socket_id": sid,
        "connected": True,
    }
    await user_model.insert_or_update({
        "watched_device_id": device_id,
        "watched_name": name,
        "watched_mobile_type": data.get("device_type", ""),
        "socket_id": sid,
        "user_type": data.get("user_type", ""),
        "fcm_token": data.get("fcm_token"),
        "os_version": data.get("os_version"),
    })
    await sio.emit("pv_listUser", json.dumps(_connected_users()))


@sio.on("pv_getUserList")
async def on_get_user_list(sid, data=None):
    await sio.emit("pv_listUser", json.dumps(_connected_users()), to=sid)


@sio.on("pv_updateUserName")
async def on_update_user_name(sid, data):
    if isinstance(data, str):
        data = json.loads(data)
    device_id = data.get("device_id")
    new_name = data.get("name", "")
    # Duplicate check
    for dev_id, u in users.items():
        if u.get("name") == new_name and dev_id != device_id and u.get("connected"):
            await sio.emit("pv_updateUserNameStatus", {"status": False}, to=sid)
            return
    if device_id in users:
        users[device_id]["name"] = new_name
    await sio.emit("pv_updateUserNameStatus", {"status": True}, to=sid)
    await sio.emit("pv_listUser", json.dumps(_connected_users()))


@sio.on("pv_pong")
async def on_pong(sid, data=None):
    pass  # Heartbeat response


# ──────────────────────────────────────────────
# PRIVATE MESSAGING
# ──────────────────────────────────────────────

@sio.on("pv_joinRoom")
async def on_join_room(sid, data):
    if isinstance(data, str):
        data = json.loads(data)
    current = data.get("current_user", {})
    partner = data.get("partner", {})
    current_id = current.get("device_id")
    partner_id = partner.get("device_id")
    if not current_id or not partner_id:
        return
    room = await room_model.get_or_create(current_id, partner_id)
    room_id = room["room_id"]
    await sio.enter_room(sid, str(room_id))
    await sio.emit("pv_roomId", str(room_id), to=sid)
    # Notify partner to auto-join
    partner_sid = _find_socket(partner_id)
    if partner_sid:
        await sio.emit("pv_autoJoinRoom", str(room_id), to=partner_sid)
    # Send message history + pin list
    history = await msg_model.get_by_room(room_id)
    await sio.emit("pv_listMessage", json.dumps(history), to=sid)
    pins = await msg_model.get_pin_list(room_id)
    await sio.emit("pv_messagePinList", json.dumps(pins), to=sid)


@sio.on("pv_autoJoinRoomClient")
async def on_auto_join_room_client(sid, room_id):
    await sio.enter_room(sid, str(room_id))


@sio.on("pv_sendMessage")
async def on_send_message(sid, data):
    if isinstance(data, str):
        data = json.loads(data)
    message = data.get("message", data)
    room_id = message.get("room_id")
    receiver_device_id = message.get("receiver_device_id")

    # Determine if group message (room_id is non-numeric string)
    is_group = room_id and not str(room_id).lstrip("-").isdigit()

    if is_group:
        # Group: no DB storage, direct delivery
        result = {
            "message_id": None,
            "room_id": room_id,
            "message_content": message.get("message_content"),
            "dead_time": message.get("dead_time"),
            "sender_device_id": message.get("sender_device_id"),
            "type_message": message.get("type_message", 0),
            "created_at": message.get("created_at") or str(datetime.now()),
            "reply_message_id": message.get("reply_message_id"),
            "is_pin": 0,
        }
        if receiver_device_id:
            await _deliver_to_device(receiver_device_id, "pv_messageSended", json.dumps(result))
        await sio.emit("pv_messageSended", json.dumps(result), to=sid)
    else:
        # Private: store in DB + dual delivery
        try:
            saved = await msg_model.insert(message)
            if not saved:
                print(f"[ERROR] msg_model.insert returned None for room={room_id}", flush=True)
                return
            result = dict(saved)
        except Exception as exc:
            print(f"[ERROR] msg_model.insert failed: {exc}", flush=True)
            return
        # Echo _tempId back so the sender client can replace its optimistic bubble
        if message.get("_tempId"):
            result["_tempId"] = message["_tempId"]
        payload = json.dumps(result)
        await sio.emit("pv_messageSended", payload, room=str(room_id))
        if receiver_device_id:
            await _deliver_to_device(receiver_device_id, "pv_messageSended", payload)


@sio.on("pv_messageRead")
async def on_message_read(sid, data):
    if isinstance(data, str):
        data = json.loads(data)
    room_id = data.get("room_id")
    sender_device_id = data.get("sender_device_id")
    payload = json.dumps(data)
    if room_id:
        await sio.emit("pv_messageRead", payload, room=str(room_id))
    if sender_device_id:
        await _deliver_to_device(sender_device_id, "pv_messageRead", payload)


@sio.on("pv_messageDelivered")
async def on_message_delivered(sid, data):
    if isinstance(data, str):
        data = json.loads(data)
    room_id = data.get("room_id")
    sender_device_id = data.get("sender_device_id")
    payload = json.dumps(data)
    if room_id:
        await sio.emit("pv_messageDelivered", payload, room=str(room_id))
    if sender_device_id:
        await _deliver_to_device(sender_device_id, "pv_messageDelivered", payload)


# ──────────────────────────────────────────────
# MESSAGE DELETION
# ──────────────────────────────────────────────

@sio.on("pv_deleteMessage")
async def on_delete_message(sid, data):
    if isinstance(data, str):
        data = json.loads(data)
    message_id = data.get("message_id")
    is_pin = data.get("is_pin", 0)
    room_id = data.get("room_id")
    success = await msg_model.remove_by_list([message_id])
    if success:
        if is_pin and room_id:
            pins = await msg_model.get_pin_list(room_id)
            await sio.emit("pv_messagePinList", json.dumps(pins), room=str(room_id))
        payload = json.dumps({"room_id": room_id, "message_id": message_id})
        if room_id:
            await sio.emit("pv_messageDeleted", payload, room=str(room_id))


@sio.on("pv_deleteMessages")
async def on_delete_messages(sid, data):
    if isinstance(data, str):
        data = json.loads(data)
    room_id = data.get("room_id")
    message_ids = data.get("message_ids", [])
    sender_device_id = data.get("sender_device_id")
    if not message_ids:
        return
    success = await msg_model.remove_by_list(message_ids)
    if success:
        payload = json.dumps({"room_id": room_id, "message_ids": message_ids})
        if room_id:
            await sio.emit("pv_messagesDeleted", payload, room=str(room_id))
        if sender_device_id:
            await _deliver_to_all_except(sender_device_id, "pv_messagesDeleted", payload)


# ──────────────────────────────────────────────
# MESSAGE OPERATIONS
# ──────────────────────────────────────────────

@sio.on("pv_forwardMessage")
async def on_forward_message(sid, data):
    if isinstance(data, str):
        data = json.loads(data)
    sender_id = data.get("sender_device_id")
    receiver_id = data.get("receiver_device_id")
    room = await room_model.get_or_create(sender_id, receiver_id)
    forwarded = await msg_model.forward_message({
        "message_id": data.get("message_id"),
        "room_id": room["room_id"],
        "sender_device_id": sender_id,
        "created_at": datetime.now(),
    })
    payload = json.dumps(forwarded)
    await sio.emit("pv_messageSended", payload, room=str(room["room_id"]))
    await _deliver_to_device(receiver_id, "pv_messageSended", payload)


@sio.on("pv_pinMessage")
async def on_pin_message(sid, data):
    if isinstance(data, str):
        data = json.loads(data)
    room_id = data.get("room_id")
    message_id = data.get("message_id")
    is_pin = data.get("is_pin", 0)
    pin_time = data.get("pin_time")
    pins = await msg_model.pin_message(room_id, message_id, is_pin, pin_time)
    await sio.emit("pv_messagePinList", json.dumps(pins), room=str(room_id))


# ──────────────────────────────────────────────
# BATTERY & STATUS
# ──────────────────────────────────────────────

@sio.on("batteryChange")
async def on_battery_change(sid, data):
    if isinstance(data, str):
        data = json.loads(data)
    device_id = data.get("deviceId")
    battery = data.get("battery")
    if device_id:
        await user_model.update_battery(device_id, battery)
        payload = json.dumps({"battery": battery, "deviceId": device_id})
        await _deliver_to_all_except(device_id, "sendUserBattery", payload)


# ──────────────────────────────────────────────
# LOCATION TRACKING
# ──────────────────────────────────────────────

@sio.on("startRequestLocation")
async def on_start_request_location(sid, wt_socket_id):
    await sio.emit("startRequestLocation", {}, to=wt_socket_id)


@sio.on("sendRequestLocation")
async def on_send_request_location(sid, data):
    if isinstance(data, str):
        data = json.loads(data)
    fl_socket_id = data.get("flSocketId")
    if fl_socket_id:
        await sio.emit("sendRequestLocation", json.dumps(data), to=fl_socket_id)


@sio.on("stopRequestLocation")
async def on_stop_request_location(sid, wt_socket_id):
    await sio.emit("stopRequestLocation", {}, to=wt_socket_id)


@sio.on("finishJobLocation")
async def on_finish_job_location(sid, data):
    if isinstance(data, str):
        data = json.loads(data)
    await path_model.insert({
        "watched_id": data.get("watchedId"),
        "path_move": json.dumps(data.get("pathMove", [])),
        "date": datetime.now().strftime("%Y-%m-%d"),
        "start_time": data.get("startTime", ""),
        "end_time": data.get("endTime", ""),
    })


# ──────────────────────────────────────────────
# WEBRTC SIGNALING
# ──────────────────────────────────────────────

webrtc_rooms: dict[str, list] = {}  # room_id -> [sid1, sid2]


@sio.on("create or join")
async def on_create_or_join(sid, data):
    if isinstance(data, str):
        data = json.loads(data)
    room_id = data.get("watchedRoom") or data.get("room_id")
    if not room_id:
        return
    clients = webrtc_rooms.get(room_id, [])
    if len(clients) == 0:
        webrtc_rooms[room_id] = [sid]
        await sio.emit("created", room_id, to=sid)
    elif len(clients) == 1:
        webrtc_rooms[room_id].append(sid)
        await sio.emit("join", room_id, to=clients[0])
        await sio.emit("joined", room_id, to=sid)
        await sio.emit("ready", clients[0], to=sid)
        await sio.emit("ready", sid, to=clients[0])
    else:
        await sio.emit("full", room_id, to=sid)


@sio.on("message")
async def on_webrtc_message(sid, data):
    # Relay SDP/ICE to the other peer in the room
    for room_id, clients in webrtc_rooms.items():
        if sid in clients:
            for other in clients:
                if other != sid:
                    await sio.emit("message", data, to=other)
            break


@sio.on("bye")
async def on_bye(sid, data=None):
    for room_id, clients in list(webrtc_rooms.items()):
        if sid in clients:
            for other in clients:
                if other != sid:
                    await sio.emit("bye", sid, to=other)
            webrtc_rooms.pop(room_id, None)
            break


@sio.on("switchCamera")
async def on_switch_camera(sid, data):
    for room_id, clients in webrtc_rooms.items():
        if sid in clients:
            for other in clients:
                if other != sid:
                    await sio.emit("switchCamera", {}, to=other)
            break


# ──────────────────────────────────────────────
# CONTACT / CALL LOG RELAY
# ──────────────────────────────────────────────

@sio.on("triggerGetContact")
async def on_trigger_get_contact(sid, data):
    if isinstance(data, str):
        data = json.loads(data)
    await sio.emit("triggerGetContact", json.dumps(data), to=data.get("wtSocketId"))


@sio.on("getContact")
async def on_get_contact(sid, data):
    if isinstance(data, str):
        data = json.loads(data)
    await sio.emit("getContact", json.dumps(data), to=data.get("flSocketId"))


@sio.on("triggerGetCallLog")
async def on_trigger_call_log(sid, data):
    if isinstance(data, str):
        data = json.loads(data)
    await sio.emit("triggerGetCallLog", json.dumps(data), to=data.get("wtSocketId"))


@sio.on("getCallLog")
async def on_get_call_log(sid, data):
    if isinstance(data, str):
        data = json.loads(data)
    await sio.emit("getCallLog", json.dumps(data), to=data.get("flSocketId"))


# ──────────────────────────────────────────────
# FILE MANAGEMENT RELAY
# ──────────────────────────────────────────────

@sio.on("getListFile")
async def on_get_list_file(sid, data):
    if isinstance(data, str):
        data = json.loads(data)
    await sio.emit("getListFile", json.dumps(data), to=data.get("wtSocketId"))


@sio.on("getListFileSuccess")
async def on_get_list_file_success(sid, data):
    if isinstance(data, str):
        data = json.loads(data)
    await sio.emit("getListFileSuccess", json.dumps(data), to=data.get("flSocketId"))


@sio.on("selectFileUpload")
async def on_select_file_upload(sid, data):
    if isinstance(data, str):
        data = json.loads(data)
    await sio.emit("selectFileUpload", json.dumps(data), to=data.get("wtSocketId"))


@sio.on("uploadFile")
async def on_upload_file(sid, data):
    if isinstance(data, str):
        data = json.loads(data)
    await sio.emit("uploadFile", json.dumps(data), to=data.get("flSocketId"))


@sio.on("selectDeleteFiles")
async def on_select_delete_files(sid, data):
    if isinstance(data, str):
        data = json.loads(data)
    await sio.emit("selectDeleteFiles", json.dumps(data), to=data.get("wtSocketId"))


@sio.on("selectDeleteFilesSuccess")
async def on_select_delete_files_success(sid, data):
    if isinstance(data, str):
        data = json.loads(data)
    await sio.emit("selectDeleteFilesSuccess", json.dumps(data), to=data.get("flSocketId"))
