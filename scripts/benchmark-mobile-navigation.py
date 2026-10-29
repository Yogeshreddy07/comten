"""Read-only list navigation on an already unlocked, signed-in test phone.

Never enters credentials, bypasses a PIN, changes data or opens another app.
Times include ADB/UI hierarchy overhead and may represent retained content.
"""
import argparse
import json
from pathlib import Path
import re
import statistics
import time
import xml.etree.ElementTree as ET
import uiautomator2 as u2

PACKAGE = 'com.crompton.pms.frontend'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    device = u2.connect(args.device)

    def nodes():
        if device.app_current()['package'] != PACKAGE:
            raise RuntimeError('App is no longer foreground; stop')
        return [n for n in ET.fromstring(device.dump_hierarchy()).iter('node')
                if n.attrib.get('package') == PACKAGE]

    def label(n):
        return n.attrib.get('text') or n.attrib.get('content-desc', '')

    samples = {name: [] for name in ['Projects', 'Employee Management', 'Billing Management', 'Activities']}
    for _ in range(3):
        for name in samples:
            current = nodes()
            if not any(label(n) == 'Quick Access' for n in current):
                raise RuntimeError('Open the existing dashboard before running this probe')
            target = next(n for n in current if label(n).split('\n')[0] == name)
            x1, y1, x2, y2 = map(int, re.findall(r'\d+', target.attrib['bounds']))
            started = time.monotonic()
            device.click((x1+x2)//2, (y1+y2)//2)
            deadline = started + 25
            while True:
                labels = [label(n) for n in nodes()]
                if any(v.startswith('Unable to load') for v in labels):
                    raise RuntimeError(f'{name} returned an error')
                if name in labels and not any(v.startswith('Loading ') for v in labels):
                    break
                if time.monotonic() > deadline:
                    raise TimeoutError(f'{name} did not finish loading')
                time.sleep(.1)
            samples[name].append((time.monotonic()-started)*1000)
            # Retained billing content can be visible before refresh completes.
            if name == 'Billing Management':
                time.sleep(3)
                if any(label(n).startswith('Unable to load') for n in nodes()):
                    raise RuntimeError('Delayed billing refresh failed')
            device.press('back')
            deadline = time.monotonic()+5
            while not any(label(n) == 'Quick Access' for n in nodes()):
                if time.monotonic() > deadline:
                    raise RuntimeError('Dashboard did not return')
    report = {'scope': 'observed UI readiness; includes automation overhead; refreshed billing may retain content',
              'samples_ms': samples,
              'summary_ms': {k: {'median': statistics.median(v), 'max': max(v)} for k, v in samples.items()},
              'errors': 0, 'business_writes': 0}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
