"""Build a mobile PCK in isolation, retaining the desktop texture import settings.

Usage: python dev/build_mobile_pack.py --godot /path/to/godot
Requires Pillow and the matching Godot Web release export template.
"""
import argparse
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from original_cutin_webp import compact

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot", help="Godot editor executable")
    parser.add_argument("--output", type=Path, help="output .pck path")
    parser.add_argument("--keep-project", action="store_true", help="keep the isolated project for import QA")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    work = root / "dev" / "mobile-perf"
    work.mkdir(parents=True, exist_ok=True)
    out = (args.output or work / "phone.pck").resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    project = Path(tempfile.mkdtemp(prefix="phone-assets-", dir=work))
    try:
        for folder in ("art", "scripts"):
            shutil.copytree(root / folder, project / folder)
        for filename in ("project.godot", "duel.tscn", "export_presets.cfg"):
            shutil.copy2(root / filename, project / filename)
        (project / "dev").mkdir()
        for filename in (".gdignore", "mobile_shell.html"):
            shutil.copy2(root / "dev" / filename, project / "dev" / filename)
        count = 0
        for settings in (project / "art").rglob("*.import"):
            value = settings.read_text(encoding="utf-8")
            if 'importer="texture"' not in value or settings.parent.name == "cutins":
                continue
            value, changed = re.subn(r"(?m)^compress/mode=0$", "compress/mode=1", value)
            if changed:
                # Character outlines and small markings benefit from the higher setting.
                quality = "0.90" if settings.parent.name == "art" else "0.95"
                value = re.sub(r"(?m)^compress/lossy_quality=.*$", "compress/lossy_quality=" + quality, value)
                settings.write_text(value, encoding="utf-8")
                count += 1
        def run(*commands):
            proc = subprocess.run([args.godot, "--headless", "--path", str(project), *commands],
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
            if proc.returncode or re.search(r"(?m)^(?:SCRIPT )?ERROR:", proc.stdout):
                raise RuntimeError(proc.stdout[-12000:])
        run("--import")
        compact(project)
        run("--export-pack", "iPhone Safari", str(out))
        print(f"{count} high-quality mobile textures, {out.stat().st_size:,} bytes: {out}")
        if args.keep_project:
            print(f"Import QA project: {project}")
    finally:
        if not args.keep_project:
            shutil.rmtree(project)

if __name__ == "__main__":
    main()

