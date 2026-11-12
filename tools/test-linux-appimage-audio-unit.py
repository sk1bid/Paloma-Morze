#!/usr/bin/env python3
"""Host-independent checks for the packaged Linux smoke's failure gates."""
import importlib.util
import os
import stat
from pathlib import Path
import subprocess
import sys
import unittest
from unittest import mock
import tempfile

spec = importlib.util.spec_from_file_location("smoke", Path(__file__).with_name("test-linux-appimage-audio.py"))
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


def needs(glibc="2.28", glibcxx="3.4.25"):
    return ("Version needs section '.gnu.version_r' contains 2 entries:\n"
            f"Name: GLIBC_{glibc} Flags: none Version: 3\n"
            f"Name: GLIBCXX_{glibcxx} Flags: none Version: 4\n")


class PackagedAudioSmokeTests(unittest.TestCase):
    def test_debian_10_boundary(self):
        self.assertEqual(smoke.check_versions(needs()), {"GLIBC": (2, 28), "GLIBCXX": (3, 4, 25)})

    def test_rejects_newer_runtime_dependencies(self):
        for args in (("2.29", "3.4.25"), ("2.28", "3.4.26"), ("2.35", "3.4.30")):
            with self.subTest(args=args), self.assertRaises(RuntimeError):
                smoke.check_versions(needs(*args))

    def test_uses_numeric_version_order(self):
        self.assertEqual(smoke.check_versions(needs() + "Name: GLIBC_2.9\n")["GLIBC"], (2, 28))

    def test_requires_dependency_sections_and_both_families(self):
        for text in ("", "Name: GLIBC_2.28\nName: GLIBCXX_3.4.25\n",
                     "Version needs section\nName: GLIBC_2.28\n"):
            with self.subTest(text=text), self.assertRaises(RuntimeError):
                smoke.check_versions(text)

    def test_ignores_exported_version_definitions(self):
        text = "Version definition section\nName: GLIBC_2.99\n" + needs()
        self.assertEqual(smoke.check_versions(text)["GLIBC"], (2, 28))

    def test_optional_families_still_reject_newer_electron_dependencies(self):
        self.assertEqual(smoke.check_versions("Version needs section\nName: GLIBC_2.17\n",
                                             required=()), {"GLIBC": (2, 17)})
        with self.assertRaises(RuntimeError):
            smoke.check_versions("Version needs section\nName: GLIBC_2.29\n", required=())

    def test_rejects_non_numeric_new_glibc_abi_dependency(self):
        with self.assertRaises(RuntimeError):
            smoke.check_versions(needs() + "Name: GLIBC_ABI_DT_RELR\n")

    def test_scans_electron_not_just_helper(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "AppRun").write_bytes(b"#!/bin/sh\n")
            (root / "morze_app").write_bytes(b"\x7fELFhelper")
            (root / "paloma").write_bytes(b"\x7fELFelectron")

            def readelf(command, **kwargs):
                return subprocess.CompletedProcess(command, 0, needs(
                    "2.29" if Path(command[-1]).name == "paloma" else "2.28"))

            with mock.patch.object(smoke.subprocess, "run", side_effect=readelf):
                with self.assertRaisesRegex(RuntimeError, "paloma: GLIBC_2.29"):
                    smoke.check_packaged_elfs(root, {})

    def test_render_gate_requires_react_controls_not_initial_loader(self):
        rendered = {"ready": "complete", "title": "Paloma Morse", "buttons": 3,
                    "text": 100, "loader": False, "visible": True}
        self.assertTrue(smoke.rendered_app(rendered))
        for changed in ({"loader": True}, {"buttons": 0}, {"text": 0},
                        {"title": "Error"}, {"ready": "loading"}, {"visible": False}):
            with self.subTest(changed=changed):
                self.assertFalse(smoke.rendered_app(dict(rendered, **changed)))
        self.assertFalse(smoke.rendered_app(None))

    def test_pcm_rejects_silence_and_reads_signed_little_endian(self):
        self.assertEqual(smoke.pcm_peak(bytes(200)), 0)
        self.assertEqual(smoke.pcm_peak(b"\x00\x80\xff\x7f"), 32768)

    def test_smoke_owns_private_home_and_xdg_directories(self):
        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.dict(os.environ, {"HOME": "/tmp", "XDG_RUNTIME_DIR": "/outside",
                                             "LD_LIBRARY_PATH": "/outside", "LD_PRELOAD": "outside.so"}):
                env = smoke.isolated_environment(Path(directory))
            for name in ("HOME", "XDG_RUNTIME_DIR", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
                target = Path(env[name])
                self.assertEqual(target.parent, Path(directory))
                self.assertEqual(target.stat().st_uid, os.getuid())
                self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o700)
            self.assertNotIn("LD_LIBRARY_PATH", env)
            self.assertNotIn("LD_PRELOAD", env)

    def test_cleanup_terminates_owned_process(self):
        child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"], start_new_session=True)
        try:
            smoke.stop(child)
            self.assertIsNotNone(child.poll())
            smoke.stop(child)  # Completed processes need no second signal.
        finally:
            if child.poll() is None:
                child.kill()
                child.wait()


if __name__ == "__main__":
    unittest.main()
