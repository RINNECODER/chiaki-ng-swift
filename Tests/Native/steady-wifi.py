"""Verify that the session pipe owns AWDL changes, including on app exit."""

import os
from pathlib import Path
import select
import subprocess
import tempfile


helper = Path(__file__).resolve().parents[2] / "Scripts/SteadyWiFi/hold-awdl.sh"

with tempfile.TemporaryDirectory() as temp:
    root = Path(temp)
    state = root / "state"
    interface = root / "ifconfig"
    interface.write_text("""#!/bin/sh
case "$2" in
    '') printf 'awdl0: flags=<%s,BROADCAST> mtu 1500\\n' "$(cat "$AWDL_STATE")" ;;
    down|up) printf '%s' "$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')" > "$AWDL_STATE"
             printf '%s\\n' "$2" ;;
esac
""")
    interface.chmod(0o700)
    env = {**os.environ, "AWDL_STATE": str(state)}
    command = ["/bin/bash", "-c", 'source "$1" && hold_steady_wifi "$2" "$3"',
               "test", str(helper), str(interface), str(root / "lock")]

    state.write_text("UP")
    reader, writer = os.pipe()
    with os.fdopen(writer, "wb") as session, subprocess.Popen(
        command, stdin=reader, stdout=subprocess.PIPE, env=env,
    ) as process:
        os.close(reader)
        try:
            assert select.select([process.stdout], [], [], 5)[0], "Helper did not pause AWDL"
            assert process.stdout.readline() == b"down\n"
            assert state.read_text() == "DOWN"
            competing = subprocess.run(command, input=b"", capture_output=True, env=env, timeout=5)
            assert competing.returncode != 0, "A second helper acquired the active lease"
            assert state.read_text() == "DOWN"
            state.write_text("UP")
            assert select.select([process.stdout], [], [], 5)[0], "AWDL resumed during the lease"
            assert process.stdout.readline() == b"down\n"
            assert state.read_text() == "DOWN"
        finally:
            session.close()
            restoration_output = process.communicate(timeout=5)[0]
        assert restoration_output == b"up\n"
        assert process.returncode == 0
        assert state.read_text() == "UP", "An app exit left AWDL disabled"

    state.write_text("DOWN")
    already_down = subprocess.run(command, input=b"", capture_output=True, env=env, timeout=5)
    assert already_down.returncode == 0
    assert not already_down.stdout
    assert state.read_text() == "DOWN", "The helper enabled AWDL without owning the change"

print("Steady Wi-Fi lease, restoration, and pre-existing interface state passed")
