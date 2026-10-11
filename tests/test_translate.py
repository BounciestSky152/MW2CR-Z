from portal_bridge.config import load_config
from portal_bridge.state import PlayerState, TravelState, WeaponState
from portal_bridge.translate import WeaponTranslator

T = WeaponTranslator(load_config().weapons)


def test_waw_to_bo1_exact_then_fallbacks():
    # BO1's remakes reuse the WaW names.
    assert T.translate("zombie_thompson", "waw", "bo1") == ["zombie_thompson", "ak74u_zm", "mp5k_zm"]


def test_older_waw_names_resolve_too():
    # Nacht/Verruckt use the plain names.
    assert T.translate("thompson", "waw", "bo1")[0] == "zombie_thompson"
    assert T.translate("mg42_bipod", "waw", "bo1") == ["hk21_zm", "rpk_zm"]


def test_bo1_only_weapon_gets_waw_lookalike():
    assert T.translate("thundergun_zm", "bo1", "waw") == ["tesla_gun", "ray_gun"]


def test_upgraded_weapons_stay_upgraded_first():
    out = T.translate("ray_gun_upgraded", "waw", "bo1")
    assert out == ["ray_gun_upgraded_zm", "ray_gun_zm"]
    out = T.translate("ray_gun_upgraded_zm", "bo1", "waw")
    assert out == ["ray_gun_upgraded", "ray_gun"]


def test_bo1_upgrade_name_exceptions():
    # Stock BO1: m16_zm -> m16_gl_upgraded_zm, aug_acog_zm -> aug_acog_mk_upgraded_zm,
    # and the remade WaW guns use WaW's "<name>_upgraded".
    assert T.split_upgrade("m16_gl_upgraded_zm", "bo1") == ("m16_zm", True)
    assert T.make_upgraded("aug_acog_zm", "bo1") == "aug_acog_mk_upgraded_zm"
    assert T.split_upgrade("zombie_thompson_upgraded", "bo1") == ("zombie_thompson", True)
    assert T.make_upgraded("zombie_stg44", "bo1") == "zombie_stg44_upgraded"
    assert T.make_upgraded("kar98k_scoped_zombie", "bo1") is None
    assert T.translate("m16_gl_upgraded_zm", "bo1", "waw")[0] == "zombie_bar_upgraded"


def test_ballistic_knife_variants_are_aliases():
    assert ["knife_ballistic_zm", "knife_ballistic_bowie_zm", "knife_ballistic_sickle_zm"] in T.aliases("bo1")


def test_same_game_keeps_original_first():
    assert T.translate("zombie_mp40", "waw", "waw")[:2] == ["zombie_mp40", "mp40"]


def test_unknown_weapon_passes_through():
    assert T.translate("zombie_cymbal_monkey", "waw", "bo1") == ["zombie_cymbal_monkey"]


def test_limit():
    assert len(T.translate("zombie_thompson_upgraded", "waw", "bo1", limit=4)) == 4


def test_translate_state_rewrites_every_player():
    state = TravelState(
        "waw", "nazi_zombie_factory", "bo1", "zombie_theater",
        players={0: PlayerState(500, [], [WeaponState(["zombie_colt"], 8, 32)], ["zombie_colt"])},
    )
    out = T.translate_state(state)
    assert out.players[0].weapons[0].candidates == ["m1911_zm"]
    assert out.players[0].current == ["m1911_zm"]
    assert state.players[0].current == ["zombie_colt"]  # original untouched


def test_aliases_only_list_real_names():
    groups = T.aliases("waw")
    assert ["zombie_thompson", "thompson"] in groups
    assert all("ak74u_zm" not in g for g in groups)
