import json
from typing import Dict, Set

from fastapi import APIRouter, Query, WebSocket, WebSocketDisconnect

from ...services import presence
from ...services.auth_service import AuthService

ws_chat_router = APIRouter()


class ChatConnectionManager:
    def __init__(self) -> None:
        # Maps username -> set of active WebSockets (supports multiple devices).
        self.active_connections: Dict[str, Set[WebSocket]] = {}

    @property
    def online_users_count(self) -> int:
        return presence.online_count()

    async def connect(self, websocket: WebSocket, username: str) -> None:
        await websocket.accept()
        self.active_connections.setdefault(username, set()).add(websocket)
        presence.mark_online(username)
        await self.broadcast_presence()

    def disconnect(self, websocket: WebSocket, username: str) -> None:
        if username in self.active_connections:
            self.active_connections[username].discard(websocket)
            if not self.active_connections[username]:
                del self.active_connections[username]
        presence.mark_offline(username)

    async def send_personal_message(self, message: dict, username: str) -> None:
        payload = json.dumps(message)
        for ws in list(self.active_connections.get(username, set())):
            try:
                await ws.send_text(payload)
            except Exception:
                pass

    async def broadcast(self, message: dict) -> None:
        payload = json.dumps(message)
        for sockets in self.active_connections.values():
            for ws in list(sockets):
                try:
                    await ws.send_text(payload)
                except Exception:
                    pass

    async def broadcast_presence(self) -> None:
        count = self.online_users_count
        await self.broadcast(
            {"type": "presence_update", "online_count": count, "label": f"● {count} Online"}
        )


chat_manager = ChatConnectionManager()


@ws_chat_router.websocket("/ws/chat")
async def websocket_chat_endpoint(
    websocket: WebSocket,
    token: str = Query(..., description="JWT access token"),
):
    try:
        payload = AuthService.decode_access_token(token)
        username = payload.get("username")
        if not username:
            raise ValueError("missing username claim")
    except Exception:
        await websocket.close(code=4001, reason="Unauthorized")
        return

    await chat_manager.connect(websocket, username)
    try:
        while True:
            raw_data = await websocket.receive_text()
            try:
                data = json.loads(raw_data)
            except (ValueError, TypeError):
                continue
            msg_type = data.get("type", "message")

            if msg_type == "direct_message":
                target_user = data.get("recipient")
                out_msg = {
                    "type": "direct_message",
                    "sender": username,
                    "text": data.get("text"),
                    "translated_text": data.get("translated_text"),
                    "dialect": data.get("dialect"),
                    "mode": data.get("mode", "translated"),
                }
                if target_user:
                    await chat_manager.send_personal_message(out_msg, target_user)
                await websocket.send_text(json.dumps(out_msg))
            elif msg_type == "spaces_message":
                await chat_manager.broadcast(
                    {
                        "type": "spaces_message",
                        "sender": username,
                        "channel": data.get("channel", "all"),
                        "text": data.get("text"),
                        "translated_text": data.get("translated_text"),
                        "dialect": data.get("dialect"),
                    }
                )
            elif msg_type == "typing":
                target_user = data.get("recipient")
                if target_user:
                    await chat_manager.send_personal_message(
                        {"type": "typing", "sender": username}, target_user
                    )
            elif msg_type == "ping":
                await websocket.send_text(json.dumps({"type": "pong"}))
    except WebSocketDisconnect:
        chat_manager.disconnect(websocket, username)
        await chat_manager.broadcast_presence()
    except Exception:
        chat_manager.disconnect(websocket, username)
        await chat_manager.broadcast_presence()
