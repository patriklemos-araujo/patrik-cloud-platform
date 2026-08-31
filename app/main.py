from fastapi import HTTPException
from fastapi.responses import RedirectResponse
import secrets
from pydantic import BaseModel
import os
import psycopg
from dotenv import load_dotenv
from fastapi import FastAPI

load_dotenv()

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": os.getenv("DB_PORT", "5432"),
    "dbname": os.getenv("DB_NAME", "appdb"),
    "user": os.getenv("DB_USER", "patrik"),
    "password": os.getenv("DB_PASSWORD", ""),
}

CREATE_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS links (
    code VARCHAR(10) PRIMARY KEY,
    url TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
"""


def get_connection():
    return psycopg.connect(**DB_CONFIG)


def init_db():
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(CREATE_TABLE_SQL)
        conn.commit()


app = FastAPI()


@app.on_event("startup")
def on_startup():
    init_db()


@app.get("/")
def read_root():
    return {"message": "Hello from patrik-cloud-platform"}


@app.get("/healthz")
def health_check():
    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
    except Exception:
        raise HTTPException(status_code=503, detail="database unavailable")
    return {"status": "ok"}




class LinkRequest(BaseModel):
    url: str


@app.post("/links")
def create_link(payload: LinkRequest):
    code = secrets.token_urlsafe(6)[:8]
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO links (code, url) VALUES (%s, %s)",
                (code, payload.url),
            )
        conn.commit()
    return {"code": code, "url": payload.url}

@app.get("/{code}")
def redirect_link(code: str):
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT url FROM links WHERE code = %s", (code,))
            row = cur.fetchone()

    if row is None:
        raise HTTPException(status_code=404, detail="Link not found")

    return RedirectResponse(url=row[0], status_code=307)

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": os.getenv("DB_PORT", "5432"),
    "dbname": os.getenv("DB_NAME", "appdb"),
    "user": os.getenv("DB_USER", "patrik"),
    "password": os.getenv("DB_PASSWORD", ""),
    "connect_timeout": 3,
}