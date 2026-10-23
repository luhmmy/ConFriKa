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


async def get_db():
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()
