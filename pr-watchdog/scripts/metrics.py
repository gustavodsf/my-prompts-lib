#!/usr/bin/env python3
"""
metrics.py <outDir> [subagents-glob]

Real token cost for one watchdog run, read from the harness transcripts.

Never ask a lane for its own token count -- a subagent has no token counter, so any figure
it states about itself is invented. Everything here comes from the recorded usage blocks.

Two things this gets right that the earlier shell version did not:

  1. Lane identification. The reconciler reads all five lane files, so matching a transcript
     on "lane-c.md" caught the reconciler for whichever lane was scanned first and reported
     one agent's usage as three lanes'. A lane's transcript names exactly ONE lane file --
     its own. That is the discriminator.

  2. What counts. Cache reads are ~95% of throughput because every turn re-reads the whole
     cached prefix, so cost is turns x context size. Output tokens are ~0.6% and are the
     wrong thing to optimise.
"""
import json, glob, os, re, sys, collections

LANE_RE = re.compile(r'lane-([a-e])\.md')
STAMP_RE = re.compile(r'\.\d+Z$')


def iso_to_epoch(ts):
    from datetime import datetime
    try:
        return datetime.strptime(STAMP_RE.sub('Z', ts), "%Y-%m-%dT%H:%M:%SZ").timestamp()
    except Exception:
        return 0.0


def scan(path, outdir_tail):
    lanes, hit = set(), False
    inp = out = cr = cw = turns = 0
    stamps, tools = [], collections.Counter()
    with open(path, errors='ignore') as fh:
        for line in fh:
            if outdir_tail in line:
                hit = True
            if 'lane-' in line:
                lanes.update(LANE_RE.findall(line))
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d.get('timestamp'):
                stamps.append(d['timestamp'])
            msg = d.get('message') or {}
            u = msg.get('usage') or {}
            if u:
                turns += 1
                inp += u.get('input_tokens', 0)
                out += u.get('output_tokens', 0)
                cr += u.get('cache_read_input_tokens', 0)
                cw += u.get('cache_creation_input_tokens', 0)
            c = msg.get('content')
            if isinstance(c, list):
                for b in c:
                    if isinstance(b, dict) and b.get('type') == 'tool_use':
                        tools[b.get('name', '?')] += 1
    if not hit:
        return None
    total = inp + out + cr + cw
    return {
        'transcript': os.path.basename(path),
        'lanes': sorted(lanes),
        'turns': turns,
        'tokens': {'input': inp, 'output': out, 'cacheRead': cr, 'cacheWrite': cw,
                   'total': total},
        'perTurn': (total // turns) if turns else 0,
        'toolCalls': sum(tools.values()),
        'toolsByName': dict(tools),
        'startedAt': min(stamps) if stamps else None,
        'endedAt': max(stamps) if stamps else None,
    }


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: metrics.py <outDir> [subagents-glob]")
    out_dir = sys.argv[1].rstrip('/')
    tail = '/'.join(out_dir.split('/')[-2:])          # PR-3020/bab8be13a0aa
    pattern = sys.argv[2] if len(sys.argv) > 2 else \
        os.path.expanduser('~/.claude/projects/*/*/subagents/agent-*.jsonl')

    lanes, recon = {}, []
    for p in glob.glob(pattern):
        r = scan(p, tail)
        if not r or not r['lanes']:
            continue
        if len(r['lanes']) == 1:
            lanes.setdefault(r['lanes'][0], r)        # one transcript per lane letter
        else:
            recon.append(r)

    ordered = [lanes[k] for k in sorted(lanes)]
    agents = ordered + recon

    def s(key, group=agents):
        return sum(a['tokens'][key] for a in group)

    n = len(ordered) or 1
    starts = [iso_to_epoch(a['startedAt']) for a in agents if a['startedAt']]
    ends = [iso_to_epoch(a['endedAt']) for a in agents if a['endedAt']]

    report = {
        'outDir': out_dir,
        'laneCount': len(ordered),
        'reconcilerFound': bool(recon),
        'lanes': [{'lane': a['lanes'][0], **{k: v for k, v in a.items() if k != 'lanes'}}
                  for a in ordered],
        'reconciler': [{k: v for k, v in a.items() if k != 'lanes'} for a in recon],
        'lanesTotal': {k: s(k, ordered) for k in
                       ('input', 'output', 'cacheRead', 'cacheWrite', 'total')},
        'perLaneAverage': {
            'total': s('total', ordered) // n,
            'output': s('output', ordered) // n,
            'cacheRead': s('cacheRead', ordered) // n,
            'turns': sum(a['turns'] for a in ordered) // n,
        },
        'runTotal': {k: s(k) for k in
                     ('input', 'output', 'cacheRead', 'cacheWrite', 'total')},
        'elapsedSeconds': int(max(ends) - min(starts)) if starts and ends else 0,
        'note': ('cacheRead is ~95% of throughput: every turn re-reads the cached prefix, '
                 'so cost is turns x context size. Output is ~0.6% and is the wrong thing '
                 'to optimise.'),
    }

    with open(os.path.join(out_dir, 'metrics.json'), 'w') as fh:
        json.dump(report, fh, indent=2)

    w = f"{'lane':6}{'turns':>7}{'output':>10}{'cacheRead':>14}{'per-turn':>11}{'TOTAL':>14}"
    print(w); print('-' * len(w))
    for a in report['lanes']:
        print(f"{a['lane']:6}{a['turns']:>7}{a['tokens']['output']:>10,}"
              f"{a['tokens']['cacheRead']:>14,}{a['perTurn']:>11,}{a['tokens']['total']:>14,}")
    for a in report['reconciler']:
        print(f"{'recon':6}{a['turns']:>7}{a['tokens']['output']:>10,}"
              f"{a['tokens']['cacheRead']:>14,}{a['perTurn']:>11,}{a['tokens']['total']:>14,}")
    print('-' * len(w))
    p = report['perLaneAverage']; t = report['runTotal']
    print(f"per-lane average: {p['total']:,} total  ({p['output']:,} output, {p['turns']} turns)")
    print(f"RUN TOTAL:        {t['total']:,} tokens  "
          f"({t['cacheRead']:,} cache-read, {t['output']:,} output)")
    print(f"elapsed:          {report['elapsedSeconds']}s")


if __name__ == '__main__':
    main()
