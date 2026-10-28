"""Read-only navigation in installed app; UI polling gives conservative upper bounds."""
import argparse
import json
import math
from pathlib import Path
import re
import statistics
import time
import xml.etree.ElementTree as ET
import uiautomator2 as u2

PACKAGE = 'com.crompton.pms.frontend'
ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    args = parser.parse_args()
    d = u2.connect(args.device)
    d.app_start(PACKAGE)
    def nodes():
        if d.app_current().get('package') != PACKAGE:
            raise RuntimeError('Expected installed application; stopping UI actions')
        return [n for n in ET.fromstring(d.dump_hierarchy()).iter('node') if n.attrib.get('package') == PACKAGE]
    def labels(items):
        return [(n.attrib.get('text') or n.attrib.get('content-desc', '')) for n in items]
    samples = []
    for _ in range(3):
        for label in ('Projects', 'Employee Management', 'Billing Management', 'Activities'):
            items = nodes()
            if not any('Quick Access' in value for value in labels(items)):
                raise RuntimeError('Expected unlocked dashboard before read-only navigation')
            candidates = [n for n in items if (n.attrib.get('text') or n.attrib.get('content-desc', '')).split('\n')[0] == label]
            if not candidates: raise RuntimeError('Required dashboard control unavailable')
            target = next((n for n in candidates if n.attrib.get('clickable') == 'true'), candidates[0])
            bounds = list(map(int, re.findall(r'\d+', target.attrib['bounds'])))
            started = time.perf_counter()
            d.click((bounds[0]+bounds[2])//2, (bounds[1]+bounds[3])//2)
            ready = False
            while time.perf_counter() - started < 30:
                values = labels(nodes())
                if any('Unable to load' in value for value in values):
                    raise RuntimeError('Installed list returned a loading error')
                if (len([v for v in values if v]) >= 4 and
                        not any('Quick Access' in v for v in values) and
                        not any('Loading' in v or 'Please wait' in v for v in values)):
                    ready = True
                    break
            elapsed = round((time.perf_counter()-started)*1000, 1)
            samples.append({'screen':label, 'upper_bound_ms':elapsed, 'ready':ready})
            print(f'{label}: {elapsed:.1f} ms observed upper bound; ready={ready}', flush=True)
            if not ready: raise RuntimeError('List navigation timed out')
            d.press('back')
            deadline = time.perf_counter()+10
            while not any('Quick Access' in v for v in labels(nodes())):
                if time.perf_counter() > deadline: raise RuntimeError('Dashboard return timed out')
    groups = {}
    for sample in samples: groups.setdefault(sample['screen'], []).append(sample['upper_bound_ms'])
    summary = {key:{'samples':len(values), 'median_upper_bound_ms':statistics.median(values),
                    'p95_upper_bound_ms':sorted(values)[math.ceil(len(values)*.95)-1]} for key, values in groups.items()}
    out = ROOT/'.local/device-performance/installed-navigation.json'
    out.write_text(json.dumps({'scope':'Installed 1.0.6 read-only navigation, UI polling includes automation overhead; not sub-100ms precision',
                               'samples':samples,'summary':summary}, indent=2))
    print(json.dumps(summary, indent=2))


if __name__ == '__main__': main()
