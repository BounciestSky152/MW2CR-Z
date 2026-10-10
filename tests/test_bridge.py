import json
import shutil

from portal_bridge.bridge import Bridge
from portal_bridge.config import DEFAULT_CONFIG_DIR, load_config
from portal_bridge.launcher import GameLauncher
from portal_bridge.logwatch import LogTailer
from portal_bridge.state import decode

LINE = (
    "  0:42 [PORTAL_BRIDGE] TRAVEL PB1|n=77|src=waw:nazi_zombie_factory|dst=bo1:zombie_theater|r=9"
    "|p0=3000~specialty_armorvest~zombie_thompson@20@140~zombie_thompson"
)


class FakeLauncher(GameLauncher):
    def __init__(self, config):
        super().__init__(config, dry_run=True, log=lambda _: None)
        self.calls = []

    def stop(self, game):
        self.calls.append(("stop", game))

    def launch(self, game, map_id, state=None):
        self.calls.append(("launch", game, map_id, state))


def make_bridge(tmp_path):
    config = load_config()
    for game in config.games.values():
        object.__setattr__(game, "logs", (str(tmp_path / f"{game.id}.log"),))
    launcher = FakeLauncher(config)
    return Bridge(config, launcher, log=lambda _: None), launcher


def test_travel_swaps_games_and_translates(tmp_path):
    bridge, launcher = make_bridge(tmp_path)
    assert bridge.handle_line(LINE)

    assert launcher.calls[0] == ("stop", "waw")
    kind, game, map_id, payload = launcher.calls[-1]
    assert (kind, game, map_id) == ("launch", "bo1", "zombie_theater")
    state = decode(payload)
    assert state.round == 9
    assert state.players[0].weapons[0].candidates[0] == "thompson_zm"
    assert state.players[0].perks == ["specialty_armorvest"]


def test_same_request_is_only_handled_once(tmp_path):
    bridge, launcher = make_bridge(tmp_path)
    assert bridge.handle_line(LINE)
    assert not bridge.handle_line(LINE)
    assert sum(1 for c in launcher.calls if c[0] == "launch") == 1


def test_unknown_destination_is_ignored(tmp_path):
    bridge, launcher = make_bridge(tmp_path)
    assert not bridge.handle_line(LINE.replace("zombie_theater", "zombie_nowhere"))
    assert launcher.calls == []


def test_unrelated_lines_are_ignored(tmp_path):
    bridge, _ = make_bridge(tmp_path)
    assert not bridge.handle_line("Loading fastfile 'nazi_zombie_factory'")


def test_poll_picks_request_from_log(tmp_path):
    bridge, launcher = make_bridge(tmp_path)
    log = tmp_path / "waw.log"
    log.write_text("old stuff\n" + LINE.replace("n=77", "n=1") + "\n")
    bridge.tailer.prime()  # history must not replay
    assert bridge.poll_once() == 0

    with log.open("a") as f:
        f.write("noise\n" + LINE)  # no trailing newline yet
    assert bridge.poll_once() == 0
    with log.open("a") as f:
        f.write("\n")
    assert bridge.poll_once() == 1
    assert launcher.calls[-1][1:3] == ("bo1", "zombie_theater")


def test_tailer_handles_truncation(tmp_path):
    log = tmp_path / "console.log"
    log.write_text("a\nb\n")
    tailer = LogTailer([log])
    tailer.prime()
    log.write_text("c\n")  # game relaunched and recreated the log
    assert tailer.poll() == ["c"]


def test_build_command_expands_placeholders():
    config = load_config()
    launcher = GameLauncher(config, dry_run=True)
    cmd = launcher.build_command("waw", "nazi_zombie_factory", "PB1|n=1")
    assert cmd[0].endswith("/CoDWaW.exe")
    assert cmd[-2:] == ["+devmap", "nazi_zombie_factory"]
    i = cmd.index("pb_state")
    assert cmd[i - 1:i + 2] == ["+set", "pb_state", "PB1|n=1"]
    assert "pb_state" not in launcher.build_command("waw", "nazi_zombie_factory")


def test_local_override_is_merged(tmp_path):
    for name in ("bridge.json", "maps.json", "weapons.json"):
        shutil.copy(DEFAULT_CONFIG_DIR / name, tmp_path / name)
    (tmp_path / "bridge.local.json").write_text(json.dumps({"games": {"bo1": {"game_dir": "D:/BO1"}}}))
    config = load_config(tmp_path)
    assert config.games["bo1"].game_dir == "D:/BO1"
    assert config.games["bo1"].process_names == ("BlackOps.exe",)
