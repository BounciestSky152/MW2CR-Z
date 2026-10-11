from pathlib import Path

from portal_bridge import procs


def fake_pid(root: Path, pid: int, comm: str, cmdline: list[str], environ: dict[str, str]) -> None:
    d = root / str(pid)
    d.mkdir(parents=True)
    (d / "comm").write_text(comm + "\n")
    (d / "cmdline").write_bytes(b"\0".join(a.encode() for a in cmdline) + b"\0")
    (d / "environ").write_bytes(b"".join(f"{k}={v}".encode() + b"\0" for k, v in environ.items()))


def test_list_and_match_wine_processes(tmp_path):
    pfx = "/lib/steamapps/compatdata/42700/pfx/"
    fake_pid(tmp_path, 100, "plutonium-boots", ["Z:\\x\\plutonium-bootstrapper-win32.exe", "t5sp"], {"WINEPREFIX": pfx})
    fake_pid(tmp_path, 101, "wineserver", ["wineserver"], {"WINEPREFIX": pfx})
    fake_pid(tmp_path, 102, "python3", ["python3", "proton", "run", "plutonium-bootstrapper-win32.exe"], {})
    fake_pid(tmp_path, 103, "reaper", ["reaper", "SteamLaunch", "AppId=42700", "--", "x"], {})
    (tmp_path / "self").mkdir()  # non-numeric entries are skipped

    all_procs = procs.list_procs(tmp_path)
    assert {p.pid for p in all_procs} == {100, 101, 102, 103}

    game = procs.find_game(all_procs, ["plutonium-bootstrapper-win32.exe"], "/lib/steamapps/compatdata/42700/pfx")
    assert [p.pid for p in game] == [100]
    assert procs.find_game(all_procs, ["plutonium-bootstrapper-win32.exe"], "/other/pfx") == []
    assert {p.pid for p in procs.find_in_prefix(all_procs, pfx)} == {100, 101}
    assert [p.pid for p in procs.find_steam_launch(all_procs, "42700")] == [103]
    assert procs.find_steam_launch(all_procs, "4270") == []


def test_send_ignores_vanished_processes():
    sent = []

    def kill(pid, sig):
        if pid == 2:
            raise ProcessLookupError
        sent.append(pid)

    procs.send([1, 2, 3], procs.SIGTERM, kill)
    assert sent == [1, 3]
