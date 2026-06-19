"""
Deko IPTV — admin backend (FastAPI).

Mounted behind Kong at /admin. Two surfaces:
  * Web UI (session-cookie login) for humans: create/block/modify accounts,
    manage per-account IPTV sources, view devices.
  * JSON API (Bearer ADMIN_API_TOKEN) for scripting the same operations.

Talks directly to Postgres as `supabase_admin` (RLS-bypassing) via asyncpg.
8-char codes are generated in-DB by zeniptv.gen_access_code().
"""
import os
import secrets
from contextlib import asynccontextmanager
from typing import Optional

import asyncpg
from fastapi import (FastAPI, Request, Form, HTTPException, Depends,
                     status, Header, UploadFile, File)
from fastapi.responses import (HTMLResponse, RedirectResponse, JSONResponse,
                               FileResponse)
from fastapi.templating import Jinja2Templates
from itsdangerous import URLSafeSerializer, BadSignature

DATABASE_URL = os.environ["DATABASE_URL"]
ADMIN_API_TOKEN = os.environ["ADMIN_API_TOKEN"]
ADMIN_USERNAME = os.environ.get("ADMIN_USERNAME", "admin")
ADMIN_PASSWORD = os.environ["ADMIN_PASSWORD"]
SESSION_SECRET = os.environ.get("ADMIN_API_TOKEN", "change-me")  # reuse token as cookie secret

signer = URLSafeSerializer(SESSION_SECRET, salt="zeniptv-admin-session")
templates = Jinja2Templates(directory="templates")

pool: Optional[asyncpg.Pool] = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global pool
    pool = await asyncpg.create_pool(DATABASE_URL, min_size=1, max_size=5)
    yield
    await pool.close()


# NOTE: no root_path — routes already carry the /admin prefix and Kong forwards
# the full path (strip_path:false). Setting root_path would double the prefix.
app = FastAPI(title="Deko IPTV Admin", lifespan=lifespan)


# ---------------------------------------------------------------- auth helpers
def make_session() -> str:
    return signer.dumps({"u": ADMIN_USERNAME})


def check_session(request: Request) -> bool:
    tok = request.cookies.get("zadmin")
    if not tok:
        return False
    try:
        signer.loads(tok)
        return True
    except BadSignature:
        return False


def require_web(request: Request):
    if not check_session(request):
        raise HTTPException(status_code=status.HTTP_303_SEE_OTHER,
                            headers={"Location": "/admin/login"})


def require_api(authorization: str = Header(default="")):
    expected = f"Bearer {ADMIN_API_TOKEN}"
    if not secrets.compare_digest(authorization, expected):
        raise HTTPException(status_code=401, detail="invalid admin token")


# ---------------------------------------------------------------- public: APK
# Public, unauthenticated download of the Android app, served at the gateway
# root via a dedicated Kong route. The file is mounted at /app/downloads.
APK_PATH = "/app/downloads/deko-iptv.apk"
DEB_PATH = "/app/downloads/deko-iptv.deb"


@app.get("/deko-iptv.apk")
async def download_apk():
    if not os.path.exists(APK_PATH):
        raise HTTPException(404, "APK not available")
    return FileResponse(
        APK_PATH,
        media_type="application/vnd.android.package-archive",
        filename="deko-iptv.apk",
    )


@app.get("/deko-iptv.deb")
async def download_deb():
    if not os.path.exists(DEB_PATH):
        raise HTTPException(404, "DEB not available")
    return FileResponse(
        DEB_PATH,
        media_type="application/vnd.debian.binary-package",
        filename="deko-iptv.deb",
    )


EXE_PATH = "/app/downloads/deko-iptv-setup.exe"


@app.get("/deko-iptv-setup.exe")
async def download_exe():
    if not os.path.exists(EXE_PATH):
        raise HTTPException(404, "EXE not available")
    return FileResponse(
        EXE_PATH,
        media_type="application/vnd.microsoft.portable-executable",
        filename="deko-iptv-setup.exe",
    )


_ALLOWED_ARTIFACT_EXT = {".apk", ".deb", ".exe"}


