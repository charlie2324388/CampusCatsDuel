"""Present one read-only game download to the named local network until the user closes it."""
import argparse
import hashlib
import io
import ipaddress
import json
import secrets
import subprocess
import sys
import threading
import webbrowser
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit
from urllib.request import build_opener, ProxyHandler

BUILD = Path(__file__).resolve().parents[1] / "build"
ZIP = BUILD / "课间猫擂台-iPhone网页版.zip"
WEB = BUILD / "iphone"
FILES = ("index.html", "index.js", "index.wasm", "index.pck", "index.png",
         "index.audio.position.worklet.js", "index.audio.worklet.js")
PRIVATE_NETS = tuple(ipaddress.ip_network(item) for item in ("192.168.0.0/16", "10.0.0.0/8", "172.16.0.0/12"))
ARCHIVE_FILES = set(FILES) | {"OFL.txt"}
APP = "https://apps.apple.com/cn/app/local-vibe-runner/id6762107899"


def game_zip():
    present = [WEB / name for name in FILES if (WEB / name).is_file()]
    if ZIP.is_file() and all(ZIP.stat().st_mtime >= p.stat().st_mtime for p in present):
        with zipfile.ZipFile(ZIP) as archive:
            if set(archive.namelist()) == ARCHIVE_FILES:
                return ZIP.read_bytes()
    if len(present) != len(FILES):
        raise RuntimeError("未找到完整的 iPhone 游戏包。请在项目的 build 文件夹内运行这个入口。")
    snapshot = io.BytesIO()
    with zipfile.ZipFile(snapshot, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=3) as archive:
        for path in present:
            archive.write(path, path.name)
        archive.write(BUILD.parent / "art" / "fonts" / "OFL.txt", "OFL.txt")
    return snapshot.getvalue()


def local_interfaces():
    # Only offer a physical IPv4 LAN with a gateway; never bind all interfaces.
    enumeration = """
    [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
    $items=foreach($nic in [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()){
        if($nic.OperationalStatus -ne 'Up' -or $nic.NetworkInterfaceType -notin @('Ethernet','Wireless80211')){continue}
        $props=$nic.GetIPProperties()
        if(!$props.GatewayAddresses.Count){continue}
        foreach($entry in $props.UnicastAddresses){
            if($entry.Address.AddressFamily -eq 'InterNetwork'){
                [PSCustomObject]@{ name=$nic.Name; ip=$entry.Address.ToString(); mask=$entry.IPv4Mask.ToString(); wifi=($nic.NetworkInterfaceType -eq 'Wireless80211') }
            }
        }
    }
    ConvertTo-Json -InputObject @($items) -Compress
    """
    result = subprocess.run(["powershell.exe", "-NoProfile", "-Command", enumeration],
                            capture_output=True, check=True, encoding="utf-8", timeout=15)
    choices = []
    for item in json.loads(result.stdout):
        address = ipaddress.ip_address(item["ip"])
        if any(address in net for net in PRIVATE_NETS):
            choices.append(item)
    return sorted(choices, key=lambda item: not item["wifi"])


def qr_svg(url):
    try:
        from reportlab.graphics.barcode.qrencoder import QRCode, QRErrorCorrectLevel
    except ImportError:
        return ""
    qr = QRCode(4, QRErrorCorrectLevel.M)
    qr.addData(url)
    qr.make()
    width = qr.getModuleCount()
    pixels = " ".join("M%d,%dh1v1h-1z" % (x + 4, y + 4) for y in range(width) for x in range(width) if qr.isDark(y,x))
    return ('<svg aria-label="手机扫码下载" role="img" viewBox="0 0 %d %d" shape-rendering="crispEdges">'
            '<rect width="100%%" height="100%%" fill="white"/><path fill="#152024" d="%s"/></svg>'
            % (width + 8, width + 8, pixels))


