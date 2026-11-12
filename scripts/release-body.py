#!/usr/bin/env python3
"""Write the user-facing Russian release body, with optional reviewed changes."""
import argparse
from pathlib import Path
import re
from urllib.parse import quote


def release_body(version, repository, notes=""):
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Expected a stable version such as 0.4.24")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Expected repository owner/name")
    base = f"https://github.com/{repository}/releases/download/v{version}"
    installers = [
        ("windows", "Windows x64", f"Paloma-Morse.Setup.{version}.exe"),
        ("linux", "Linux x64", f"Paloma-Morse.{version}.AppImage"),
        ("macos", "macOS 26+ · нативное приложение, Apple Silicon и Intel",
         f"Paloma-Morse-Native-{version}-universal.dmg"),
        ("macos-electron", "macOS 26+ · Electron, только Apple Silicon", f"Paloma-Morse.{version}.dmg"),
    ]
    body = f"Paloma Morse {version}\n\nВыберите установщик для своей системы:\n\n"
    body += "| Система | Установщик |\n| --- | --- |\n"
    body += "\n".join(f'| <a id="download-{anchor}"></a>{label} | [Скачать {Path(name).suffix[1:]}]({base}/{quote(name)}) |'
                      for anchor, label, name in installers)
    body += f"\n\nНа Mac при первой установке выбирайте нативное приложение. Electron оставлен для тех, кто уже им пользуется.\n\n[Как установить](https://github.com/{repository}#скачать-и-установить). Движок уже входит в приложение."
    if notes.strip():
        body += "\n\nЧто изменилось:\n\n" + notes.strip()
    body += """

<details>
<summary>Для чего нужны остальные файлы?</summary>

Для обычной установки достаточно одного файла по ссылкам выше.

- ZIP-архивы macOS нужны для автоматического обновления и установки из архива.
- `latest*.yml` и `.blockmap` используются автоматическим обновлением Electron.
- `appcast.xml` используется автоматическим обновлением нативного приложения macOS.
- `native-manifest.json` и `native-SHA256SUMS.txt` содержат сведения о нативных
  архивах и контрольные суммы для проверки целостности.

</details>
"""
    return body, [name for _, _, name in installers]


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default=(root / "VERSION").read_text().strip())
    parser.add_argument("--repository", required=True)
    parser.add_argument("--notes", type=Path, help="Optional reviewed Russian Markdown changes")
    parser.add_argument("--artifacts", type=Path, help="Require all four installers in this directory")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    notes = args.notes or root / "docs" / "release-notes" / f"{args.version}.md"
    if args.notes and not notes.is_file():
        parser.error(f"Notes file not found: {notes}")
    body, installers = release_body(args.version, args.repository,
                                    notes.read_text() if notes.is_file() else "")
    if args.artifacts:
        missing = [name for name in installers if not (args.artifacts / name).is_file()]
        if missing:
            parser.error("Missing installers: " + ", ".join(missing))
    args.output.write_text(body, encoding="utf-8")


if __name__ == "__main__":
    main()
