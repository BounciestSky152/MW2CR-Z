"""linux-setup against a fake home directory laid out like a real Steam +
Proton + Plutonium install."""
import json
import shutil
from pathlib import Path

import pytest

from portal_bridge import cli
from portal_bridge.config import DEFAULT_CONFIG_DIR, load_config
from portal_bridge.launcher import GameLauncher
from portal_bridge.linux_setup import plan_linux_setup, write_plan


def write(path: Path, text: str = "") -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    return path


def proton(dir: Path, tool_appid: str) -> None:
    write(dir / "proton", "#!/usr/bin/env python3\n")
    write(dir / "toolmanifest.vdf",
          f'"manifest" {{ "version" "2" "commandline" "/proton %verb%" "require_tool_appid" "{tool_appid}" }}')


@pytest.fixture
def home(tmp_path):
    home = tmp_path / "home"
    root = home / ".local/share/Steam"
    lib = tmp_path / "games/SteamLibrary"
    write(root / "steamapps/libraryfolders.vdf",
          f'"libraryfolders" {{ "0" {{ "path" "{root}" }} "1" {{ "path" "{lib}" }} }}')
    (home / ".steam").mkdir(parents=True)
    (home / ".steam/steam").symlink_to(root)
    for app, folder in (("10090", "Call of Duty World at War"), ("42700", "Call of Duty Black Ops")):
        write(lib / f"steamapps/appmanifest_{app}.acf",
              f'"AppState" {{ "appid" "{app}" "StateFlags" "4" "installdir" "{folder}" }}')
        (lib / "steamapps/common" / folder).mkdir(parents=True)
        (lib / f"steamapps/compatdata/{app}/pfx/drive_c/users/steamuser/AppData/Local").mkdir(parents=True)
    # Proton 9 in the main library, wrapped by the sniper runtime.
    proton(root / "steamapps/common/Proton 9.0 (Beta)", "1628350")
    write(root / "steamapps/appmanifest_1628350.acf",
          '"AppState" { "appid" "1628350" "installdir" "SteamLinuxRuntime_sniper" }')
    write(root / "steamapps/common/SteamLinuxRuntime_sniper/_v2-entry-point", "#!/bin/sh\n")
    # WaW's prefix was last set up by Proton 9 (Steam writes this).
    write(lib / "steamapps/compatdata/10090/config_info",
          f"9.0-203\n{root}/steamapps/common/Proton 9.0 (Beta)/files/share/fonts/\n")
    # Plutonium installed inside WaW's prefix only (DeckOps layout).
    pluto = lib / "steamapps/compatdata/10090/pfx/drive_c/users/steamuser/AppData/Local/Plutonium"
    write(pluto / "bin/plutonium-bootstrapper-win32.exe")
    (pluto / "storage").mkdir()
    return home


def plan(home, methods, **kw):
    kw.setdefault("kernel_release", "6.15.2-arch1")
    kw.setdefault("os_release", "ID=arch\n")
    return plan_linux_setup(methods, home=home, env={}, **kw)


def test_plutonium_method(home):
    p = plan(home, {"waw": "plutonium", "bo1": "plutonium"})
    assert not p.problems, p.problems
    waw, bo1 = p.games["waw"], p.games["bo1"]
    pluto = waw["vars"]["pluto_dir"]
    assert pluto.endswith("compatdata/10090/pfx/drive_c/users/steamuser/AppData/Local/Plutonium")
    assert bo1["vars"]["pluto_dir"] == pluto  # one Plutonium install serves both games
    assert waw["launch"][0].endswith("Proton 9.0 (Beta)/proton") and waw["launch"][1] == "run"
    assert waw["launch"][2:] == ["{pluto_dir}/bin/plutonium-bootstrapper-win32.exe", "t4sp", "{game_dir_win}",
                                 "-token", "{token}", "-lan", "{game_args}"]
    assert bo1["launch"][3] == "t5sp"
    assert waw["env"]["STEAM_COMPAT_DATA_PATH"].endswith("compatdata/10090")
    assert "SteamGameId" not in waw["env"]  # Plutonium doesn't use Steam
    assert waw["signal_files"] == ["{pluto_dir}/storage/t4/raw/scriptdata/portal_bridge_travel.txt"]
    assert waw["cwd"] == "{pluto_dir}"
    assert "PROTON_NO_ESYNC" not in bo1["env"]  # kernel has NTSync


def test_bo1_gets_esync_workaround_on_old_kernels(home):
    p = plan(home, {"bo1": "plutonium"}, kernel_release="6.6.30-lts")
    assert p.games["bo1"]["env"]["PROTON_NO_ESYNC"] == "1"
    assert p.games["bo1"]["env"]["PROTON_NO_FSYNC"] == "1"


