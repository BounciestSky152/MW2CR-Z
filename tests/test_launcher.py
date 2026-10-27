import subprocess
from dataclasses import replace

from portal_bridge.config import expand, load_config, wine_path
from portal_bridge.launcher import GameLauncher


def config_with(game, **changes):
    config = load_config()
    changes.setdefault("cwd", "{game_dir}")
    config.games[game] = replace(config.games[game], **changes)
    return config


def test_wine_path():
    assert wine_path("/home/me/Games/BO1") == "Z:\\home\\me\\Games\\BO1"
    assert wine_path("C:/Games/BO1") == "C:\\Games\\BO1"


def test_expand_home_vars_and_placeholders(monkeypatch):
    monkeypatch.setenv("HOME", "/home/me")
    monkeypatch.setenv("LIB", "/mnt/lib")
    assert expand("~/x/{map}", "", "zombie_moon") == "/home/me/x/zombie_moon"
    assert expand("{game_dir}/BlackOps.exe", "$LIB/BO1") == "/mnt/lib/BO1/BlackOps.exe"
    assert expand("{game_dir_win}", "~/BO1") == "Z:\\home\\me\\BO1"


def test_env_is_expanded_and_passed_to_the_game(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))
    config = config_with(
        "bo1",
        game_dir="~/BO1",
        launch=("~/proton/proton", "run", "{game_dir}/BlackOps.exe", "{state_args}", "+devmap", "{map}"),
        env=(("STEAM_COMPAT_DATA_PATH", "~/compatdata/42700"), ("SteamAppId", "42700")),
    )
    (tmp_path / "BO1").mkdir()
    calls = []
    launcher = GameLauncher(config, popen=lambda cmd, **kw: calls.append((cmd, kw)), log=lambda _: None)
    launcher.launch("bo1", "zombie_moon", "PB1|n=1")

    cmd, kw = calls[0]
    assert cmd[:3] == [f"{tmp_path}/proton/proton", "run", f"{tmp_path}/BO1/BlackOps.exe"]
    assert cmd[3:6] == ["+set", "pb_state", "PB1|n=1"]
    assert kw["cwd"] == f"{tmp_path}/BO1"
    assert kw["env"]["STEAM_COMPAT_DATA_PATH"] == f"{tmp_path}/compatdata/42700"
    assert kw["env"]["SteamAppId"] == "42700"
    assert "PATH" in kw["env"]  # the rest of the environment is kept


def fake_proc(pid, comm, prefix=None, cmdline=()):
    from portal_bridge.procs import Proc
    return Proc(pid, comm[:15], tuple(cmdline), prefix)


def proton_config(**bridge):
    config = config_with(
        "bo1",
        env=(("STEAM_COMPAT_DATA_PATH", "/lib/steamapps/compatdata/42700/"),),
        process_names=("BlackOps.exe",),
    )
    config.bridge.update({"kill_wait_seconds": 0, **bridge})
    return config


def test_wineprefix_is_derived_from_proton_env():
    launcher = GameLauncher(proton_config(), log=lambda _: None)
    assert launcher.wineprefix("bo1") == "/lib/steamapps/compatdata/42700/pfx"


def test_stop_on_linux_only_kills_the_game_in_its_own_prefix():
    pfx = "/lib/steamapps/compatdata/42700/pfx/"
    world = [
        fake_proc(10, "BlackOps.exe", pfx),
        fake_proc(11, "wineserver", pfx),
        fake_proc(12, "BlackOps.exe", "/home/me/other-prefix"),  # someone else's copy
        fake_proc(13, "python3", None, ["python3", "proton", "run", "BlackOps.exe"]),
    ]
    killed = []

    def kill(pid, sig):
        killed.append((pid, sig))
        world[:] = [p for p in world if p.pid != pid]
        if pid == 10:  # wineserver exits once its last client is gone
            world[:] = [p for p in world if p.pid != 11]

    launcher = GameLauncher(proton_config(), platform="linux", list_procs=lambda: list(world),
                            kill=kill, sleep=lambda s: None, log=lambda _: None)
    launcher.stop("bo1")
    assert [pid for pid, _ in killed] == [10]
    assert {p.pid for p in world} == {12, 13}


