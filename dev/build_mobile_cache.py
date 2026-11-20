"""Add content-addressed, cacheable downloads to a Godot 4.7.2 mobile export."""
import argparse
import hashlib
import json
import os
import re
import shutil
from pathlib import Path


HOOK = "return fetch(file).then(function (response) {"
PATCH = "return (window.campusCatsFetchAsset || window.fetch.bind(window))(file).then(function (response) {"
PRELOADER = "function loadFetch(file, tracker, fileSize, raw)"
MARKER = "<!-- mobile-cache -->"
END = "<!-- /mobile-cache -->"
DRIVER = re.compile(r'(?P<prefix>\bscript\.src\s*=\s*")index\.js(?:\?v=[a-f0-9]{16})?(?P<suffix>";)')


def prepare_asset_cache(output_dir):
    folder = Path(output_dir)
    driver = folder / "index.js"
    page = folder / "index.html"
    js = driver.read_text(encoding="utf-8")
    html = page.read_text(encoding="utf-8")
    if html.count(MARKER) != 1 or html.count(END) > 1 or len(DRIVER.findall(html)) != 1:
        raise ValueError("Unexpected mobile HTML shell: cache marker or JS driver assignment missing")
    start = js.find(PRELOADER)
    finish = js.find("function retry(", start)
    if start == -1 or finish == -1 or js.count(PRELOADER) != 1:
        raise ValueError("Unrecognized Godot preloader")
    fragment = js[start:finish]
    if (js.count(HOOK), js.count(PATCH), fragment.count(HOOK), fragment.count(PATCH)) == (1, 0, 1, 0):
        js = js.replace(HOOK, PATCH, 1)
    elif (js.count(HOOK), js.count(PATCH), fragment.count(PATCH)) != (0, 1, 1):
        raise ValueError("Unsupported Godot preloader; driver was not changed")

    assets = {}
    for suffix, mime in [(".wasm", "application/wasm"), (".pck", "application/octet-stream")]:
        source = folder / ("index" + suffix)
        digest = hashlib.sha256(source.read_bytes()).hexdigest()[:16]
        fingerprint = "index-" + digest + suffix
        dest = folder / fingerprint
        if not dest.exists() or hashlib.sha256(dest.read_bytes()).hexdigest()[:16] != digest:
            shutil.copyfile(source, dest)
        # Milliseconds survive JSON serialization and browser numeric precision.
        revision = int(os.environ["SOURCE_DATE_EPOCH"]) * 1000 if "SOURCE_DATE_EPOCH" in os.environ else source.stat().st_mtime_ns // 1_000_000
        assets[source.name] = dict(name=fingerprint, suffix=suffix, revision=revision, mime=mime)

    code = Path(__file__).with_name("mobile_asset_cache.js").read_text(encoding="utf-8")
    code = code.replace("__VERSIONED_ASSETS__", json.dumps(assets, sort_keys=True, separators=(",", ":")))
    replacement = MARKER + "\n<script>\n" + code.rstrip() + "\n</script>\n" + END
    if END in html:
        first = html.index(MARKER)
        last = html.index(END, first) + len(END)
        html = html[:first] + replacement + html[last:]
    else:
        html = html.replace(MARKER, replacement, 1)
    driver_bytes = js.encode("utf-8")
    version = hashlib.sha256(driver_bytes).hexdigest()[:16]
    html = DRIVER.sub(lambda m: m["prefix"] + "index.js?v=" + version + m["suffix"], html, count=1)
    driver.write_bytes(driver_bytes)
    page.write_bytes(html.encode("utf-8"))
    return {name: item["name"] for name, item in assets.items()}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export_directory", type=Path)
    print(json.dumps(prepare_asset_cache(parser.parse_args().export_directory)))
