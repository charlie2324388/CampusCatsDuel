"""Add mobile installation support to an existing Godot web export.

Usage: python dev/prepare_mobile_site.py <web-export-directory> <release-ZIP-with-licenses>
"""
import argparse
import json
import re
import shutil
import zipfile
from build_mobile_cache import prepare_asset_cache
from pathlib import Path

def prepare_site(folder, notices_archive):
    root = Path(__file__).resolve().parents[1]
    folder = folder.resolve(strict=True)
    page = folder / "index.html"
    html = page.read_text(encoding="utf-8")
    marker = "<!-- mobile-install -->"
    metadata = ('<link rel="manifest" href="./manifest.webmanifest">\n'
                '<link rel="apple-touch-icon" href="./app-icon.png">\n'
                '<link rel="icon" type="image/png" href="./app-icon.png">')
    if marker not in html and metadata not in html:
        raise ValueError("Export the project with its mobile HTML shell first.")
    manifest = {
        "id": "./", "name": "课间猫擂台", "short_name": "猫擂台", "lang": "zh-CN",
        "start_url": "./", "scope": "./", "display": "standalone",
        "display_override": ["fullscreen", "standalone"], "orientation": "landscape",
        "background_color": "#101e28", "theme_color": "#101e28",
        "icons": [{"src": "./app-icon.png", "sizes": "256x256", "type": "image/png"}]
    }
    (folder / "manifest.webmanifest").write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
    shutil.copyfile(root / "art/taffy/idle_0.png",folder / "app-icon.png")
    with zipfile.ZipFile(notices_archive) as archive:
        for name in ("LICENSE.txt", "OFL.txt", "GODOT-LICENSE.txt", "GODOT-THIRD-PARTY.txt"):
            (folder / name).write_bytes(archive.read(name))
    # Progress reports decoded file sizes; a mobile-only PCK can replace the desktop one.
    for asset in ("index.pck", "index.wasm"):
        pattern = r'("' + re.escape(asset) + r'"\s*:\s*)\d+'
        html, count = re.subn(pattern, lambda m: m[1] + str((folder/asset).stat().st_size), html)
        if count != 1:
            raise ValueError(f"Expected one Godot file size for {asset}")
    page.write_text(html.replace(marker,metadata),encoding="utf-8")
    prepare_asset_cache(folder)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export_directory",type=Path)
    parser.add_argument("notices_archive",type=Path)
    args = parser.parse_args()
    prepare_site(args.export_directory, args.notices_archive)