def test_stop_waits_for_steam_reaper_then_escalates():
    pfx = "/lib/steamapps/compatdata/42700/pfx"
    reaper = fake_proc(20, "reaper", None, ["reaper", "SteamLaunch", "AppId=42700", "--", "x"])
    world = [fake_proc(21, "BlackOps.exe", pfx), fake_proc(22, "services.exe", pfx), reaper]
    now = {"t": 0.0}
    killed = []

    def kill(pid, sig):
        killed.append((pid, sig))
        if pid == 21:
            world.remove(world[0])  # game dies, services.exe hangs around

    def sleep(s):
        now["t"] += s
        if now["t"] > 3 and reaper in world:
            world.remove(reaper)  # Steam notices after a while

    config = proton_config(kill_timeout_seconds=10)
    config.games["bo1"] = replace(config.games["bo1"], steam_app_id="42700")
    launcher = GameLauncher(config, platform="linux", list_procs=lambda: list(world), kill=kill,
                            sleep=sleep, clock=lambda: now["t"], log=lambda _: None)
    launcher.stop("bo1")

    import signal
    assert (21, signal.SIGTERM) in killed
    assert (22, signal.SIGKILL) in killed  # escalation after the timeout
    assert reaper not in world


def test_stop_on_windows_uses_taskkill_and_tasklist():
    config = load_config()
    config.bridge["kill_wait_seconds"] = 0
    ran = []

    def run(cmd, **kw):
        ran.append(cmd)
        return subprocess.CompletedProcess(cmd, 0, "INFO: No tasks are running", "")

    GameLauncher(config, run=run, sleep=lambda s: None, platform="win32", log=lambda _: None).stop("bo1")
    assert ["taskkill", "/F", "/IM", "BlackOps.exe"] in ran
    assert ["taskkill", "/F", "/IM", "launcher_ldr.exe"] in ran
    assert any(c[0] == "tasklist" for c in ran)


def test_game_args_token_vars_and_cwd(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))
    config = config_with(
        "bo1",
        game_dir="~/BO1",
        vars=(("pluto", "~/pfx/Plutonium"),),
        cwd="{pluto}",
        launch=("proton", "run", "{pluto}/bin/plutonium-bootstrapper-win32.exe", "t5sp", "{game_dir_win}",
                "-token", "{token}", "-lan", "{game_args}"),
        game_args=("{state_args}", "+devmap", "{map}"),
    )
    launcher = GameLauncher(config, token=lambda: "abcd1234abcd1234", log=lambda _: None)
    cmd = launcher.build_command("bo1", "zombie_moon", "PB1|n=1", token="abcd1234abcd1234")
    assert cmd == ["proton", "run", f"{tmp_path}/pfx/Plutonium/bin/plutonium-bootstrapper-win32.exe", "t5sp",
                   "Z:" + str(tmp_path).replace("/", "\\") + "\\BO1", "-token", "abcd1234abcd1234", "-lan",
                   "+set", "pb_state", "PB1|n=1", "+devmap", "zombie_moon"]
    assert launcher.cwd("bo1") == f"{tmp_path}/pfx/Plutonium"


def test_args_file_method_keeps_args_off_the_command_line(tmp_path):
    config = config_with(
        "bo1",
        game_dir=str(tmp_path),
        launch=("steam", "-applaunch", "42700"),
        game_args=("{state_args}", "+devmap", "{map}"),
        args_file=str(tmp_path / "next_args"),
    )
    calls = []
    launcher = GameLauncher(config, popen=lambda cmd, **kw: calls.append(cmd), platform="linux", log=lambda _: None)
    launcher.launch("bo1", "zombie_moon", "PB1|n=1|x=a~b")
    assert calls == [["steam", "-applaunch", "42700"]]
    assert (tmp_path / "next_args").read_text() == "+set\npb_state\nPB1|n=1|x=a~b\n+devmap\nzombie_moon\n"


def test_game_output_goes_to_a_log_file(tmp_path):
    config = config_with("bo1", game_dir=str(tmp_path), launch=("wine", "x.exe"))
    config.bridge["game_log_dir"] = str(tmp_path / "logs")
    seen = {}

    def popen(cmd, **kw):
        seen.update(kw)
        kw["stdout"].write(b"wine noise\n")

    GameLauncher(config, popen=popen, platform="linux", log=lambda _: None).launch("bo1", "zombie_moon")
    assert seen["stderr"] is subprocess.STDOUT
    assert (tmp_path / "logs/bo1.log").read_bytes() == b"wine noise\n"
