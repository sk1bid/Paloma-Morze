#!/usr/bin/env python3
"""Smoke the actual packaged Linux audio helper, not its headless test mode."""
import argparse
import array
import os
from pathlib import Path
import queue
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import threading
import time


def check_versions(text):
    # Inspect dependencies only, not versions this ELF might define/export.
    needs = text.split("Version needs section", 1)
    if len(needs) != 2:
        raise RuntimeError("ELF has no readable version needs section")
    found = {}
    for family, ceiling in (("GLIBC", (2, 35)), ("GLIBCXX", (3, 4, 30))):
        versions = {tuple(map(int, value.split("."))) for value in
                    re.findall(r"\bName: " + family + r"_([0-9.]+)\b", needs[1])}
        if not versions:
            raise RuntimeError(f"No {family} dependency versions found")
        highest = max(versions)
        if highest > ceiling:
            raise RuntimeError(f"{family}_{'.'.join(map(str, highest))} exceeds Ubuntu 22.04 limit "
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


def run_smoke(appimage):
    for tool in ("readelf", "pulseaudio", "pactl", "parec"):
        if not shutil.which(tool):
            raise RuntimeError(f"Missing {tool}; install binutils pulseaudio pulseaudio-utils")
    processes = []
    with tempfile.TemporaryDirectory(prefix="paloma-appimage-audio-") as temporary:
        work = Path(temporary)
        env = dict(os.environ, LC_ALL="C")
        env.pop("LD_PRELOAD", None)
        env.pop("LD_LIBRARY_PATH", None)
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
            print("PASS: packaged helper mode 0755, Ubuntu 22.04 ABI " + str(highest), flush=True)

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
    args = parser.parse_args()
    try:
        run_smoke(args.appimage.resolve(strict=True))
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        sys.exit(f"FAIL: {error}")
