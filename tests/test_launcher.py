import subprocess
from dataclasses import replace

from portal_bridge.config import expand, load_config, wine_path
from portal_bridge.launcher import GameLauncher


def config_with(game, **changes):
    config = load_config()
    config.games[game] = replace(config.games[game], **changes)
    return config


def test_wine_path():
    assert wine_path("/home/me/Games/WaW") == "Z:\\home\\me\\Games\\WaW"
    assert wine_path("C:/Games/WaW") == "C:\\Games\\WaW"


def test_expand_home_vars_and_placeholders(monkeypatch):
    monkeypatch.setenv("HOME", "/home/me")
    monkeypatch.setenv("LIB", "/mnt/lib")
    assert expand("~/x/{map}", "", "zombie_moon") == "/home/me/x/zombie_moon"
    assert expand("{game_dir}/CoDWaW.exe", "$LIB/WaW") == "/mnt/lib/WaW/CoDWaW.exe"
    assert expand("{game_dir_win}", "~/WaW") == "Z:\\home\\me\\WaW"


def test_env_is_expanded_and_passed_to_the_game(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))
    config = config_with(
        "waw",
        game_dir="~/WaW",
        launch=("~/proton/proton", "run", "{game_dir}/CoDWaW.exe", "{state_args}", "+devmap", "{map}"),
        env=(("STEAM_COMPAT_DATA_PATH", "~/compatdata/10090"), ("SteamAppId", "10090")),
    )
    (tmp_path / "WaW").mkdir()
    calls = []
    launcher = GameLauncher(config, popen=lambda cmd, **kw: calls.append((cmd, kw)), log=lambda _: None)
    launcher.launch("waw", "nazi_zombie_factory", "PB1|n=1")

    cmd, kw = calls[0]
    assert cmd[:3] == [f"{tmp_path}/proton/proton", "run", f"{tmp_path}/WaW/CoDWaW.exe"]
    assert cmd[3:6] == ["+set", "pb_state", "PB1|n=1"]
    assert kw["cwd"] == f"{tmp_path}/WaW"
    assert kw["env"]["STEAM_COMPAT_DATA_PATH"] == f"{tmp_path}/compatdata/10090"
    assert kw["env"]["SteamAppId"] == "10090"
    assert "PATH" in kw["env"]  # the rest of the environment is kept


def test_stop_on_linux_kills_and_waits_until_gone():
    config = load_config()
    config.bridge["kill_wait_seconds"] = 2
    alive = {"polls": 3}
    ran, slept = [], []

    def run(cmd, **kw):
        ran.append(cmd)
        if cmd[0] == "pgrep":
            alive["polls"] -= 1
            return subprocess.CompletedProcess(cmd, 0 if alive["polls"] > 0 else 1, "", "")
        return subprocess.CompletedProcess(cmd, 0, "", "")

    launcher = GameLauncher(config, run=run, sleep=slept.append, platform="linux", log=lambda _: None)
    launcher.stop("waw")

    assert ["pkill", "-f", "CoDWaW.exe"] in ran
    assert sum(1 for c in ran if c[0] == "pgrep") == 3
    assert slept == [0.5, 0.5, 2.0]


def test_stop_gives_up_waiting_after_timeout():
    config = load_config()
    config.bridge.update(kill_timeout_seconds=1, kill_wait_seconds=0)
    now = {"t": 0.0}

    def sleep(s):
        now["t"] += s

    launcher = GameLauncher(
        config,
        run=lambda cmd, **kw: subprocess.CompletedProcess(cmd, 0, "", ""),  # never exits
        sleep=sleep, clock=lambda: now["t"], platform="linux", log=lambda _: None,
    )
    launcher.stop("bo1")
    assert 1.0 <= now["t"] <= 2.0


def test_stop_on_windows_uses_taskkill_and_tasklist():
    config = load_config()
    config.bridge["kill_wait_seconds"] = 0
    ran = []

    def run(cmd, **kw):
        ran.append(cmd)
        return subprocess.CompletedProcess(cmd, 0, "INFO: No tasks are running", "")

    GameLauncher(config, run=run, sleep=lambda s: None, platform="win32", log=lambda _: None).stop("bo1")
    assert ran[0] == ["taskkill", "/F", "/IM", "BlackOps.exe"]
    assert ran[1][0] == "tasklist"
