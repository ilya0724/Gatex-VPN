import pytest

import plans


def test_prices_match_the_grid():
    assert plans.price("economy", False, 2, 1) == 49
    assert plans.price("economy", False, 4, 12) == 2 * 439
    assert plans.price("standard", True, 6, 1) == 2 * 179
    assert plans.price("vip", True, 5, 3) == 1079
    assert plans.price("eco", True, 8, 1) == 400
    assert plans.price("family", True, 7, 3) == 1079
    assert plans.price("family", False, 21, 12) == 3 * 1790


@pytest.mark.parametrize("args", [
    ("gold", False, 2, 1), ("economy", True, 2, 1), ("vip", False, 5, 1),
    ("economy", False, 3, 1), ("standard", False, 2, 1), ("eco", False, 2, 2), ("family", True, 8, 1),
])
def test_price_rejects_what_is_not_on_sale(args):
    with pytest.raises(ValueError):
        plans.price(*args)


def test_make_order_validates_untrusted_input():
    order = plans.make_order("family", True, "14", "6")
    assert order == {"plan": "family", "bypass": True, "devices": 14, "months": 6,
                     "days": 180, "amount": 3980, "tag": "FAMILY_BS",
                     "servers": "all", "traffic_gb": 0}
    assert plans.make_order("economy", False, 2, 1)["servers"] == "lite"
    assert plans.make_order("economy", False, 2, 1)["traffic_gb"] == 0
    with pytest.raises(ValueError):
        plans.make_order("standard", "yes", 3, 1)
    with pytest.raises(ValueError):
        plans.make_order("standard", False, None, 1)


def test_legacy_plan_only_for_its_users():
    with pytest.raises(ValueError):
        plans.make_order("eco", False, 2, 1)
    with pytest.raises(ValueError):
        plans.make_order("eco", False, 2, 1, current="family")
    assert plans.make_order("eco", False, 2, 1, current="eco")["amount"] == 50
    codes = [p["code"] for p in plans.catalog()["plans"]]
    assert codes == ["economy", "standard", "family", "vip"]
    assert "eco" in [p["code"] for p in plans.catalog("eco")["plans"]]


def test_catalog_lists_bypass_choices():
    by_code = {p["code"]: p for p in plans.catalog()["plans"]}
    assert by_code["economy"]["bypass_options"] == [False]
    assert by_code["economy"]["prices"]["bypass"] is None
    assert by_code["vip"]["bypass_options"] == [True]
    assert by_code["standard"]["bypass_options"] == [False, True]


def test_every_tag_is_distinct_and_fits_remnawave():
    tags = list(plans.TAGS.values()) + [plans.TRIAL["tag"]]
    assert len(tags) == len(set(tags))
    for t in tags:
        assert len(t) <= 16 and t.replace("_", "").isalnum() and t.isupper()
    for (plan, bypass) in plans.TAGS:
        assert bypass in plans.bypass_options(plan)
    for plan in plans.PLANS:
        for b in plans.bypass_options(plan):
            assert (plan, b) in plans.TAGS


def test_tags_round_trip():
    assert plans.tariff_from_tag("ECO_BS", 4) == {"code": "eco", "title": "Стандарт", "bypass": True,
                                                  "devices": 4, "traffic_gb": 0}
    assert plans.tariff_from_tag("VIP")["code"] == "vip"
    assert plans.tariff_from_tag("ECONOMY")["traffic_gb"] == 0
    assert plans.tariff_from_tag("TRIAL")["code"] == "trial"
    assert plans.tariff_from_tag("SOMETHING_OLD") is None
    assert plans.tariff_from_tag(None) is None
