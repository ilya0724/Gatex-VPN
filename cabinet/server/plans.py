"""GateX tariffs for users who signed up after the 2026-10 tariff change.

Pure data and arithmetic, no imports beyond the standard library, so the
bot can load the same file and both sides agree on every price.

A tariff is a plan (eco or family), with or without the whitelist bypass
("обход БС": the two LTE ОСНОВНАЯ hosts in Poland).
More devices are sold in whole packs of the plan's base size at the same
price per pack. The plan is stored as the Remnawave user tag; users without
one of these tags are on the old tariffs: they keep them until their
subscription ends, and a purchase switches them to the new tariff then.
"""

from __future__ import annotations

MONTHS = (1, 3, 6, 12)
DISCOUNTS = {1: 0, 3: 10, 6: 15, 12: 25}  # percent, already baked into PRICES

PLANS = {
    "eco": {
        "title": "Эконом",
        "base_devices": 2,
        "device_steps": (2, 4, 6, 8),
        # price of one device pack for the whole period, by bypass and months
        "prices": {
            False: {1: 50, 3: 135, 6: 255, 12: 450},
            True: {1: 100, 3: 270, 6: 510, 12: 900},
        },
    },
    "family": {
        "title": "Семейный",
        "base_devices": 7,
        "device_steps": (7, 14, 21),
        "prices": {
            False: {1: 199, 3: 539, 6: 999, 12: 1790},
            True: {1: 399, 3: 1079, 6: 1990, 12: 3590},
        },
    },
}

TRIAL = {"days": 3, "devices": 2, "bypass": True, "tag": "TRIAL"}

TAGS = {
    ("eco", False): "ECO",
    ("eco", True): "ECO_BS",
    ("family", False): "FAMILY",
    ("family", True): "FAMILY_BS",
}
NEW_FLOW_TAGS = frozenset(TAGS.values()) | {TRIAL["tag"]}


def price(plan: str, bypass: bool, devices: int, months: int) -> int:
    """Total in rubles; raises ValueError for anything not on sale."""
    p = PLANS.get(plan)
    if p is None:
        raise ValueError("unknown plan")
    if months not in MONTHS:
        raise ValueError("unknown period")
    if devices not in p["device_steps"]:
        raise ValueError("unsupported device count")
    return p["prices"][bool(bypass)][months] * (devices // p["base_devices"])


def make_order(plan, bypass, devices, months) -> dict:
    """Validated order from untrusted input."""
    try:
        devices, months = int(devices), int(months)
    except (TypeError, ValueError):
        raise ValueError("bad number") from None
    if not isinstance(bypass, bool):
        raise ValueError("bad bypass flag")
    plan = str(plan)
    amount = price(plan, bypass, devices, months)
    return {
        "plan": plan,
        "bypass": bypass,
        "devices": devices,
        "months": months,
        "days": months * 30,
        "amount": amount,
        "tag": TAGS[(plan, bypass)],
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
            }
    return None


def catalog() -> dict:
    """What the purchase screen needs, JSON-ready."""
    return {
        "months": [{"months": m, "discount": DISCOUNTS[m]} for m in MONTHS],
        "plans": [{
            "code": code,
            "title": p["title"],
            "base_devices": p["base_devices"],
            "device_steps": list(p["device_steps"]),
            "prices": {"plain": p["prices"][False], "bypass": p["prices"][True]},
        } for code, p in PLANS.items()],
    }
