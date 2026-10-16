"""GateX personal cabinet: Telegram Mini App backend.

Serves the static cabinet from ../web and two JSON endpoints, both checked
with Telegram initData:
  POST /api/me              subscription and devices from the Remnawave API
  POST /api/devices/delete  unlinks one of the user's own HWID devices
That unlink is the only write to the panel.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import logging
import os
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from urllib.parse import parse_qsl

from aiohttp import ClientSession, ClientTimeout, web

log = logging.getLogger("gatex-cabinet")

WEB_DIR = Path(__file__).resolve().parent.parent / "web"
INIT_DATA_MAX_AGE = 24 * 3600
CACHE_TTL = 30


@dataclass
class Config:
    bot_token: str
    rw_api_base: str
    rw_api_token: str
    bot_username: str = "gatexvpn_bot"
    support_url: str = ""
    channel_url: str = ""
    buy_url: str = ""
    referral_url: str = ""
    price_from: str = ""
    sub_url_template: str = ""
    mirror_url_template: str = ""
    trial_tag: str = ""
    web_dir: Path = field(default=WEB_DIR)

    @classmethod
    def from_env(cls) -> "Config":
        def get(name: str, default: str = "") -> str:
            return os.environ.get(name, default).strip()

        bot = get("BOT_USERNAME", "gatexvpn_bot").lstrip("@")
        bot_link = f"https://t.me/{bot}"
        return cls(
            bot_token=get("BOT_TOKEN"),
            rw_api_base=get("RW_API_BASE").rstrip("/"),
            rw_api_token=get("RW_API_TOKEN"),
            bot_username=bot,
            support_url=get("SUPPORT_URL", bot_link),
            channel_url=get("CHANNEL_URL"),
            buy_url=get("BUY_URL", bot_link),
            referral_url=get("REFERRAL_URL", bot_link),
            price_from=get("PRICE_FROM"),
            sub_url_template=get("SUB_URL_TEMPLATE"),
            mirror_url_template=get("MIRROR_URL_TEMPLATE"),
            trial_tag=get("TRIAL_TAG"),
            web_dir=Path(get("WEB_DIR") or WEB_DIR),
        )


# ---------------------------------------------------------------- Telegram

def validate_init_data(init_data: str, bot_token: str,
                       max_age: int = INIT_DATA_MAX_AGE,
                       now: float | None = None) -> dict | None:
    """Return the parsed initData if its hash is valid and fresh, else None.

    https://core.telegram.org/bots/webapps#validating-data-received-via-the-mini-app
    """
    if not init_data or not bot_token:
        return None
    pairs = dict(parse_qsl(init_data, keep_blank_values=True))
    received = pairs.pop("hash", "")
    if not received:
        return None
    check = "\n".join(f"{k}={pairs[k]}" for k in sorted(pairs))
    secret = hmac.new(b"WebAppData", bot_token.encode(), hashlib.sha256).digest()
    expected = hmac.new(secret, check.encode(), hashlib.sha256).hexdigest()
    if not hmac.compare_digest(expected, received):
        return None
    try:
        auth_date = int(pairs.get("auth_date", "0"))
    except ValueError:
        return None
    if (now or time.time()) - auth_date > max_age:
        return None
    try:
        pairs["user"] = json.loads(pairs.get("user", "{}"))
    except json.JSONDecodeError:
        return None
    if not isinstance(pairs["user"], dict) or not pairs["user"].get("id"):
        return None
    return pairs


# ---------------------------------------------------------------- Remnawave

class Remnawave:
    def __init__(self, cfg: Config, session: ClientSession):
        self.cfg = cfg
        self.session = session

    def _headers(self) -> dict:
        h = {
            "Authorization": f"Bearer {self.cfg.rw_api_token}",
            "Accept": "application/json",
        }
        # The panel refuses plain-HTTP API calls unless they look proxied.
        if self.cfg.rw_api_base.startswith("http://"):
            h["X-Forwarded-For"] = "127.0.0.1"
            h["X-Forwarded-Proto"] = "https"
        return h

    async def users_by_telegram_id(self, tg_id: int) -> list[dict]:
        url = f"{self.cfg.rw_api_base}/users/by-telegram-id/{int(tg_id)}"
        async with self.session.get(url, headers=self._headers()) as r:
            if r.status == 404:
                return []
            r.raise_for_status()
            body = await r.json()
        resp = body.get("response", body) if isinstance(body, dict) else body
        if isinstance(resp, dict):
            resp = [resp]
        return [u for u in resp or [] if isinstance(u, dict)]

    async def hwid_devices(self, user_uuid: str) -> list[dict]:
        url = f"{self.cfg.rw_api_base}/hwid/devices/{user_uuid}"
        async with self.session.get(url, headers=self._headers()) as r:
            if r.status == 404:
                return []
            r.raise_for_status()
            body = await r.json()
        resp = body.get("response", body) if isinstance(body, dict) else body
        devices = resp.get("devices", []) if isinstance(resp, dict) else resp
        return [d for d in devices or [] if isinstance(d, dict) and d.get("hwid")]

    async def delete_hwid_device(self, user_uuid: str, hwid: str) -> None:
        url = f"{self.cfg.rw_api_base}/hwid/devices/delete"
        async with self.session.post(url, headers=self._headers(),
                                     json={"userUuid": user_uuid, "hwid": hwid}) as r:
            r.raise_for_status()


def _ts(value) -> float:
    if not value:
        return 0.0
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return 0.0


def pick_user(users: list[dict]) -> dict | None:
    """Several panel users can share one Telegram id; show the best one."""
    if not users:
        return None
    return max(users, key=lambda u: (u.get("status") == "ACTIVE", _ts(u.get("expireAt"))))


STATUS_MAP = {
    "ACTIVE": "active",
    "EXPIRED": "expired",
    "LIMITED": "limited",
    "DISABLED": "disabled",
}


def normalize_subscription(user: dict | None, cfg: Config) -> dict:
    if not user:
        return {"status": "none"}
    # Remnawave moved traffic and online fields into userTraffic in 2.x;
    # read both shapes.
    traffic = user.get("userTraffic") or {}
    used = traffic.get("usedTrafficBytes", user.get("usedTrafficBytes")) or 0
    short = user.get("shortUuid") or ""

    sub_url = user.get("subscriptionUrl") or ""
    if cfg.sub_url_template and short:
        sub_url = cfg.sub_url_template.format(shortUuid=short)
    mirror = cfg.mirror_url_template.format(shortUuid=short) if cfg.mirror_url_template and short else None

    status = STATUS_MAP.get(str(user.get("status", "")).upper(), "disabled")
    if status == "active" and 0 < _ts(user.get("expireAt")) < time.time():
        status = "expired"

    return {
        "status": status,
        "expire_at": user.get("expireAt"),
        "is_trial": bool(cfg.trial_tag) and user.get("tag") == cfg.trial_tag,
        "used_bytes": int(float(used)),
        "limit_bytes": int(float(user.get("trafficLimitBytes") or 0)),
        "device_limit": user.get("hwidDeviceLimit"),
        "online_at": traffic.get("onlineAt", user.get("onlineAt")),
        "first_connected_at": traffic.get("firstConnectedAt", user.get("firstConnectedAt")),
        "sub_url": sub_url,
        "mirror_url": mirror,
    }


def device_id(hwid: str) -> str:
    """Opaque id for the page; the raw HWID never leaves the server."""
    return hashlib.sha256(f"gatex-device:{hwid}".encode()).hexdigest()[:16]


def normalize_devices(devices: list[dict]) -> list[dict]:
    out = [{
        "id": device_id(str(d["hwid"])),
        "platform": d.get("platform") or "",
        "os_version": d.get("osVersion") or "",
        "model": d.get("deviceModel") or "",
        "app": d.get("userAgent") or "",
        "added_at": d.get("createdAt"),
        "seen_at": d.get("updatedAt") or d.get("createdAt"),
    } for d in devices]
    out.sort(key=lambda d: _ts(d["seen_at"]), reverse=True)
    return out


def public_links(cfg: Config) -> dict:
    return {
        "bot": f"https://t.me/{cfg.bot_username}",
        "buy": cfg.buy_url,
        "support": cfg.support_url,
        "channel": cfg.channel_url or None,
        "referral": cfg.referral_url,
    }


# ---------------------------------------------------------------- HTTP

def json_response(data: dict, status: int = 200) -> web.Response:
    return web.json_response(data, status=status, headers={"Cache-Control": "no-store"})


async def _auth(request: web.Request) -> tuple[dict | None, dict]:
    cfg: Config = request.app["cfg"]
    try:
        body = await request.json()
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None, {}
    if not isinstance(body, dict):
        return None, {}
    return validate_init_data(str(body.get("initData", "")), cfg.bot_token), body


async def _load(request: web.Request, tg_id: int, fresh: bool = False) -> dict:
    """Subscription and devices for one Telegram user, cached briefly.

    The panel user's UUID is kept server-side only: it is the VPN credential.
    """
    cache: dict = request.app["cache"]
    hit = cache.get(tg_id)
    if hit and hit[0] > time.time() and not fresh:
        return hit[1]
    rw: Remnawave = request.app["rw"]
    user = pick_user(await rw.users_by_telegram_id(tg_id))
    devices = None
    if user and user.get("uuid"):
        try:
            devices = await rw.hwid_devices(user["uuid"])
        except Exception:
            log.exception("device lookup failed for %s", tg_id)
    entry = {
        "uuid": (user or {}).get("uuid"),
        "raw_devices": devices,
        "subscription": normalize_subscription(user, request.app["cfg"]),
        "devices": normalize_devices(devices) if devices is not None else None,
    }
    cache[tg_id] = (time.time() + CACHE_TTL, entry)
    return entry


def _profile(tg: dict) -> dict:
    return {
        "id": int(tg["id"]),
        "first_name": tg.get("first_name", ""),
        "last_name": tg.get("last_name", ""),
        "username": tg.get("username", ""),
        "photo_url": tg.get("photo_url", ""),
    }


async def handle_me(request: web.Request) -> web.Response:
    cfg: Config = request.app["cfg"]
    init, _ = await _auth(request)
    if not init:
        return json_response({"error": "unauthorized"}, 401)
    tg_id = int(init["user"]["id"])
    try:
        entry = await _load(request, tg_id)
    except Exception:
        log.exception("panel lookup failed for %s", tg_id)
        return json_response({"error": "panel_unavailable"}, 502)
    return json_response({
        "user": _profile(init["user"]),
        "subscription": entry["subscription"],
        "devices": entry["devices"],
        "links": public_links(cfg),
        "price_from": cfg.price_from or None,
    })


async def handle_device_delete(request: web.Request) -> web.Response:
    init, body = await _auth(request)
    if not init:
        return json_response({"error": "unauthorized"}, 401)
    tg_id = int(init["user"]["id"])
    target = str(body.get("id", ""))
    rw: Remnawave = request.app["rw"]
    try:
        entry = await _load(request, tg_id, fresh=True)
        match = next((d for d in entry["raw_devices"] or []
                      if device_id(str(d["hwid"])) == target), None)
        if not entry["uuid"] or not match:
            return json_response({"error": "not_found"}, 404)
        await rw.delete_hwid_device(entry["uuid"], str(match["hwid"]))
        log.info("tg %s removed device %s", tg_id, target)
        entry = await _load(request, tg_id, fresh=True)
    except Exception:
        log.exception("device delete failed for %s", tg_id)
        return json_response({"error": "panel_unavailable"}, 502)
    return json_response({"devices": entry["devices"]})


async def handle_health(request: web.Request) -> web.Response:
    return json_response({"ok": True})


async def handle_static(request: web.Request) -> web.StreamResponse:
    root: Path = request.app["cfg"].web_dir.resolve()
    rel = request.match_info.get("path", "") or "index.html"
    path = (root / rel).resolve()
    if root not in path.parents and path != root:
        raise web.HTTPNotFound()
    if path.is_dir():
        path = path / "index.html"
    if not path.is_file():
        raise web.HTTPNotFound()
    cache = "no-cache" if path.suffix == ".html" else "public, max-age=3600"
    return web.FileResponse(path, headers={"Cache-Control": cache})


async def _on_startup(app: web.Application) -> None:
    session = ClientSession(timeout=ClientTimeout(total=10))
    app["http"] = session
    app["rw"] = Remnawave(app["cfg"], session)


async def _on_cleanup(app: web.Application) -> None:
    await app["http"].close()


def create_app(cfg: Config) -> web.Application:
    app = web.Application(client_max_size=64 * 1024)
    app["cfg"] = cfg
    app["cache"] = {}
    app.on_startup.append(_on_startup)
    app.on_cleanup.append(_on_cleanup)
    app.router.add_post("/api/me", handle_me)
    app.router.add_post("/api/devices/delete", handle_device_delete)
    app.router.add_get("/api/health", handle_health)
    app.router.add_get("/{path:.*}", handle_static)
    return app


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    cfg = Config.from_env()
    missing = [n for n, v in (("BOT_TOKEN", cfg.bot_token), ("RW_API_BASE", cfg.rw_api_base),
                              ("RW_API_TOKEN", cfg.rw_api_token)) if not v]
    if missing:
        raise SystemExit(f"missing env: {', '.join(missing)}")
    web.run_app(create_app(cfg), host=os.environ.get("HOST", "127.0.0.1"),
                port=int(os.environ.get("PORT", "8095")))


if __name__ == "__main__":
    main()
