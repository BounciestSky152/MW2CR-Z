from portal_bridge.config import load_config
from portal_bridge.state import PlayerState, TravelState, WeaponState
from portal_bridge.translate import WeaponTranslator

T = WeaponTranslator(load_config().weapons)


def test_same_game_keeps_original_first_then_fallbacks():
    # The remade WaW maps use zombie_* names; other maps get look-alikes.
    out = T.translate("zombie_thompson", "bo1", "bo1")
    assert out[0] == "zombie_thompson" and "ak74u_zm" in out


def test_bo1_upgrade_name_exceptions():
    # Stock BO1: m16_zm -> m16_gl_upgraded_zm, aug_acog_zm -> aug_acog_mk_upgraded_zm,
    # and the remade WaW guns use "<name>_upgraded".
    assert T.split_upgrade("m16_gl_upgraded_zm", "bo1") == ("m16_zm", True)
    assert T.make_upgraded("aug_acog_zm", "bo1") == "aug_acog_mk_upgraded_zm"
    assert T.split_upgrade("zombie_thompson_upgraded", "bo1") == ("zombie_thompson", True)
    assert T.make_upgraded("zombie_stg44", "bo1") == "zombie_stg44_upgraded"
    assert T.make_upgraded("kar98k_scoped_zombie", "bo1") is None


def test_upgraded_weapons_stay_upgraded_first():
    out = T.translate("ray_gun_upgraded_zm", "bo1", "bo1")
    assert out[0] == "ray_gun_upgraded_zm" and "ray_gun_zm" in out


def test_ballistic_knife_variants_are_aliases():
    assert ["knife_ballistic_zm", "knife_ballistic_bowie_zm", "knife_ballistic_sickle_zm"] in T.aliases("bo1")


def test_unknown_weapon_passes_through():
    assert T.translate("zombie_cymbal_monkey", "bo1", "bo1") == ["zombie_cymbal_monkey"]


def test_limit():
    assert len(T.translate("zombie_thompson_upgraded", "bo1", "bo1", limit=2)) == 2


def test_translate_state_rewrites_every_player():
    state = TravelState(
        "bo1", "zombie_moon", "bo1", "zombie_theater",
        players={0: PlayerState(500, [], [WeaponState(["m1911_zm"], 8, 32)], ["m1911_zm"])},
    )
    out = T.translate_state(state)
    assert out.players[0].weapons[0].candidates[0] == "m1911_zm"
    assert out.players[0].current[0] == "m1911_zm"
