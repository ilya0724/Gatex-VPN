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
    def __init__(self, users, devices):
        self.users, self.devices, self.calls, self.deleted = users, devices, 0, []
        self.revoked = []

    async def users_by_telegram_id(self, tg_id):
        self.calls += 1
        return self.users

    async def hwid_devices(self, user_uuid):
        assert user_uuid == "uuid-1"
        return list(self.devices)

    async def delete_hwid_device(self, user_uuid, hwid):
        self.deleted.append((user_uuid, hwid))
        self.devices = [d for d in self.devices if d["hwid"] != hwid]

    async def revoke_passwords(self, user_uuid):
        self.revoked.append(user_uuid)


DEVICES = [
    {"hwid": "hw-old", "platform": "Windows", "osVersion": "11", "deviceModel": "PC",
     "userAgent": "Happ/1.0", "createdAt": "2026-09-01T00:00:00Z", "updatedAt": "2026-09-02T00:00:00Z"},
    {"hwid": "hw-new", "platform": "iOS", "osVersion": "18.1", "deviceModel": "iPhone15,2",
     "userAgent": "Happ/3.0", "createdAt": "2026-10-01T00:00:00Z", "updatedAt": "2026-10-16T00:00:00Z"},
]


@pytest.fixture
async def client(aiohttp_client, tmp_path):
    (tmp_path / "index.html").write_text("<p>cabinet</p>")
    application = cabinet.create_app(cfg(web_dir=tmp_path))
    application.on_startup.clear()
    application.on_cleanup.clear()
    fake = FakeRW([{"uuid": "uuid-1", "status": "ACTIVE", "expireAt": "2099-01-01T00:00:00Z",
                    "shortUuid": "s1"}], DEVICES)
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
    assert [d["platform"] for d in body["devices"]] == ["iOS", "Windows"]  # newest first
    text = json.dumps(body)
    assert "hw-new" not in text and "uuid-1" not in text  # credentials stay server-side
    await client.post("/api/me", json={"initData": init_data()})
    assert client.fake.calls == 1  # second call served from cache


async def test_device_delete(client):
    me = await (await client.post("/api/me", json={"initData": init_data()})).json()
    target = next(d["id"] for d in me["devices"] if d["platform"] == "Windows")
    r = await client.post("/api/devices/delete", json={"initData": init_data(), "id": target})
    assert r.status == 200
    assert [d["platform"] for d in (await r.json())["devices"]] == ["iOS"]
    assert client.fake.deleted == [("uuid-1", "hw-old")]
    assert client.fake.revoked == ["uuid-1"]  # copied configs stop working

    r = await client.post("/api/devices/delete", json={"initData": init_data(), "id": "nope"})
    assert r.status == 404
    r = await client.post("/api/devices/delete", json={"initData": "bad", "id": target})
    assert r.status == 401


async def test_me_rejects_bad_init_data(client):
    r = await client.post("/api/me", json={"initData": "user=%7B%22id%22%3A1%7D&hash=00"})
    assert r.status == 401


async def test_static_and_traversal(client):
    r = await client.get("/")
    assert r.status == 200 and "cabinet" in await r.text()
    r = await client.get("/../app.py")
    assert r.status == 404


async def test_remnawave_3x_fallbacks(aiohttp_client):
    """3.x has no by-telegram-id route and uses numeric user ids."""
    from aiohttp import ClientSession, web as aweb

    seen = {}

    async def list_users(request):
        start = int(request.query["start"])
        users = [{"id": i, "telegramId": str(1000 + i), "status": "ACTIVE", "shortUuid": f"s{i}"}
                 for i in range(1, 4)]
        return aweb.json_response({"response": {"users": users[start:], "total": len(users)}})

    async def devices(request):
        return aweb.json_response({"response": {"total": 1, "devices": [{"hwid": "hw-1", "platform": "iOS"}]}})

    async def delete(request):
        seen["delete"] = await request.json()
        return aweb.json_response({"response": {}})

    async def revoke(request):
        seen["revoke"] = (request.match_info["key"], await request.json())
        return aweb.json_response({"response": {}})

    panel = aweb.Application()
    panel.router.add_get("/api/users", list_users)
    panel.router.add_get("/api/hwid/devices/{key}", devices)
    panel.router.add_post("/api/hwid/devices/delete", delete)
    panel.router.add_post("/api/users/{key}/actions/revoke", revoke)
    srv = await aiohttp_client(panel)

    async with ClientSession() as session:
        rw = cabinet.Remnawave(cfg(rw_api_base=str(srv.make_url("/api"))), session)
        users = await rw.users_by_telegram_id(1002)
        assert [u["shortUuid"] for u in users] == ["s2"]
        key = cabinet.user_key(users[0])
        assert key == 2
        assert (await rw.hwid_devices(key))[0]["hwid"] == "hw-1"
        await rw.delete_hwid_device(key, "hw-1")
        assert seen["delete"] == {"userId": 2, "hwid": "hw-1"}
        await rw.revoke_passwords(key)
        assert seen["revoke"] == ("2", {"revokeOnlyPasswords": True})
        assert await rw.users_by_telegram_id(9999) == []


