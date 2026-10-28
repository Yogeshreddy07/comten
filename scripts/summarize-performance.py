"""Summarize development backend trace JSONL; fixture timings are not SLAs."""
import argparse
from collections import defaultdict
import json
import math
from pathlib import Path
import statistics


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    groups = defaultdict(list)
    for line in args.input.read_text(encoding='utf-8').splitlines():
        row = json.loads(line)
        groups[row['method'] + ' ' + row['route']].append(row)
    result = {'scope':'Development traces; nested spans overlap; test fixture contention and failures are included', 'workflows':{}}
    for key, rows in sorted(groups.items()):
        values = sorted(r['total_ms'] for r in rows)
        labels = {label for r in rows for label in r['spans']}
        counts = {label for r in rows for label in r.get('counts', {})}
        result['workflows'][key] = {
            'requests':len(rows), 'errors':sum(r['status'] >= 400 for r in rows),
            'median_ms':round(statistics.median(values), 2), 'p95_ms':values[math.ceil(len(values)*.95)-1], 'max_ms':max(values),
            'stage_median_ms':{label:round(statistics.median(r['spans'].get(label, {}).get('ms', 0) for r in rows), 2) for label in sorted(labels)},
            'counter_totals':{label:sum(r.get('counts', {}).get(label, 0) for r in rows) for label in sorted(counts)}}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print('Wrote', len(groups), 'route summaries to', args.output)


if __name__ == '__main__':
    main()
