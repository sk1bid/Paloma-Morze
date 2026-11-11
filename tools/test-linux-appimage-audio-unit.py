#!/usr/bin/env python3
"""Host-independent checks for the packaged Linux smoke's failure gates."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest

spec = importlib.util.spec_from_file_location("smoke", Path(__file__).with_name("test-linux-appimage-audio.py"))
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


def needs(glibc="2.35", glibcxx="3.4.30"):
    return ("Version needs section '.gnu.version_r' contains 2 entries:\n"
            f"Name: GLIBC_{glibc} Flags: none Version: 3\n"
            f"Name: GLIBCXX_{glibcxx} Flags: none Version: 4\n")


class PackagedAudioSmokeTests(unittest.TestCase):
    def test_ubuntu_2204_boundary(self):
        self.assertEqual(smoke.check_versions(needs()), {"GLIBC": (2, 35), "GLIBCXX": (3, 4, 30)})

    def test_rejects_newer_runtime_dependencies(self):
        for args in (("2.36", "3.4.30"), ("2.35", "3.4.31"), ("2.39", "3.4.32")):
            with self.subTest(args=args), self.assertRaises(RuntimeError):
                smoke.check_versions(needs(*args))

    def test_uses_numeric_version_order(self):
        self.assertEqual(smoke.check_versions(needs() + "Name: GLIBC_2.9\n")["GLIBC"], (2, 35))

    def test_requires_dependency_sections_and_both_families(self):
        for text in ("", "Name: GLIBC_2.35\nName: GLIBCXX_3.4.30\n",
                     "Version needs section\nName: GLIBC_2.35\n"):
            with self.subTest(text=text), self.assertRaises(RuntimeError):
                smoke.check_versions(text)

    def test_ignores_exported_version_definitions(self):
        text = "Version definition section\nName: GLIBC_2.99\n" + needs()
        self.assertEqual(smoke.check_versions(text)["GLIBC"], (2, 35))

    def test_pcm_rejects_silence_and_reads_signed_little_endian(self):
        self.assertEqual(smoke.pcm_peak(bytes(200)), 0)
        self.assertEqual(smoke.pcm_peak(b"\x00\x80\xff\x7f"), 32768)

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