def test_proton_method_uses_the_runtime_container_and_steam_drm_env(home):
    p = plan(home, {"waw": "proton", "bo1": "proton"})
    waw, bo1 = p.games["waw"], p.games["bo1"]
    assert waw["launch"][0].endswith("SteamLinuxRuntime_sniper/_v2-entry-point")
    assert waw["launch"][1:4] == ["--verb=waitforexitandrun", "--", waw["launch"][3]]
    assert waw["launch"][4] == "waitforexitandrun"
    assert waw["launch"][5:] == ["{game_dir}/CoDWaW.exe", "{game_args}"]
    assert waw["env"]["SteamGameId"] == waw["env"]["SteamAppId"] == "10090"
    assert bo1["cwd"] == "{game_dir}/bin"
    assert bo1["launch"][-4:] == ["{game_dir}/bin/launcher_ldr.exe", "game_mod.dll", "../BlackOps.exe", "{game_args}"]


def test_steam_method_for_waw_and_refused_for_bo1(home):
    p = plan(home, {"waw": "steam", "bo1": "steam"})
    assert p.games["waw"]["launch"] == ["steam", "-applaunch", "10090"]
    assert p.games["waw"]["args_file"].endswith(".local/share/portal_bridge/next_args_waw")
    assert p.games["waw"]["steam_app_id"] == "10090"
    assert "bo1" not in p.games
    assert any("Black Ops" in x for x in p.problems)


def test_missing_plutonium_explains_how_to_get_it(home):
    shutil.rmtree(next(home.parent.glob("games/SteamLibrary/steamapps/compatdata/10090/pfx/drive_c/users/steamuser/AppData/Local/Plutonium")))
    p = plan(home, {"waw": "plutonium"})
    assert "waw" not in p.games
    assert "plutonium-updater" in p.problems[0]


def test_steam_deck_note(home):
    p = plan(home, {"waw": "plutonium"}, os_release="ID=steamos\nVARIANT_ID=steamdeck\n")
    assert any("Steam Deck" in n for n in p.notes)


def config_dir_copy(tmp_path) -> Path:
    cfg = tmp_path / "config"
    shutil.copytree(DEFAULT_CONFIG_DIR, cfg, ignore=shutil.ignore_patterns("bridge.local.json*"))
    return cfg


def test_written_config_launches_correctly(home, tmp_path):
    cfg_dir = config_dir_copy(tmp_path)
    p = plan(home, {"waw": "plutonium", "bo1": "plutonium"}, player_name="Sam")
    write_plan(p, cfg_dir)
    config = load_config(cfg_dir)
    launcher = GameLauncher(config, token=lambda: "0123456789abcdef", log=lambda _: None)
    cmd = launcher.build_command("bo1", "zombie_moon", "PB1|n=1", token="0123456789abcdef")
    bo1_dir = config.games["bo1"].game_dir
    assert cmd[4] == "Z:" + bo1_dir.replace("/", "\\")
    assert cmd[-8:] == ["-lan", "+name", "Sam", "+set", "pb_state", "PB1|n=1", "+devmap", "zombie_moon"]
    assert launcher.wineprefix("waw").endswith("compatdata/10090/pfx")
    assert launcher.cwd("waw").endswith("AppData/Local/Plutonium")
    assert [s.name for s in launcher.signal_paths("bo1")] == ["portal_bridge_travel.txt"]


def test_switching_method_replaces_the_whole_game_section(home, tmp_path):
    cfg_dir = config_dir_copy(tmp_path)
    write_plan(plan(home, {"waw": "plutonium"}), cfg_dir)
    write_plan(plan(home, {"waw": "proton"}), cfg_dir)
    local = json.loads((cfg_dir / "bridge.local.json").read_text())
    assert "pluto_dir" not in local["games"]["waw"]["vars"]
    assert local["games"]["waw"]["signal_files"] == []
    assert (cfg_dir / "bridge.local.json.bak").exists()


def test_cli_setup_then_install_plutonium_then_doctor(home, tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.delenv("XDG_DATA_HOME", raising=False)
    monkeypatch.delenv("STEAM_DIR", raising=False)
    cfg_dir = config_dir_copy(tmp_path)
    assert cli.main(["--config-dir", str(cfg_dir), "linux-setup"]) == 0
    assert cli.main(["--config-dir", str(cfg_dir), "install-plutonium"]) == 0
    pluto = Path(load_config(cfg_dir).games["waw"].vars[0][1])
    assert (pluto / "storage/t4/raw/scripts/sp/portal_bridge.gsc").is_file()
    assert (pluto / "storage/t5/scripts/sp/zom/portal_bridge.gsc").is_file()
    assert (pluto / "storage/t4/raw/scriptdata").is_dir()
    bundle = (pluto / "storage/t4/raw/scripts/sp/portal_bridge.gsc").read_text()
    assert "fs_fopen" in bundle and "maps\\_zombiemode_score::" not in bundle
    capsys.readouterr()
    cli.main(["--config-dir", str(cfg_dir), "doctor"])
    out = capsys.readouterr().out
    assert "[!!] Plutonium script" not in out


def test_wrapper_is_installed_for_steam_method(home, tmp_path):
    cfg_dir = config_dir_copy(tmp_path)
    p = plan(home, {"waw": "steam"})
    write_plan(p, cfg_dir)
    wrapper = home / ".local/share/portal_bridge/pb-wrap.sh"
    assert wrapper.is_file() and wrapper.stat().st_mode & 0o111
