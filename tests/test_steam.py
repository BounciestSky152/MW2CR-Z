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


def write(path: Path, text: str) -> None:
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
    installs = steam.find_steam_roots(tmp_path)
    assert len(installs) == 1
    assert installs[0].root == root.resolve()
    assert installs[0].libraries == [root.resolve(), lib.resolve()]


def test_finds_games_in_secondary_library(tmp_path):
    _, lib = make_steam(tmp_path)
    s = steam.find_steam_roots(tmp_path)[0]
    waw = steam.find_game(s, "waw")
    assert waw.game_dir == lib.resolve() / "steamapps/common/Call of Duty World at War"
    assert waw.compatdata == lib.resolve() / "steamapps/compatdata/10090"
    assert steam.find_game(s, "bo1").app_id == "42700"


def test_picks_the_proton_steam_uses_for_each_game(tmp_path):
    make_steam(tmp_path)
    s = steam.find_steam_roots(tmp_path)[0]
    protons = steam.find_protons(s)
    assert {p.name for p in protons} == {"proton_8", "proton_experimental", "proton_9", "GE-Proton9-20"}
    assert steam.pick_proton(s, protons, "42700").name == "GE-Proton9-20"   # per-game override
    assert steam.pick_proton(s, protons, "10090").name == "proton_experimental"  # global default


def test_newest_numbered_proton_when_steam_has_no_preference(tmp_path):
    root, _ = make_steam(tmp_path)
    (root / "config/config.vdf").unlink()
    s = steam.find_steam_roots(tmp_path)[0]
    assert steam.pick_proton(s, steam.find_protons(s), "10090").name == "GE-Proton9-20"


def test_flatpak_steam_is_flagged(tmp_path):
    root = tmp_path / ".var/app/com.valvesoftware.Steam/.local/share/Steam"
    (root / "steamapps").mkdir(parents=True)
    installs = steam.find_steam_roots(tmp_path)
    assert installs[0].flatpak
