import hashlib
import hmac
import json
import time
from urllib.parse import urlencode

import pytest

import app as cabinet

TOKEN = "123456:TEST"


def sign(fields: dict, token: str = TOKEN) -> str:
    check = "\n".join(f"{k}={fields[k]}" for k in sorted(fields))
    secret = hmac.new(b"WebAppData", token.encode(), hashlib.sha256).digest()
    h = hmac.new(secret, check.encode(), hashlib.sha256).hexdigest()
    return urlencode({**fields, "hash": h})


def init_data(user_id=42, age=0, **extra):
    fields = {
        "auth_date": str(int(time.time()) - age),
        "query_id": "AAE",
        "user": json.dumps({"id": user_id, "first_name": "Илья", "username": "ilya"}, ensure_ascii=False),
        **extra,
    }
    return sign(fields)


def cfg(**kw):
    base = dict(bot_token=TOKEN, rw_api_base="http://panel/api", rw_api_token="t",
                mirror_url_template="https://r1.example/s/{shortUuid}")
    base.update(kw)
    return cabinet.Config(**base)


def test_valid_init_data():
    data = cabinet.validate_init_data(init_data(signature="abc"), TOKEN)
    assert data["user"]["id"] == 42


def test_rejects_tampered_and_stale_init_data():
    good = init_data()
    assert cabinet.validate_init_data(good.replace("42", "43"), TOKEN) is None
    assert cabinet.validate_init_data(good, "999:OTHER") is None
    assert cabinet.validate_init_data(init_data(age=2 * 86400), TOKEN) is None
    assert cabinet.validate_init_data("", TOKEN) is None


def test_pick_user_prefers_active_then_latest():
    users = [
        {"status": "EXPIRED", "expireAt": "2027-01-01T00:00:00Z", "shortUuid": "a"},
        {"status": "ACTIVE", "expireAt": "2026-11-01T00:00:00Z", "shortUuid": "b"},
        {"status": "ACTIVE", "expireAt": "2026-12-01T00:00:00Z", "shortUuid": "c"},
    ]
    assert cabinet.pick_user(users)["shortUuid"] == "c"
    assert cabinet.pick_user([]) is None


def test_normalize_new_and_old_shapes():
    future = "2099-01-01T00:00:00.000Z"
    new = {"status": "ACTIVE", "expireAt": future, "shortUuid": "abc", "trafficLimitBytes": 0,
           "subscriptionUrl": "https://sub/abc", "hwidDeviceLimit": 3, "tag": "TRIAL",
           "userTraffic": {"usedTrafficBytes": 1024, "onlineAt": future}}
    s = cabinet.normalize_subscription(new, cfg(trial_tag="TRIAL"))
    assert s["status"] == "active" and s["used_bytes"] == 1024 and s["is_trial"]
    assert s["sub_url"] == "https://sub/abc" and s["mirror_url"] == "https://r1.example/s/abc"

    old = {"status": "ACTIVE", "expireAt": "2020-01-01T00:00:00Z", "shortUuid": "x",
           "usedTrafficBytes": "2048"}
    s = cabinet.normalize_subscription(old, cfg(sub_url_template="https://cdn/{shortUuid}"))
    assert s["status"] == "expired" and s["used_bytes"] == 2048 and not s["is_trial"]
    assert s["sub_url"] == "https://cdn/x"
    assert cabinet.normalize_subscription(None, cfg()) == {"status": "none"}


class FakeRW:
    def __init__(self, users):
        self.users, self.calls = users, 0

    async def users_by_telegram_id(self, tg_id):
        self.calls += 1
        return self.users


@pytest.fixture
async def client(aiohttp_client, tmp_path):
    (tmp_path / "index.html").write_text("<p>cabinet</p>")
    application = cabinet.create_app(cfg(web_dir=tmp_path))
    application.on_startup.clear()
    application.on_cleanup.clear()
    fake = FakeRW([{"status": "ACTIVE", "expireAt": "2099-01-01T00:00:00Z", "shortUuid": "s1"}])
    application["rw"] = fake
    c = await aiohttp_client(application)
    c.fake = fake
    return c


async def test_me_endpoint(client):
    r = await client.post("/api/me", json={"initData": init_data()})
    assert r.status == 200
    body = await r.json()
    assert body["user"]["id"] == 42
    assert body["subscription"]["status"] == "active"
    assert body["links"]["bot"] == "https://t.me/gatexvpn_bot"
    await client.post("/api/me", json={"initData": init_data()})
    assert client.fake.calls == 1  # second call served from cache


async def test_me_rejects_bad_init_data(client):
    r = await client.post("/api/me", json={"initData": "user=%7B%22id%22%3A1%7D&hash=00"})
    assert r.status == 401


async def test_static_and_traversal(client):
    r = await client.get("/")
    assert r.status == 200 and "cabinet" in await r.text()
    r = await client.get("/../app.py")
    assert r.status == 404
