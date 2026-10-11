from pathlib import Path

from portal_bridge import steam

LIBRARYFOLDERS = """
"libraryfolders"
{
	"0"
	{
		"path"		"{root}"
		"label"		""
		"apps"
		{
			"228980"		"1"
		}
	}
	"1"
	{
		"path"		"{lib}"
		"apps"
		{
			"10090"		"8000000000"
			"42700"		"9000000000"
		}
	}
}
"""

CONFIG_VDF = """
"InstallConfigStore"
{
	"Software"
	{
		"valve"
		{
			"Steam"
			{
				"CompatToolMapping"
				{
					"0" { "name" "proton_experimental" "config" "" "priority" "75" }
					"42700" { "name" "GE-Proton9-20" "config" "" "priority" "250" }
				}
			}
		}
	}
}
"""


def write(path: Path, text: str = "") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def fake_proton(dir: Path, internal: str, display: str) -> None:
    write(dir / "proton", "#!/usr/bin/env python3\n")
    write(dir / "compatibilitytool.vdf",
          f'"compatibilitytools" {{ "compat_tools" {{ "{internal}" {{ "install_path" "." "display_name" "{display}" }} }} }}')


def make_steam(home: Path) -> tuple[Path, Path]:
    root = home / ".local/share/Steam"
    lib = home / "Games/SteamLibrary"
    write(root / "steamapps/libraryfolders.vdf",
          LIBRARYFOLDERS.replace("{root}", str(root)).replace("{lib}", str(lib)))
    write(root / "config/config.vdf", CONFIG_VDF)
    (home / ".steam").mkdir()
    (home / ".steam/steam").symlink_to(root)
    write(lib / "steamapps/appmanifest_10090.acf",
          '"AppState" { "appid" "10090" "installdir" "Call of Duty World at War" }')
    write(lib / "steamapps/appmanifest_42700.acf",
          '"AppState" { "appid" "42700" "installdir" "Call of Duty Black Ops" }')
    fake_proton(root / "steamapps/common/Proton 8.0", "proton_8", "Proton 8.0-5")
    fake_proton(root / "steamapps/common/Proton - Experimental", "proton_experimental", "Proton - Experimental")
    fake_proton(lib / "steamapps/common/Proton 9.0 (Beta)", "proton_9", "Proton 9.0-4")
    fake_proton(root / "compatibilitytools.d/GE-Proton9-20", "GE-Proton9-20", "GE-Proton9-20")
    return root, lib


def test_parse_vdf_handles_both_libraryfolders_formats():
    new = steam.parse_vdf('"libraryfolders" { "0" { "path" "/a" } }')
    old = steam.parse_vdf('"LibraryFolders" { "TimeNextStatsReport" "1" "1" "/b" }')
    assert new == {"libraryfolders": {"0": {"path": "/a"}}}
    assert old["LibraryFolders"]["1"] == "/b"


def test_parse_vdf_escapes_and_comments():
    data = steam.parse_vdf('// comment\n"a" { "b" "x\\\\y \\"q\\"" "c" "{" }')
    assert data == {"a": {"b": 'x\\y "q"', "c": "{"}}


def test_finds_steam_once_through_symlinks(tmp_path):
    root, lib = make_steam(tmp_path)
    installs = steam.find_steam_roots(tmp_path, {})
    assert len(installs) == 1
    assert installs[0].root == root.resolve()
    assert installs[0].libraries == [root.resolve(), lib.resolve()]


def test_finds_games_in_secondary_library(tmp_path):
    _, lib = make_steam(tmp_path)
    s = steam.find_steam_roots(tmp_path, {})[0]
    waw = steam.find_game(s, "waw")
    assert waw.game_dir == lib.resolve() / "steamapps/common/Call of Duty World at War"
    assert waw.compatdata == lib.resolve() / "steamapps/compatdata/10090"
    assert steam.find_game(s, "bo1").app_id == "42700"


def test_picks_the_proton_steam_uses_for_each_game(tmp_path):
    make_steam(tmp_path)
    s = steam.find_steam_roots(tmp_path, {})[0]
    protons = steam.find_protons(s)
    assert {p.name for p in protons} == {"proton_8", "proton_experimental", "proton_9", "GE-Proton9-20"}
    assert steam.pick_proton(s, protons, "42700").name == "GE-Proton9-20"   # per-game override
    assert steam.pick_proton(s, protons, "10090").name == "proton_experimental"  # global default


def test_newest_numbered_proton_when_steam_has_no_preference(tmp_path):
    root, _ = make_steam(tmp_path)
    (root / "config/config.vdf").unlink()
    s = steam.find_steam_roots(tmp_path, {})[0]
    assert steam.pick_proton(s, steam.find_protons(s), "10090").name == "GE-Proton9-20"


def test_flatpak_steam_is_flagged(tmp_path):
    root = tmp_path / ".var/app/com.valvesoftware.Steam/.local/share/Steam"
    (root / "steamapps").mkdir(parents=True)
    installs = steam.find_steam_roots(tmp_path, {})
    assert installs[0].flatpak


