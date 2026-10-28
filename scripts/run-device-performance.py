"""Run the separate local-only Android performance APK; never replaces the cloud app."""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import math
from pathlib import Path
import statistics
import subprocess
import threading
import time

import httpx

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = 'com.crompton.pms.frontend.performance'
ADB = r'D:\SDKs\Android\platform-tools\adb.exe'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--label', choices=('before', 'after'), required=True)
    args = parser.parse_args()
    out = ROOT / '.local/device-performance'
    out.mkdir(parents=True, exist_ok=True)
    apk = ROOT / 'mobile/build/app/outputs/flutter-apk/app-profile.apk'
    aapt = sorted(Path(r'D:\SDKs\Android\build-tools').glob('*/aapt.exe'))[-1]
    metadata = subprocess.check_output([str(aapt), 'dump', 'badging', str(apk)], text=True)
    if "package: name='" + PACKAGE + "'" not in metadata:
        raise SystemExit('Refusing to install an APK outside the separate performance package')
    health = httpx.get('http://127.0.0.1:8006/health', timeout=5).json()
    if health.get('project') != 'demo-crompton-pms' or health.get('environment') != 'local':
        raise SystemExit('Requires owned local demo backend on port 8006')
    completed = threading.Event()
    results = {}
    stages = []

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args): pass
        def reply(self, value):
            body = json.dumps(value).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        def do_GET(self):
            if self.path != '/fixtures': self.send_error(404); return
            self.reply({'password':'SyntheticPass123!'})
        def do_POST(self):
            if self.path not in ('/stage', '/result'): self.send_error(404); return
            data = json.loads(self.rfile.read(min(int(self.headers.get('Content-Length', '0')), 100_000)))
            if self.path == '/stage':
                # Only fixed stage names and numbers leave the phone.
                stage, ms = str(data['stage']), float(data['ms'])
                if not stage.startswith(('startup.', 'login.', 'projects.', 'read.', 'project.', 'hosted.')) or not math.isfinite(ms):
                    self.send_error(400); return
                stages.append({'stage':stage, 'ms':round(ms, 2)})
                print(f'{stage}: {ms:.1f} ms', flush=True)
            else:
                results['passed'] = data.get('passed') is True
                completed.set()
            self.reply({'ok':True})

    server = ThreadingHTTPServer(('127.0.0.1', 8014), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    def adb(*command):
        return subprocess.check_output([ADB, '-s', args.device, *command], text=True, timeout=90)
    forwarded = []
    try:
        for port in (8006, 8086, 9099, 8014):
            adb('reverse', f'tcp:{port}', f'tcp:{port}')
            forwarded.append(port)
        adb('install', '-r', str(apk))
        adb('shell', 'am', 'force-stop', PACKAGE)
        adb('shell', 'am', 'start', '-n', PACKAGE + '/com.crompton.pms.frontend.MainActivity')
        deadline = time.monotonic() + 480
        while not completed.wait(20) and time.monotonic() < deadline:
            print(f'Waiting for device probe; {len(stages)} stages received', flush=True)
        groups = {}
        for item in stages: groups.setdefault(item['stage'], []).append(item['ms'])
        summary = {key:{'samples':len(values), 'median_ms':round(statistics.median(values), 2),
                        'p95_ms':sorted(values)[math.ceil(len(values)*.95)-1], 'max_ms':max(values)}
                   for key, values in groups.items()}
        result = {'passed':results.get('passed', False), 'samples':stages, 'summary':summary,
                  'scope':'Physical Android sandbox + USB local emulators; cloud health read-only'}
        (out / (args.label + '.json')).write_text(json.dumps(result, indent=2) + '\n')
        (out / (args.label + '-memory.txt')).write_text(adb('shell','dumpsys','meminfo', PACKAGE))
        print(json.dumps(summary, indent=2))
        if not result['passed']: raise SystemExit('Device probe did not complete; partial timing evidence saved')
    finally:
        server.shutdown()
        for port in forwarded:
            try: adb('reverse', '--remove', f'tcp:{port}')
            except subprocess.SubprocessError: pass


if __name__ == '__main__': main()
