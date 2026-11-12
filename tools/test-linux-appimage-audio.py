#!/usr/bin/env python3
"""Check packaged ELF ABI, actual audio, and Electron rendering on the target host."""
import argparse
import array
import os
import json
from pathlib import Path
import queue
import re
import shutil
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request


def check_versions(text, required=("GLIBC", "GLIBCXX")):
    # Inspect dependencies only, not versions this ELF might define/export.
    needs = text.split("Version needs section", 1)
    if len(needs) != 2:
        raise RuntimeError("ELF has no readable version needs section")
    unsupported = re.findall(r"\bName: (GLIBC_[A-Za-z][A-Za-z0-9_]*)\b", needs[1])
    if unsupported:
        raise RuntimeError(f"Unsupported baseline dependency: {', '.join(sorted(set(unsupported)))}")
    found = {}
    for family, ceiling in (("GLIBC", (2, 28)), ("GLIBCXX", (3, 4, 25))):
        versions = {tuple(map(int, value.split("."))) for value in
                    re.findall(r"\bName: " + family + r"_([0-9.]+)\b", needs[1])}
        if not versions:
            if family in required:
                raise RuntimeError(f"No {family} dependency versions found")
            continue
        highest = max(versions)
        if highest > ceiling:
            raise RuntimeError(f"{family}_{'.'.join(map(str, highest))} exceeds Debian 10 / Astra 1.7 baseline "
                               f"{'.'.join(map(str, ceiling))}")
        found[family] = highest
    return found


