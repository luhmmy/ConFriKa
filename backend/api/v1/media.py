"""Media uploads: profile pictures and image messages.

Files are stored on disk with an unguessable UUID name and served publicly from
`/media`. For end-to-end-encrypted direct messages the client uploads the image
as a ciphertext blob, so public access is safe (undecryptable without the key).
Avatars and Global Spaces images are uploaded as-is (they're public anyway).
"""
import os
import uuid

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status

from ...config.settings import settings
from ...database.models import User
from .auth import get_current_user

router = APIRouter(prefix="/media", tags=["Media"])

# Allowed image types → file extension (for direct display). Encrypted blobs are
# uploaded as octet-stream and keep a .bin extension.
_IMAGE_EXT = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "image/gif": ".gif",
}


@router.post("/upload")
async def upload_media(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
):
    """Upload an image (or an encrypted image blob). Returns its public path."""
    data = await file.read()
    if len(data) > settings.MEDIA_MAX_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="Image is too large (max 8 MB).",
        )
    if not data:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Empty file.")

    ctype = (file.content_type or "").lower()
    if ctype in _IMAGE_EXT:
        ext = _IMAGE_EXT[ctype]
    elif ctype in ("application/octet-stream", "", None):
        ext = ".bin"  # encrypted blob
    else:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Only JPEG, PNG, WebP or GIF images are allowed.",
        )

    os.makedirs(settings.MEDIA_DIR, exist_ok=True)
    name = f"{uuid.uuid4().hex}{ext}"
    with open(os.path.join(settings.MEDIA_DIR, name), "wb") as f:
        f.write(data)

    return {"media_id": name, "url": f"/media/{name}"}