def test_uninstalled_manifest_is_ignored(tmp_path):
    _, lib = make_steam(tmp_path)
    write(lib / "steamapps/appmanifest_10090.acf",
          '"AppState" { "appid" "10090" "StateFlags" "1" "installdir" "Call of Duty World at War" }')
    s = steam.find_steam_roots(tmp_path, {})[0]
    assert steam.find_game(s, "waw") is None


def test_capitalised_steamapps_and_config_libraryfolders_fallback(tmp_path):
    root = tmp_path / "Steam"
    lib = tmp_path / "lib2"
    (root / "SteamApps").mkdir(parents=True)
    write(root / "config/libraryfolders.vdf", f'"LibraryFolders" {{ "1" "{lib}" }}')
    (lib / "steamapps").mkdir(parents=True)
    s = steam.find_steam_roots(tmp_path, {"STEAM_DIR": str(root)})[0]
    assert s.libraries == [root.resolve(), lib.resolve()]


def test_flatpak_library_paths_are_remapped(tmp_path):
    root = tmp_path / ".var/app/com.valvesoftware.Steam/.local/share/Steam"
    # Written from inside the sandbox, where $HOME/.local/share/Steam is the Flatpak dir.
    write(root / "steamapps/libraryfolders.vdf",
          f'"libraryfolders" {{ "0" {{ "path" "{tmp_path}/.local/share/Steam" }} "1" {{ "path" "/mnt/games" }} }}')
    s = steam.find_steam_roots(tmp_path, {})[0]
    assert s.kind == "flatpak"
    assert s.libraries[0] == root.resolve()
    assert Path("/mnt/games") in s.libraries
    assert root.resolve() in s.libraries and tmp_path / ".local/share/Steam" not in s.libraries
    assert s.launch_prefix() == ["flatpak", "run", "com.valvesoftware.Steam"]


def test_prefix_config_info_beats_steam_settings(tmp_path):
    root, lib = make_steam(tmp_path)
    s = steam.find_steam_roots(tmp_path, {})[0]
    cd = lib / "steamapps/compatdata/42700"
    (cd / "pfx").mkdir(parents=True)
    write(cd / "config_info", f"8.0-5\n{root}/steamapps/common/Proton 8.0/files/share/fonts/\n")
    protons = steam.find_protons(s)
    assert steam.pick_proton(s, protons, "42700", cd).name == "proton_8"


def test_valve_proton_names_map_to_directories(tmp_path):
    root, _ = make_steam(tmp_path)
    # Valve's own builds have no compatibilitytool.vdf.
    (root / "steamapps/common/Proton 8.0/compatibilitytool.vdf").unlink()
    write(root / "steamapps/common/Proton 10.0/proton")
    s = steam.find_steam_roots(tmp_path, {})[0]
    protons = steam.find_protons(s)
    assert steam._match_tool_name("proton_8", protons).path.name == "Proton 8.0"
    assert steam._match_tool_name("proton_10", protons).path.name == "Proton 10.0"


def test_compatdata_prefers_the_games_own_library(tmp_path):
    root, lib = make_steam(tmp_path)
    for base in (root, lib):
        (base / "steamapps/compatdata/10090/pfx").mkdir(parents=True)
    s = steam.find_steam_roots(tmp_path, {})[0]
    assert steam.find_game(s, "waw").compatdata == lib.resolve() / "steamapps/compatdata/10090"


def test_runtime_entry_point_from_toolmanifest(tmp_path):
    root, _ = make_steam(tmp_path)
    p9 = root / "steamapps/common/Proton 8.0"
    write(p9 / "toolmanifest.vdf", '"manifest" { "require_tool_appid" "1628350" }')
    write(root / "steamapps/appmanifest_1628350.acf", '"AppState" { "installdir" "SteamLinuxRuntime_sniper" }')
    write(root / "steamapps/common/SteamLinuxRuntime_sniper/_v2-entry-point", "#!/bin/sh\n")
    s = steam.find_steam_roots(tmp_path, {})[0]
    proton = next(p for p in steam.find_protons(s) if p.path.name == "Proton 8.0")
    assert steam.runtime_entry_point(s, proton) == s.root / "steamapps/common/SteamLinuxRuntime_sniper/_v2-entry-point"


def test_plutonium_candidates_and_prefix_helpers(tmp_path):
    pluto = tmp_path / ".wine/drive_c/users/me/AppData/Local/Plutonium"
    write(pluto / "bin/plutonium-bootstrapper-win32.exe")
    assert steam.plutonium_candidates(tmp_path, [], []) == [pluto]
    assert steam.wine_prefix_of(pluto) == tmp_path / ".wine"
    assert steam.compatdata_of(tmp_path / ".wine") is None
    assert steam.compatdata_of(Path("/l/steamapps/compatdata/10090/pfx")) == Path("/l/steamapps/compatdata/10090")


def test_kernel_and_deck_detection():
    assert steam.kernel_has_ntsync("6.14.0-1-default")
    assert not steam.kernel_has_ntsync("6.13.9")
    assert not steam.kernel_has_ntsync("5.15.0-112-generic")
    assert steam.is_steam_deck('NAME="SteamOS"\nID=steamos\nVARIANT_ID=steamdeck\n')