def pcm_peak(data):
    samples = array.array("h")
    samples.frombytes(data[:len(data) // 2 * 2])
    if sys.byteorder != "little":
        samples.byteswap()
    return max((abs(value) for value in samples), default=0)


def stop(process):
    if process.poll() is None:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            process.wait(timeout=3)
            return
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=3)


def free_port():
    with socket.socket() as server:
        server.bind(("127.0.0.1", 0))
        return server.getsockname()[1]


def check_packaged_elfs(root, env):
    # Check Electron and every shipped DSO as well as the native helper. A helper
    # built on the baseline cannot compensate for a newer Electron binary.
    count = 0
    for binary in sorted(root.rglob("*")):
        if not binary.is_file():
            continue
        with binary.open("rb") as source:
            if source.read(4) != b"\x7fELF":
                continue
        info = subprocess.run(["readelf", "--version-info", str(binary)], env=env,
                              capture_output=True, text=True, check=True, timeout=10)
        if "Version needs section" not in info.stdout:
            continue  # Static AppImage runtime or an ELF with no versioned imports.
        try:
            check_versions(info.stdout, required=())
        except RuntimeError as error:
            raise RuntimeError(f"{binary.relative_to(root)}: {error}") from error
        count += 1
    if not count:
        raise RuntimeError("No versioned packaged ELF files found")
    print(f"PASS: all {count} packaged ELF files meet GLIBC 2.28 / GLIBCXX 3.4.25 caps", flush=True)


def rendered_app(value):
    return (isinstance(value, dict) and value.get("ready") == "complete"
            and value.get("title") == "Paloma Morse" and value.get("buttons", 0) > 0
            and value.get("text", 0) > 20 and value.get("visible") is True
            and not value.get("loader", True))


def smoke_electron(root, work, env, processes, logs, no_sandbox):
    import websocket

    debug_port, bridge_port = free_port(), 8080
    # The production renderer uses port 8080. Verify it is free before starting
    # rather than connecting the test to an existing user application.
    with socket.socket() as probe:
        try:
            probe.bind(("127.0.0.1", bridge_port))
        except OSError as error:
            raise RuntimeError("Port 8080 is occupied; close the existing app before this smoke") from error
    # The AppImage runtime normally supplies APPDIR. Extraction avoids FUSE,
    # so provide that same contract when invoking the extracted AppRun.
    electron_env = dict(env, PALOMA_AUDIO_PORT=str(bridge_port), APPDIR=str(root))
    electron_env.pop("ELECTRON_RUN_AS_NODE", None)
    electron_log = (work / "electron.log").open("w+")
    logs.append(electron_log)
    command = ["xvfb-run", "-a", str(root / "AppRun"), "--disable-gpu",
               "--remote-debugging-address=127.0.0.1", f"--remote-debugging-port={debug_port}",
               "--remote-allow-origins=http://localhost", f"--user-data-dir={work / 'profile'}"]
    if no_sandbox:
        command.append("--no-sandbox")
    electron = subprocess.Popen(command, env=electron_env, stdout=electron_log,
                                stderr=subprocess.STDOUT, start_new_session=True)
    processes.append(electron)
    deadline = time.monotonic() + 40
    rendered = False
    while time.monotonic() < deadline:
        if electron.poll() is not None:
            raise RuntimeError(f"Packaged Electron exited {electron.returncode} before rendering")
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{debug_port}/json/list", timeout=2) as response:
                pages = json.load(response)
            for page in pages:
                if page.get("type") != "page" or not page.get("url", "").startswith("file:"):
                    continue
                connection = websocket.create_connection(page["webSocketDebuggerUrl"], timeout=3,
                                                         origin="http://localhost")
                try:
                    connection.send(json.dumps({"id": 1, "method": "Runtime.evaluate", "params": {
                        "expression": "({ready:document.readyState,title:document.title,"
                        "buttons:document.querySelectorAll('#root button').length,"
                        "text:document.querySelector('#root')?.innerText.length||0,"
                        "visible:!!document.querySelector('.app-container')&&"
                        "Number(getComputedStyle(document.querySelector('.app-container')).opacity)>0.9,"
                        "loader:!!document.querySelector('.loader-container')})", "returnByValue": True}}))
                    while time.monotonic() < deadline:
                        message = json.loads(connection.recv())
                        if message.get("id") == 1:
                            rendered = rendered_app(message.get("result", {}).get("result", {}).get("value"))
                            break
                finally:
                    connection.close()
                if rendered:
                    break
        except (OSError, ValueError, websocket.WebSocketException):
            pass
        if rendered:
            break
        time.sleep(0.2)
    if not rendered:
        raise RuntimeError("Packaged Electron did not render the React app within 40 seconds")
    # The application's own bridge must also spawn its bundled helper successfully.
    connection = websocket.create_connection(f"ws://127.0.0.1:{bridge_port}", timeout=10)
    try:
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            event = connection.recv()
            if event.startswith("{"):
                message = json.loads(event)
                if message.get("event") == "error":
                    raise RuntimeError(f"Packaged application audio bridge: {message}")
                if message.get("type") == "audio" and message.get("event") == "ready":
                    print("PASS: packaged Electron rendered React and its audio bridge reports ready", flush=True)
                    return
        raise RuntimeError("Packaged application's audio bridge did not become ready")
    finally:
        connection.close()
        stop(electron)


def isolated_environment(work):
    env = dict(os.environ, LC_ALL="C")
    env.pop("LD_PRELOAD", None)
    env.pop("LD_LIBRARY_PATH", None)
    # PulseAudio requires HOME to belong to its user: shared /tmp is rejected.
    # Keep its configuration, Chromium cache, and XDG runtime private as well.
    for variable, directory in (("HOME", "home"), ("XDG_CONFIG_HOME", "config"),
                                ("XDG_CACHE_HOME", "cache"), ("XDG_RUNTIME_DIR", "runtime")):
        target = work / directory
        target.mkdir(mode=0o700)
        env[variable] = str(target)
    return env


def run_smoke(appimage, no_sandbox=False):
    for tool in ("readelf", "pulseaudio", "pactl", "parec", "xvfb-run"):
        if not shutil.which(tool):
            raise RuntimeError(f"Missing {tool}; install binutils pulseaudio pulseaudio-utils xvfb xauth")
    try:
        import websocket  # Debian package python3-websocket
    except ImportError as error:
        raise RuntimeError("Missing websocket-client; install python3-websocket") from error
    processes = []
    with tempfile.TemporaryDirectory(prefix="paloma-appimage-audio-") as temporary:
        work = Path(temporary)
        env = isolated_environment(work)
        logs = []
        try:
            # AppImage extraction executes its own runtime, without mounting FUSE.
            extract_log = (work / "extract.log").open("w+")
            logs.append(extract_log)
            extraction = subprocess.Popen([str(appimage), "--appimage-extract"], cwd=work,
                                          env=env, stdout=extract_log, stderr=subprocess.STDOUT,
                                          start_new_session=True)
            processes.append(extraction)
            extraction.wait(timeout=90)
            if extraction.returncode:
                raise RuntimeError(f"AppImage extraction exited {extraction.returncode}")
            helper = work / "squashfs-root/resources/app.asar.unpacked/native/morze_app"
            if not helper.is_file() or stat.S_IMODE(helper.stat().st_mode) != 0o755:
                raise RuntimeError(f"Packaged helper missing or mode is not 0755: {helper}")
            versions = subprocess.run(["readelf", "--version-info", str(helper)], env=env,
                                      capture_output=True, text=True, check=True, timeout=10)
            highest = check_versions(versions.stdout)
            print("PASS: packaged helper mode 0755, baseline ABI " + str(highest), flush=True)
            check_packaged_elfs(work / "squashfs-root", env)

            # Private server and runtime directory: no user daemon/default-device changes.
            runtime = work / "pulse"
            runtime.mkdir(mode=0o700)
            socket = runtime / "native"
            env.update(PULSE_SERVER=f"unix:{socket}", PULSE_RUNTIME_PATH=str(runtime),
                       PULSE_SINK="paloma_smoke", PULSE_SOURCE="paloma_smoke.monitor")
            pulse_log = (work / "pulse.log").open("w+")
            logs.append(pulse_log)
            pulse = subprocess.Popen([
                "pulseaudio", "--daemonize=no", "--exit-idle-time=-1", "--use-pid-file=no",
                "--disallow-exit", "-n", "--load=module-native-protocol-unix "
                f"socket={socket} auth-anonymous=1",
                "--load=module-null-sink sink_name=paloma_smoke rate=48000 channels=1",
            ], env=env, stdout=pulse_log, stderr=subprocess.STDOUT, start_new_session=True)
            processes.append(pulse)
            deadline = time.monotonic() + 10
            while True:
                probe = subprocess.run(["pactl", "info"], env=env, stdout=subprocess.DEVNULL,
                                       stderr=subprocess.DEVNULL, timeout=2)
                if probe.returncode == 0:
                    break
                if pulse.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError("Private PulseAudio server did not become ready")
                time.sleep(0.1)
            recording = work / "monitor.pcm"
            with recording.open("wb") as audio:
                recorder = subprocess.Popen([
                    "parec", "--raw", "--format=s16le", "--rate=48000", "--channels=1",
                    "--device=paloma_smoke.monitor", "--latency-msec=20",
                ], env=env, stdout=audio, stderr=pulse_log, start_new_session=True)
                processes.append(recorder)
                helper_log = (work / "helper-stderr.log").open("w+")
                logs.append(helper_log)
                engine = subprocess.Popen([str(helper)], env=env, stdin=subprocess.PIPE,
                                          stdout=subprocess.PIPE, stderr=helper_log, text=True,
                                          bufsize=1, start_new_session=True)
                processes.append(engine)
                events = queue.Queue()
                transcript = []

                def collect():
                    for line in engine.stdout:
                        events.put(line.rstrip())
                    events.put(None)

                threading.Thread(target=collect, daemon=True).start()

                def until(predicate, seconds):
                    end = time.monotonic() + seconds
                    while time.monotonic() < end:
                        try:
                            line = events.get(timeout=max(0.001, end - time.monotonic()))
                        except queue.Empty:
                            break
                        if line is None:
                            raise RuntimeError("Helper exited before required event: " + str(transcript[-12:]))
                        transcript.append(line)
                        if line.startswith("AUDIO ERROR") or "TEST MODE" in line:
                            raise RuntimeError("Unexpected helper event: " + line)
                        if predicate(line):
                            return
                    raise RuntimeError("Timed out waiting for helper event: " + str(transcript[-12:]))

                until(lambda line: line.startswith("AUDIO READY 1 "), 15)
                # Wait for the recording stream to be connected before sending sound.
                end = time.monotonic() + 5
                while recording.stat().st_size < 960:
                    if recorder.poll() is not None or time.monotonic() > end:
                        raise RuntimeError("Null-sink monitor recorder did not become ready")
                    time.sleep(0.05)
                engine.stdin.write("S 600 75 6 0 1\nP 751 105 23 30 30 6 0 1 0 ...---...|...---...\n")
                engine.stdin.flush()
                until(lambda line: line == "AUDIO DONE 751 0", 15)
                stop(recorder)
                audio.flush()
                peak = pcm_peak(recording.read_bytes())
                if peak < 100:
                    raise RuntimeError(f"Playback completed but no real audio reached monitor (peak={peak})")
                engine.stdin.close()
                engine.wait(timeout=5)
                if engine.returncode != 0:
                    raise RuntimeError(f"Helper exited {engine.returncode}")
                print(f"PASS: real packaged helper AUDIO READY, P → DONE 0, monitor PCM peak={peak}")
            smoke_electron(work / "squashfs-root", work, env, processes, logs, no_sandbox)
        except BaseException:
            for log in logs:
                log.flush()
                log.seek(0)
                print(f"--- {log.name} (tail) ---\n" + log.read()[-4000:], file=sys.stderr)
            raise
        finally:
            for process in reversed(processes):
                stop(process)
            for log in logs:
                log.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("appimage", type=Path)
    parser.add_argument("--no-sandbox", action="store_true",
                        help="Disable Chromium sandbox only for isolated CI containers")
    args = parser.parse_args()
    try:
        run_smoke(args.appimage.resolve(strict=True), args.no_sandbox)
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        sys.exit(f"FAIL: {error}")
