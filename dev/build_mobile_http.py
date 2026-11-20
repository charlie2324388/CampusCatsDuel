"""Prepare an HTTP-compatible copy of the single-thread Godot 4.7.2 mobile export.

Run prepare_mobile_site.py first, then:
    python dev/build_mobile_http.py <prepared-HTTPS-export> <HTTP-output>
"""
import argparse
import hashlib
import re
import shutil
from pathlib import Path

def replace(text,old,new):
    if text.count(old)!=1: raise ValueError('Expected one site to adjust: '+old[:75])
    return text.replace(old,new)


def prepare_http(source, out):
    if source.resolve() == out.resolve():
        raise ValueError("Choose a separate output directory for the HTTP build")
    out.mkdir(parents=True, exist_ok=True)
    for asset in source.iterdir():
        if asset.is_file():
            shutil.copy2(asset, out / asset.name)
    p=out/'index.html'
    html=p.read_text(encoding='utf-8')
    html=html.replace('if (!window.isSecureContext) throw new Error("请通过 HTTPS 打开这个网址。");','').replace('if (!window.isSecureContext) {fail("请通过 HTTPS 打开这个网址。"); return;}','')
    html=replace(html,'const missing = Engine.getMissingFeatures({threads:false});','''const missing = window.isSecureContext ? Engine.getMissingFeatures({threads:false}) : [];
      if (!window.isSecureContext) {
        if (!Engine.isWebGLAvailable(2)) missing.push("WebGL 2");
        if (!Engine.isFetchAvailable()) missing.push("Fetch");
        if (typeof WebAssembly !== "object") missing.push("WebAssembly");
      }''')
    p=out/'index.js'
    js=p.read_text(encoding='utf-8')
    js=replace(js,'GodotAudio.audioPositionWorkletPromise=ctx.audioWorklet.addModule(path)','GodotAudio.audioPositionWorkletPromise=ctx.audioWorklet&&typeof AudioWorkletNode==="function"?ctx.audioWorklet.addModule(path):null')
    js=replace(js,'if(this.isCanceled){return}this._source.connect(this.getPositionWorklet());if(start){this.start()}','if(this.isCanceled){return}if(GodotAudio.audioPositionWorkletPromise){this._source.connect(this.getPositionWorklet())}if(start){this.start()}')
    js=replace(js,'getPlaybackPosition(){return this._playbackPosition}','getPlaybackPosition(){if(!GodotAudio.audioPositionWorkletPromise){return this.offset+(this.isPaused?this.pauseTime:(this.isStarted?GodotAudio.ctx.currentTime-this._sourceStartTime:0))*this.getPlaybackRate()*this.getPitchScale()}return this._playbackPosition}')
    html=replace(html, 'const hint = ios && !standalone ?', 'const hint = window.isSecureContext && ios && !standalone ?')
    html=replace(html, 'let cache;\n    try {', 'if (!window.isSecureContext || typeof window.caches === "undefined") return fetch(url);\n    let cache;\n    try {')
    driver_bytes = js.encode('utf-8')
    digest = hashlib.sha256(driver_bytes).hexdigest()[:16]
    html,n=re.subn(r'script\.src = "index\.js\?v=[0-9a-f]{16}";',f'script.src = "index.js?v={digest}";',html)
    if n!=1: raise ValueError('Expected one fingerprinted JS URL')
    (out/'index.js').write_bytes(driver_bytes)
    (out/'index.html').write_bytes(html.encode('utf-8'))
    print(f'HTTP single-thread build: {out}, driver sha256 prefix {digest}, pack {(out / "index.pck").stat().st_size:,} bytes')



if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    prepare_http(args.source, args.output)