async def test_pay_goes_through_the_bot_for_new_tariffs(aiohttp_client, aiohttp_server, tmp_path):
    from aiohttp import ClientSession, web as aweb

    seen = []

    async def bot_pay(request):
        seen.append(await request.json())
        return aweb.json_response({"pay_url": "https://pay.example/x", "amount": 1079, "payment_id": "p1"})

    bot = aweb.Application()
    bot.router.add_post("/api/plan/pay", bot_pay)
    bot_server = await aiohttp_server(bot)

    application = cabinet.create_app(cfg(web_dir=tmp_path, bot_pay_url=str(bot_server.make_url("/api/plan/pay"))))
    application.on_startup.clear()
    application.on_cleanup.clear()
    fake = FakeRW([{"uuid": "uuid-1", "status": "ACTIVE", "expireAt": "2099-01-01T00:00:00Z",
                    "shortUuid": "s1", "tag": "TRIAL", "hwidDeviceLimit": 2}], [])
    application["rw"] = fake
    session = ClientSession()
    application["http"] = session
    c = await aiohttp_client(application)
    try:
        me = await (await c.post("/api/me", json={"initData": init_data()})).json()
        assert me["tariff"]["code"] == "trial"
        assert me["subscription"]["is_trial"] is True
        assert [p["code"] for p in me["plans"]["plans"]] == ["eco", "family"]

        order = {"initData": init_data(), "plan": "family", "bypass": True, "devices": 7, "months": 3, "method": "sbp"}
        r = await c.post("/api/pay", json=order)
        assert r.status == 200
        assert await r.json() == {"pay_url": "https://pay.example/x", "amount": 1079}
        assert seen[0]["plan"] == "family" and seen[0]["bypass"] is True and seen[0]["initData"]

        r = await c.post("/api/pay", json={**order, "devices": 8})
        assert r.status == 400
        r = await c.post("/api/pay", json={**order, "method": "cash"})
        assert r.status == 400
        r = await c.post("/api/pay", json={**order, "initData": "bad"})
        assert r.status == 401
        assert len(seen) == 1

        # an old-tariff user can buy too; the bot defers the switch to their expiry
        fake.users[0]["tag"] = None
        application["cache"].clear()
        me = await (await c.post("/api/me", json={"initData": init_data()})).json()
        assert me["tariff"] is None and me["plans"]["plans"]
        r = await c.post("/api/pay", json=order)
        assert r.status == 200 and len(seen) == 2
    finally:
        await session.close()


async def test_page_assets_are_revalidated(aiohttp_client, tmp_path):
    (tmp_path / "vendor").mkdir()
    (tmp_path / "app.js").write_text("1")
    (tmp_path / "vendor" / "qrcode.js").write_text("2")
    application = cabinet.create_app(cfg(web_dir=tmp_path))
    application.on_startup.clear()
    application.on_cleanup.clear()
    c = await aiohttp_client(application)
    assert (await c.get("/app.js")).headers["Cache-Control"] == "no-cache"
    assert "max-age" in (await c.get("/vendor/qrcode.js")).headers["Cache-Control"]


async def test_referral_link_with_and_without_the_bot(aiohttp_client, aiohttp_server, tmp_path):
    from aiohttp import ClientSession, web as aweb

    async def bot_me(request):
        assert request.headers["X-Init-Data"]
        return aweb.json_response({"referral_link": "https://t.me/gatexvpn_bot?start=ref42", "referral_count": 3})

    bot = aweb.Application()
    bot.router.add_get("/api/me", bot_me)
    bot_server = await aiohttp_server(bot)
    session = ClientSession()
    try:
        for url, count in ((str(bot_server.make_url("/api/me")), 3), ("", None)):
            application = cabinet.create_app(cfg(web_dir=tmp_path, bot_me_url=url))
            application.on_startup.clear()
            application.on_cleanup.clear()
            application["http"] = session
            c = await aiohttp_client(application)
            r = await c.post("/api/referral", json={"initData": init_data()})
            assert r.status == 200
            assert await r.json() == {"link": "https://t.me/gatexvpn_bot?start=ref42", "count": count, "bonus_percent": 25}
            assert (await c.post("/api/referral", json={"initData": "bad"})).status == 401
    finally:
        await session.close()


