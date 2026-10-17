import pytest

import plans


def test_prices_match_the_grid():
    assert plans.price("eco", False, 2, 1) == 50
    assert plans.price("eco", True, 8, 1) == 400
    assert plans.price("family", True, 7, 3) == 1079
    assert plans.price("family", False, 21, 12) == 3 * 1790


@pytest.mark.parametrize("args", [
    ("vip", False, 2, 1), ("eco", False, 3, 1), ("eco", False, 2, 2), ("family", True, 8, 1),
])
def test_price_rejects_what_is_not_on_sale(args):
    with pytest.raises(ValueError):
        plans.price(*args)


def test_make_order_validates_untrusted_input():
    order = plans.make_order("family", True, "14", "6")
    assert order == {"plan": "family", "bypass": True, "devices": 14, "months": 6,
                     "days": 180, "amount": 3980, "tag": "FAMILY_BS"}
    with pytest.raises(ValueError):
        plans.make_order("eco", "yes", 2, 1)
    with pytest.raises(ValueError):
        plans.make_order("eco", False, None, 1)


def test_tags_round_trip():
    assert plans.tariff_from_tag("ECO_BS", 4) == {"code": "eco", "title": "Эконом", "bypass": True, "devices": 4}
    assert plans.tariff_from_tag("TRIAL")["code"] == "trial"
    assert plans.tariff_from_tag("SOMETHING_OLD") is None
    assert plans.tariff_from_tag(None) is None
