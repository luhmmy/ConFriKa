from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from ..config.settings import settings
from .models import Base

engine = create_async_engine(
    settings.DATABASE_URL,
    echo=settings.DEBUG,
    future=True,
)

AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autocommit=False,
    autoflush=False,
)


async def _ensure_column(conn, table: str, column: str, ddl_type: str) -> None:
    """Add a column to an existing Postgres table if it isn't there yet."""
    exists = await conn.scalar(
        text(
            "SELECT 1 FROM information_schema.columns "
            "WHERE table_name = :t AND column_name = :c"
        ),
        {"t": table, "c": column},
    )
    if not exists:
        await conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {column} {ddl_type}"))


async def init_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        # Lightweight migration: add User.email_verified to an existing Postgres
        # table that predates the column, and grandfather current accounts so
        # they are not suddenly locked out by the new verification requirement.
        if engine.dialect.name == "postgresql":
            col = await conn.scalar(
                text(
                    "SELECT 1 FROM information_schema.columns "
                    "WHERE table_name = 'users' AND column_name = 'email_verified'"
                )
            )
            if not col:
                await conn.execute(
                    text(
                        "ALTER TABLE users ADD COLUMN email_verified "
                        "BOOLEAN NOT NULL DEFAULT FALSE"
                    )
                )
                # Existing users registered before email verification are trusted.
                await conn.execute(text("UPDATE users SET email_verified = TRUE"))

            # E2E encryption columns, added to tables that predate them.
            await _ensure_column(conn, "users", "public_key", "TEXT")
            await _ensure_column(
                conn, "direct_messages", "is_encrypted",
                "BOOLEAN NOT NULL DEFAULT FALSE",
            )
            await _ensure_column(conn, "direct_messages", "ciphertext", "TEXT")
            await _ensure_column(conn, "direct_messages", "sender_pub", "TEXT")
            # Privacy / reachability controls.
            await _ensure_column(
                conn, "users", "calls_privacy",
                "VARCHAR(16) NOT NULL DEFAULT 'everyone'",
            )
            await _ensure_column(
                conn, "users", "messages_privacy",
                "VARCHAR(16) NOT NULL DEFAULT 'everyone'",
            )
            await _ensure_column(
                conn, "users", "allow_images",
                "BOOLEAN NOT NULL DEFAULT TRUE",
            )
            # Profile pictures + image/sticker messages.
            await _ensure_column(conn, "users", "avatar_url", "TEXT")
            await _ensure_column(conn, "direct_messages", "media_url", "TEXT")
            await _ensure_column(conn, "global_spaces_messages", "media_url", "TEXT")
            # original_text may now be null (encrypted messages carry no plaintext).
            await conn.execute(
                text("ALTER TABLE direct_messages ALTER COLUMN original_text DROP NOT NULL")
            )


async def get_db():
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()
