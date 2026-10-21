from fastapi import APIRouter
from .chat_ws import ws_chat_router
from .call_ws import ws_call_router

ws_router = APIRouter()
ws_router.include_router(ws_chat_router)
ws_router.include_router(ws_call_router)

__all__ = ["ws_router"]