@app.post("/admin/api/upload-artifact/{filename}", dependencies=[Depends(require_api)])
async def upload_artifact(filename: str, file: UploadFile = File(...)):
    if any(c in filename for c in ("/", "\\", "..")):
        raise HTTPException(400, "invalid filename")
    ext = os.path.splitext(filename)[1].lower()
    if ext not in _ALLOWED_ARTIFACT_EXT:
        raise HTTPException(400, f"extension not allowed: {ext}")
    path = f"/app/downloads/{filename}"
    content = await file.read()
    with open(path, "wb") as f:
        f.write(content)
    return {"ok": True, "filename": filename, "bytes": len(content)}


# ---------------------------------------------------------------- health
@app.get("/admin/healthz")
async def healthz():
    async with pool.acquire() as c:
        await c.fetchval("select 1")
    return {"ok": True}


# ---------------------------------------------------------------- web: login
@app.get("/admin/login", response_class=HTMLResponse)
async def login_form(request: Request, error: str = ""):
    return templates.TemplateResponse("login.html", {"request": request, "error": error})


@app.post("/admin/login")
async def login_submit(username: str = Form(...), password: str = Form(...)):
    ok = (secrets.compare_digest(username, ADMIN_USERNAME)
          and secrets.compare_digest(password, ADMIN_PASSWORD))
    if not ok:
        return RedirectResponse("/admin/login?error=Invalid+credentials", status_code=303)
    resp = RedirectResponse("/admin/", status_code=303)
    resp.set_cookie("zadmin", make_session(), httponly=True, samesite="lax", max_age=86400)
    return resp


@app.get("/admin/logout")
async def logout():
    resp = RedirectResponse("/admin/login", status_code=303)
    resp.delete_cookie("zadmin")
    return resp


# ---------------------------------------------------------------- web: dashboard
@app.get("/admin/", response_class=HTMLResponse)
async def dashboard(request: Request):
    if not check_session(request):
        return RedirectResponse("/admin/login", status_code=303)
    async with pool.acquire() as c:
        accounts = await c.fetch("""
            select a.*,
                   (select count(*) from zeniptv.devices d where d.account_id=a.id) as device_count,
                   (select count(*) from zeniptv.iptv_sources s where s.account_id=a.id) as source_count
            from zeniptv.accounts a order by a.created_at desc
        """)
    return templates.TemplateResponse("dashboard.html",
                                      {"request": request, "accounts": accounts})


@app.get("/admin/account/{account_id}", response_class=HTMLResponse)
async def account_detail(request: Request, account_id: str):
    if not check_session(request):
        return RedirectResponse("/admin/login", status_code=303)
    async with pool.acquire() as c:
        acct = await c.fetchrow("select * from zeniptv.accounts where id=$1", account_id)
        if not acct:
            raise HTTPException(404, "account not found")
        sources = await c.fetch("select * from zeniptv.iptv_sources where account_id=$1 order by created_at", account_id)
        devices = await c.fetch("select * from zeniptv.devices where account_id=$1 order by last_seen_at desc", account_id)
    return templates.TemplateResponse("account.html",
                                      {"request": request, "a": acct,
                                       "sources": sources, "devices": devices})


# ---------------------------------------------------------------- web: mutations
@app.post("/admin/account/create")
async def web_create(request: Request, label: str = Form(""),
                     max_devices: int = Form(1), expires_at: str = Form("")):
    require_web(request)
    async with pool.acquire() as c:
        row = await c.fetchrow(
            "insert into zeniptv.accounts(label, max_devices, expires_at) "
            "values ($1,$2, nullif($3,'')::timestamptz) returning id, access_code",
            label or None, max_devices, expires_at)
    return RedirectResponse(f"/admin/account/{row['id']}", status_code=303)


@app.post("/admin/account/{account_id}/status")
async def web_status(request: Request, account_id: str, status_val: str = Form(...)):
    require_web(request)
    async with pool.acquire() as c:
        await c.execute("update zeniptv.accounts set status=$1 where id=$2", status_val, account_id)
    return RedirectResponse(f"/admin/account/{account_id}", status_code=303)