async def test_device_delete_blacklists_in_the_bot_first(aiohttp_client, aiohttp_server, tmp_path):
    from aiohttp import ClientSession, web as aweb

    seen, state = [], {"status": 200}

    async def bot_revoke(request):
        seen.append(await request.json())
        return aweb.json_response({"ok": True}, status=state["status"])

    bot = aweb.Application()
    bot.router.add_post("/api/devices/revoke-hwid", bot_revoke)
    bot_server = await aiohttp_server(bot)

    application = cabinet.create_app(cfg(web_dir=tmp_path,
                                         bot_revoke_url=str(bot_server.make_url("/api/devices/revoke-hwid"))))
    application.on_startup.clear()
    application.on_cleanup.clear()
    fake = FakeRW([{"uuid": "uuid-1", "status": "ACTIVE", "expireAt": "2099-01-01T00:00:00Z",
                    "shortUuid": "s1"}], DEVICES)
    application["rw"] = fake
    session = ClientSession()
    application["http"] = session
    c = await aiohttp_client(application)
    try:
        me = await (await c.post("/api/me", json={"initData": init_data()})).json()
        ids = {d["platform"]: d["id"] for d in me["devices"]}

        # bot down: nothing is deleted, so the device can't sneak back
        state["status"] = 500
        r = await c.post("/api/devices/delete", json={"initData": init_data(), "id": ids["Windows"]})
        assert r.status == 502
        assert fake.deleted == [] and fake.revoked == []

        state["status"] = 200
        r = await c.post("/api/devices/delete", json={"initData": init_data(), "id": ids["Windows"]})
        assert r.status == 200
        assert (await r.json())["keys_rotated"] is True
        assert seen[-1]["hwid"] == "hw-old" and seen[-1]["initData"]
        assert fake.deleted == [("uuid-1", "hw-old")] and fake.revoked == ["uuid-1"]
    finally:
        await session.close()


async def test_removed_devices_can_be_restored(aiohttp_client, aiohttp_server, tmp_path):
    from aiohttp import ClientSession, web as aweb

    blocked = {"hw-old": {"hwid": "hw-old", "platform": "android", "model": "Pixel 8",
                          "app": "Happ", "revoked_at": "2026-10-19T08:00:00Z"}}
    restored = []

    async def revoked(request):
        assert (await request.json())["initData"]
        return aweb.json_response({"devices": list(blocked.values())})

    async def restore(request):
        hwid = (await request.json())["hwid"]
        if hwid not in blocked:
            return aweb.json_response({"error": "not_found"}, status=404)
        restored.append(blocked.pop(hwid)["hwid"])
        return aweb.json_response({"ok": True})

    bot = aweb.Application()
    bot.router.add_post("/api/devices/revoked", revoked)
    bot.router.add_post("/api/devices/restore-hwid", restore)
    bot_server = await aiohttp_server(bot)

    application = cabinet.create_app(cfg(web_dir=tmp_path,
                                         bot_revoke_url=str(bot_server.make_url("/api/devices/revoke-hwid"))))
    application.on_startup.clear()
    application.on_cleanup.clear()
    application["rw"] = FakeRW([{"uuid": "uuid-1", "status": "ACTIVE", "shortUuid": "s1"}], [])
    session = ClientSession()
    application["http"] = session
    c = await aiohttp_client(application)
    try:
        r = await c.post("/api/devices/removed", json={"initData": init_data()})
        assert r.status == 200
        removed = (await r.json())["removed"]
        assert [d["model"] for d in removed] == ["Pixel 8"]
        assert "hw-old" not in json.dumps(removed)  # raw HWID stays server-side

        r = await c.post("/api/devices/restore", json={"initData": init_data(), "id": "nope"})
        assert r.status == 404
        r = await c.post("/api/devices/restore", json={"initData": init_data(), "id": removed[0]["id"]})
        assert r.status == 200
        assert (await r.json())["removed"] == [] and restored == ["hw-old"]
        r = await c.post("/api/devices/removed", json={"initData": "bad"})
        assert r.status == 401
    finally:
        await session.close()


async def test_removed_devices_without_the_bot(client):
    r = await client.post("/api/devices/removed", json={"initData": init_data()})
    assert r.status == 200 and (await r.json())["removed"] == []


def test_mirror_can_be_the_primary_link():
    user = {"status": "ACTIVE", "shortUuid": "abc", "subscriptionUrl": "https://sub/abc"}
    s = cabinet.normalize_subscription(user, cfg(prefer_mirror=True))
    assert s["sub_url"] == "https://r1.example/s/abc" and s["mirror_url"] == "https://sub/abc"


def test_empty_support_link_falls_back_to_the_support_account(monkeypatch):
    monkeypatch.setenv("SUPPORT_URL", "")
    assert cabinet.Config.from_env().support_url == "https://t.me/gatexvpn_support"
