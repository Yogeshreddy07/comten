"""Cold process startup to an interactive installed-app screen; never enters a PIN."""
import argparse
import json
from pathlib import Path
import statistics
import subprocess
import time
import xml.etree.ElementTree as ET
import uiautomator2 as u2

PACKAGE = 'com.crompton.pms.frontend'
ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--label', choices=('before', 'after'), required=True)
    args = parser.parse_args()
    d = u2.connect(args.device)
    samples = []
    for _ in range(3):
        d.app_stop(PACKAGE)
        started = time.perf_counter()
        d.app_start(PACKAGE)
        ready = None
        while time.perf_counter()-started < 30:
            if d.app_current().get('package') != PACKAGE:
                raise RuntimeError('Expected installed app; stopping')
            nodes = ET.fromstring(d.dump_hierarchy()).iter('node')
            labels = [(n.attrib.get('text') or n.attrib.get('content-desc', '')) for n in nodes if n.attrib.get('package')==PACKAGE]
            if any('Quick Access' in x for x in labels): ready='dashboard'
            elif any(x in ('Show PIN','Hide PIN') for x in labels): ready='app_lock'
            elif any('Welcome to Comten' in x for x in labels): ready='welcome'
            if ready: break
        if not ready: raise RuntimeError('Startup screen did not become interactive')
        elapsed = round((time.perf_counter()-started)*1000,1)
        samples.append({'upper_bound_ms':elapsed,'destination':ready})
        print('Installed cold startup:',elapsed,'ms upper bound to',ready,flush=True)
    values = [x['upper_bound_ms'] for x in samples]
    result = {'scope':'Installed app cold process to dashboard/lock/welcome; UI polling includes automation overhead; no PIN entered',
              'samples':samples,'median_upper_bound_ms':statistics.median(values),'max_upper_bound_ms':max(values)}
    (ROOT / ('.local/device-performance/installed-startup-'+args.label+'.json')).write_text(json.dumps(result,indent=2))


if __name__ == '__main__': main()
