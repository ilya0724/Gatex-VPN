"""GateX tariffs for users who signed up after the 2026-10 tariff change.

Pure data and arithmetic, no imports beyond the standard library, so the
bot can load the same file and both sides agree on every price.

A tariff is a plan, with or without the whitelist bypass ("обход БС": the
two LTE ОСНОВНАЯ hosts in Poland) where the plan offers the choice.
Plans also differ in servers: "all" is every country and "⚡ Авто", "lite"
is the short economy list (the bot maps both to Remnawave squads), and in
monthly traffic (0 means unlimited).
More devices are sold in whole packs of the plan's base size at the same
price per pack. The plan is stored as the Remnawave user tag; users without
one of these tags are on the old tariffs: they keep them until their
subscription ends, and a purchase switches them to the new tariff then.

Legacy plans are no longer sold to new buyers: only someone already on that
plan sees it in the catalog and can renew it at the old price.
"""

from __future__ import annotations

MONTHS = (1, 3, 6, 12)
DISCOUNTS = {1: 0, 3: 10, 6: 15, 12: 25}  # percent, roughly baked into PRICES

PLANS = {
    "economy": {
        "title": "Эконом",
        "blurb": "Две страны, без обхода БС",
        "base_devices": 2,
        "device_steps": (2, 4),
        "servers": "lite",
        "traffic_gb": 100,
        # price of one device pack for the whole period, by bypass and months;
        # a missing bypass key means the plan does not offer that option
        "prices": {
            False: {1: 49, 3: 129, 6: 249, 12: 439},
        },
    },
    "standard": {
        "title": "Стандарт",
        "blurb": "Все страны и «Авто»",
        "base_devices": 3,
        "device_steps": (3, 6, 9),
        "servers": "all",
        "traffic_gb": 0,
        "prices": {
            False: {1: 99, 3: 269, 6: 499, 12: 890},
            True: {1: 179, 3: 479, 6: 909, 12: 1590},
        },
    },
    "family": {
        "title": "Семейный",
        "blurb": "Телефоны, ноутбуки и ТВ всей семьи",
        "base_devices": 7,
        "device_steps": (7, 14, 21),
        "servers": "all",
        "traffic_gb": 0,
        "prices": {
            False: {1: 199, 3: 539, 6: 999, 12: 1790},
            True: {1: 399, 3: 1079, 6: 1990, 12: 3590},
        },
    },
    "vip": {
        "title": "VIP",
        "blurb": "Всё включено, поддержка вне очереди",
        "base_devices": 5,
        "device_steps": (5, 10),
        "servers": "all",
        "traffic_gb": 0,
        "prices": {
            True: {1: 399, 3: 1079, 6: 1990, 12: 3590},
        },
    },
    # the 17.10 «Эконом»: every country for 50 ₽; kept for people already on it
    "eco": {
        "title": "Стандарт",
        "blurb": "Ваш тариф по прежней цене",
        "legacy": True,
        "base_devices": 2,
        "device_steps": (2, 4, 6, 8),
        "servers": "all",
        "traffic_gb": 0,
        "prices": {
            False: {1: 50, 3: 135, 6: 255, 12: 450},
            True: {1: 100, 3: 270, 6: 510, 12: 900},
        },
    },
}

TRIAL = {"days": 3, "devices": 2, "bypass": True, "tag": "TRIAL"}

TAGS = {
    ("economy", False): "ECONOMY",
    ("standard", False): "STANDARD",
    ("standard", True): "STANDARD_BS",
    ("family", False): "FAMILY",
    ("family", True): "FAMILY_BS",
    ("vip", True): "VIP",
    ("eco", False): "ECO",
    ("eco", True): "ECO_BS",
}
NEW_FLOW_TAGS = frozenset(TAGS.values()) | {TRIAL["tag"]}


def bypass_options(plan: str) -> tuple[bool, ...]:
    return tuple(sorted(PLANS[plan]["prices"]))


def on_sale(plan: str, current: str | None = None) -> bool:
    """Legacy plans can only be renewed by someone already on them."""
    p = PLANS.get(plan)
    return p is not None and (not p.get("legacy") or plan == current)


def price(plan: str, bypass: bool, devices: int, months: int) -> int:
    """Total in rubles; raises ValueError for anything not on sale."""
    p = PLANS.get(plan)
    if p is None:
        raise ValueError("unknown plan")
    if months not in MONTHS:
        raise ValueError("unknown period")
    if devices not in p["device_steps"]:
        raise ValueError("unsupported device count")
    if bool(bypass) not in p["prices"]:
        raise ValueError("bypass option not offered")
    return p["prices"][bool(bypass)][months] * (devices // p["base_devices"])


def make_order(plan, bypass, devices, months, current: str | None = None) -> dict:
    """Validated order from untrusted input.

    current is the buyer's plan code from their panel tag (None for old-tariff
    users and trials); it only matters for renewing a legacy plan.
    """
    try:
        devices, months = int(devices), int(months)
    except (TypeError, ValueError):
        raise ValueError("bad number") from None
    if not isinstance(bypass, bool):
        raise ValueError("bad bypass flag")
    plan = str(plan)
    if not on_sale(plan, current):
        raise ValueError("plan not on sale")
    amount = price(plan, bypass, devices, months)
    p = PLANS[plan]
    return {
        "plan": plan,
        "bypass": bypass,
        "devices": devices,
        "months": months,
        "days": months * 30,
        "amount": amount,
        "tag": TAGS[(plan, bypass)],
        "servers": p["servers"],
        "traffic_gb": p["traffic_gb"],
    }


def daily_value(plan: str, bypass: bool, devices: int) -> float:
    """Rubles per day at the monthly price; used to convert leftover days
    when someone switches tariff."""
    return price(plan, bypass, devices, 1) / 30


def tariff_from_tag(tag: str | None, device_limit: int | None = None) -> dict | None:
    if not tag:
        return None
    if tag == TRIAL["tag"]:
        return {"code": "trial", "title": "Пробный", "bypass": True, "devices": TRIAL["devices"]}
    for (plan, bypass), t in TAGS.items():
        if t == tag:
            p = PLANS[plan]
            return {
                "code": plan,
                "title": p["title"],
                "bypass": bypass,
                "devices": device_limit or p["base_devices"],
                "traffic_gb": p["traffic_gb"],
            }
    return None


def catalog(current: str | None = None) -> dict:
    """What the purchase screen needs, JSON-ready."""
    return {
        "months": [{"months": m, "discount": DISCOUNTS[m]} for m in MONTHS],
        "plans": [{
            "code": code,
            "title": p["title"],
            "blurb": p["blurb"],
            "legacy": bool(p.get("legacy")),
            "base_devices": p["base_devices"],
            "device_steps": list(p["device_steps"]),
            "servers": p["servers"],
            "traffic_gb": p["traffic_gb"],
            "bypass_options": list(bypass_options(code)),
            "prices": {"plain": p["prices"].get(False), "bypass": p["prices"].get(True)},
        } for code, p in PLANS.items() if on_sale(code, current)],
    }