def page(url, payload):
    qr = qr_svg(url)
    return f"""<!doctype html><html lang="zh-CN"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer">
<title>课间猫擂台 · 手机试玩</title>
<style>*{{box-sizing:border-box}}body{{font:17px/1.55 system-ui,sans-serif;color:#1a282b;background:#faf3e4;margin:0;padding:24px}}
main{{margin:6vh auto;max-width:34rem}}h1{{font-size:2.3rem;margin:0}}p{{margin:10px 0}}svg{{display:block;width:195px;max-width:76vw;margin:18px 0}}
a{{color:#006257}}a.download{{display:inline-block;background:#254c4b;color:#fff;text-decoration:none;font-weight:700;padding:11px 21px;border-radius:2em}}
small{{display:block;overflow-wrap:anywhere}}ol{{padding-left:1.3rem}}li{{margin:10px 0}}</style>
<main><h1>课间猫擂台</h1><p>用 iPhone 相机扫码，把试玩包带到手机上。</p>{qr}
<small>{url}</small><p><a class="download" href="{url}game.zip">下载游戏包（{len(payload)/1048576:.1f} MB）</a></p>
<ol><li>在 iPhone 的「文件」→「下载项」中轻点 ZIP 解压。</li>
<li>用 <a href="{APP}" rel="noreferrer">Local Vibe Runner</a> 打开整个游戏文件夹，点 <b>Preview</b>。</li>
<li>横过手机，点一下画面，选猫开打。</li></ol><p>传完即可关闭电脑上的传包窗口。</p></main></html>""".encode()


class DownloadServer(ThreadingHTTPServer):
    daemon_threads = True

    def verify_request(self, request, client_address):
        return ipaddress.ip_address(client_address[0]) in self.subnet


class Download(BaseHTTPRequestHandler):
    def do_GET(self):
        self.answer(True)

    def do_HEAD(self):
        self.answer(False)

    def answer(self, body):
        route = urlsplit(self.path).path
        if route == self.server.link:
            data, mime = self.server.landing, "text/html; charset=utf-8"
        elif route == self.server.link + "game.zip":
            data, mime = self.server.archive, "application/zip"
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        if mime == "application/zip":
            self.send_header("Content-Disposition", 'attachment; filename="CampusCatsDuel-iPhone.zip"')
        self.end_headers()
        if body:
            try:
                self.wfile.write(data)
            except (ConnectionResetError, BrokenPipeError):
                pass

    def log_message(self, *_args):
        pass


def main(check=False, check_lan=False):
    archive = game_zip()
    if check and not check_lan:
        item = {"ip":"127.0.0.1", "mask":"255.0.0.0"}
    else:
        choices = local_interfaces()
        if not choices:
            raise RuntimeError("没有找到可用的局域网地址。请连接家庭 Wi-Fi 或改用平时传文件的方法把游戏 ZIP 发到自己的手机。")
        for number, candidate in enumerate([] if check_lan else choices,1):
            print(f"{number}. {candidate['name']}   {candidate['ip']}")
        index = int(input("请选择与 iPhone 在同一网络的编号：") or "1") if not check_lan and len(choices)>1 else 1
        if not 1 <= index <= len(choices):
            raise ValueError("网络编号无效。")
        item = choices[index-1]
    with DownloadServer((item["ip"],0), Download) as server:
        if check_lan: item["mask"]="255.255.255.255"
        server.subnet = ipaddress.ip_network((item["ip"],item["mask"]),strict=False)
        server.link = "/" + secrets.token_urlsafe(6) + "/"
        url = f"http://{item['ip']}:{server.server_port}{server.link}"
        server.archive = archive
        server.landing = page(url,archive)
        if check:
            threading.Thread(target=server.serve_forever,daemon=True).start()
            local = build_opener(ProxyHandler({}))
            try:
                with local.open(url, timeout=5) as incoming:
                    assert "Preview".encode() in incoming.read()
                with local.open(url+"game.zip",timeout=15) as incoming:
                    received = incoming.read()
                    assert received == archive
                with zipfile.ZipFile(io.BytesIO(received)) as zf:
                    assert set(zf.namelist())==ARCHIVE_FILES and zf.testzip() is None
                from urllib.error import HTTPError
                try:
                    local.open(url+"..%2f",timeout=5).close()
                except HTTPError as err:
                    assert err.code==404
                else:
                    raise RuntimeError("无效路径未正确拒绝")
                print("本机传包验证通过，下载与档案逐字节匹配。",len(archive),"bytes",hashlib.sha256(archive).hexdigest()[:12])
            finally:
                server.shutdown()
        else:
            print("\n课间猫擂台 · 手机试玩\niPhone 扫描浏览器内的二维码，或在 Safari 输入\n"+url)
            print("下载结束后关闭本窗口即可停止传包。\n")
            webbrowser.open(url)
            try:
                server.serve_forever()
            except KeyboardInterrupt:
                pass


if __name__ == "__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--check",action="store_true")
    parser.add_argument("--check-lan",action="store_true")
    args=parser.parse_args()
    try:
        main(args.check or args.check_lan, args.check_lan)
    except (ValueError, OSError, RuntimeError, subprocess.SubprocessError, zipfile.BadZipFile) as exc:
        print("传包入口未能启动。",exc)
        sys.exit(1)
