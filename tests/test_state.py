import pytest

from portal_bridge.state import PlayerState, StateError, TravelState, WeaponState, decode, encode

# Shaped exactly like pb_encode_state() output.
GSC_SAMPLE = (
    "PB1|n=8150042|src=waw:nazi_zombie_factory|dst=bo1:zombie_theater|r=12"
    "|p0=4520~specialty_armorvest.specialty_rof~zombie_thompson@20@140.ray_gun_upgraded@40@160~ray_gun_upgraded"
    "|p1=500~-~zombie_colt@8@32~zombie_colt"
)


def test_decode_gsc_output():
    s = decode(GSC_SAMPLE)
    assert (s.src_game, s.src_map, s.dst_game, s.dst_map) == ("waw", "nazi_zombie_factory", "bo1", "zombie_theater")
    assert s.round == 12
    assert s.nonce == "8150042"
    p0 = s.players[0]
    assert p0.score == 4520
    assert p0.perks == ["specialty_armorvest", "specialty_rof"]
    assert p0.weapons[1] == WeaponState(["ray_gun_upgraded"], 40, 160)
    assert p0.current == ["ray_gun_upgraded"]
    assert s.players[1].perks == []


def test_roundtrip():
    state = TravelState(
        "bo1", "zombie_moon", "waw", "nazi_zombie_sumpf", round=31, nonce="1",
        players={
            0: PlayerState(9000, ["specialty_quickrevive"], [WeaponState(["zombie_mp40", "mp40"], 32, 192)], ["zombie_mp40"]),
            1: PlayerState(500),
        },
    )
    assert decode(encode(state)) == state


def test_empty_fields_use_dashes():
    text = encode(TravelState("waw", "a", "bo1", "b", players={0: PlayerState(500)}))
    assert text.endswith("|p0=500~-~-~-")


@pytest.mark.parametrize("bad", [
    "",
    "PB2|src=waw:a|dst=bo1:b",
    "PB1|src=waw:a",
    "PB1|src=waw:a|dst=bo1:b|p0=500~-~-",
    "PB1|src=waw:a|dst=bo1:b|p0=abc~-~-~-",
    "PB1|src=waw:a|dst=bo1:b;quit",
])
def test_rejects_malformed(bad):
    with pytest.raises(StateError):
        decode(bad)


def test_encode_refuses_unsafe_names():
    state = TravelState("waw", "a", "bo1", "b", players={0: PlayerState(500, ["x;quit"])})
    with pytest.raises(StateError):
        encode(state)