@app.post("/admin/account/{account_id}/update")
async def web_update(request: Request, account_id: str,
                     label: str = Form(""), max_devices: int = Form(1),
                     expires_at: str = Form("")):
    require_web(request)
    async with pool.acquire() as c:
        await c.execute(
            "update zeniptv.accounts set label=$1, max_devices=$2, "
            "expires_at=nullif($3,'')::timestamptz where id=$4",
            label or None, max_devices, expires_at, account_id)
    return RedirectResponse(f"/admin/account/{account_id}", status_code=303)


@app.post("/admin/account/{account_id}/source")
async def web_add_source(request: Request, account_id: str,
                         kind: str = Form(...), name: str = Form("My Playlist"),
                         server_url: str = Form(""), username: str = Form(""),
                         password: str = Form(""), m3u_url: str = Form("")):
    require_web(request)
    async with pool.acquire() as c:
        await c.execute(
            "insert into zeniptv.iptv_sources(account_id,kind,name,server_url,username,password,m3u_url) "
            "values ($1,$2,$3,nullif($4,''),nullif($5,''),nullif($6,''),nullif($7,''))",
            account_id, kind, name, server_url, username, password, m3u_url)
    return RedirectResponse(f"/admin/account/{account_id}", status_code=303)


@app.post("/admin/source/{source_id}/delete")
async def web_del_source(request: Request, source_id: str, account_id: str = Form(...)):
    require_web(request)
    async with pool.acquire() as c:
        await c.execute("delete from zeniptv.iptv_sources where id=$1", source_id)
    return RedirectResponse(f"/admin/account/{account_id}", status_code=303)


@app.post("/admin/device/{device_id}/delete")
async def web_del_device(request: Request, device_id: str, account_id: str = Form(...)):
    require_web(request)
    async with pool.acquire() as c:
        await c.execute("delete from zeniptv.devices where id=$1", device_id)
    return RedirectResponse(f"/admin/account/{account_id}", status_code=303)


# ---------------------------------------------------------------- JSON API
@app.get("/admin/api/accounts", dependencies=[Depends(require_api)])
async def api_list():
    async with pool.acquire() as c:
        rows = await c.fetch("select * from zeniptv.accounts order by created_at desc")
    return [dict(r) for r in rows]


@app.post("/admin/api/accounts", dependencies=[Depends(require_api)])
async def api_create(payload: dict):
    async with pool.acquire() as c:
        row = await c.fetchrow(
            "insert into zeniptv.accounts(label,max_devices,expires_at) "
            "values ($1,$2,$3) returning *",
            payload.get("label"), int(payload.get("max_devices", 1)),
            payload.get("expires_at"))
    return dict(row)


@app.patch("/admin/api/accounts/{account_id}", dependencies=[Depends(require_api)])
async def api_update(account_id: str, payload: dict):
    fields, vals = [], []
    for i, k in enumerate([k for k in ("label", "status", "max_devices", "expires_at")
                           if k in payload], start=1):
        fields.append(f"{k}=${i}")
        vals.append(payload[k])
    if not fields:
        raise HTTPException(400, "no updatable fields")
    vals.append(account_id)
    async with pool.acquire() as c:
        row = await c.fetchrow(
            f"update zeniptv.accounts set {','.join(fields)} where id=${len(vals)} returning *", *vals)
    if not row:
        raise HTTPException(404, "not found")
    return dict(row)


@app.post("/admin/api/accounts/{account_id}/sources", dependencies=[Depends(require_api)])
async def api_add_source(account_id: str, payload: dict):
    async with pool.acquire() as c:
        row = await c.fetchrow(
            "insert into zeniptv.iptv_sources(account_id,kind,name,server_url,username,password,m3u_url) "
            "values ($1,$2,$3,$4,$5,$6,$7) returning *",
            account_id, payload["kind"], payload.get("name", "My Playlist"),
            payload.get("server_url"), payload.get("username"),
            payload.get("password"), payload.get("m3u_url"))
    return dict(row)
