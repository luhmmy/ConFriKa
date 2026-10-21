import json
from typing import Dict
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from ...services.auth_service import AuthService

ws_call_router = APIRouter()


class CallSignalingManager:
    def __init__(self):
        self.peer_sockets: Dict[str, WebSocket] = {}

    async def register(self, username: str, websocket: WebSocket):
        await websocket.accept()
        self.peer_sockets[username] = websocket

    def unregister(self, username: str):
        self.peer_sockets.pop(username, None)

    async def relay_signal(self, target_username: str, signal_payload: dict):
        sock = self.peer_sockets.get(target_username)
        if sock:
            await sock.send_text(json.dumps(signal_payload))


call_manager = CallSignalingManager()


@ws_call_router.websocket("/ws/calls")
async def websocket_call_signaling_endpoint(
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

    await call_manager.register(username, websocket)
    try:
        while True:
            raw_data = await websocket.receive_text()
            data = json.loads(raw_data)
            target = data.get("target")
            signal_type = data.get("signal_type")  # offer, answer, ice-candidate, hangup

            if target and signal_type:
                forward_data = {
                    "signal_type": signal_type,
                    "sender": username,
                    "payload": data.get("payload", {}),
                }
                await call_manager.relay_signal(target, forward_data)
    except WebSocketDisconnect:
        call_manager.unregister(username)
    except Exception:
        call_manager.unregister(username)
