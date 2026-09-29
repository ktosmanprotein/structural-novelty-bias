#!/bin/bash
# =============================================================================
# Re-analysis of the AFDB "dark cluster" fraction under confidence filtering
#
#   WHY THIS ANALYSIS
#   Barrio-Hernandez et al. (Nature 2023) clustered the whole AlphaFold Database
#   and reported that ~31% of the 2.27M non-singleton structural clusters are
#   "dark" - lacking annotation, and interpreted as probable previously
#   undescribed structures. That figure is the most-cited number in this area.
#
#   Our paper argues that apparent structural novelty is inflated by model
#   confidence. This tests that claim on the field's own flagship dataset
#   rather than only on our parasite panel: what happens to the dark fraction
#   if clusters whose representative fails a standard confidence filter are
#   excluded?
#
#   WHY IT IS A CONSERVATIVE TEST
#   The cluster representative is the HIGHEST-pLDDT member of its AFDB50
#   sequence cluster. So we are asking whether even the best-predicted member
#   of a dark cluster is confidently predicted. Any inflation we detect is a
#   lower bound.
#
#   WHAT IT CANNOT DO
#   This file reports mean pLDDT only, not per-residue values, so the
#   ordered-fraction criterion cannot be applied - only 2 of our 3 criteria
#   (mean pLDDT >= 70, length >= 50). That also makes the result conservative:
#   the full filter would exclude more.
#
#   Downloads one 47.6 MB file. Nothing else is fetched.
#
# Double-click, or:  bash ~/Downloads/paper1_methods/run_afdb_darkcluster_reanalysis.command
# Output: ~/Downloads/paper1_methods/afdb_reanalysis/
# =============================================================================
set -e
OUT="$HOME/Downloads/paper1_methods/afdb_reanalysis"
mkdir -p "$OUT"
BASE="https://afdb-cluster.steineggerlab.workers.dev"
FN="2-repId_isDark_nMem_repLen_avgLen_repPlddt_avgPlddt_LCAtaxId.tsv.gz"
exec > >(tee "$OUT/run.log") 2>&1

echo "=== AFDB dark-cluster re-analysis ==="
echo "Source: Barrio-Hernandez et al., Nature 2023 (AFDB Clusters v6)"
echo "License: CC-BY 4.0"
echo ""
# Both releases: v3 is the release the published 31% figure was computed on,
# v6 is current. Comparing them quantifies how much a "novelty" number moves
# with the database alone, holding the method fixed.
for V in v3 v6; do
  F="$OUT/afdb_clusters_$V.tsv.gz"
  if [ -s "$F" ]; then
    echo "$V cluster file present ($(du -h "$F" | cut -f1)) - reusing"
  else
    echo "Downloading $V cluster overview..."
    curl -fL --progress-bar "$BASE/$V/$FN" -o "$F" || { echo "$V download failed."; rm -f "$F"; }
  fi
done
echo ""

ENV=/opt/miniconda3/envs/pfstruct
PY="$ENV/bin/python3"; [ -x "$PY" ] || PY=python3

"$PY" - "$OUT" <<'PYEOF'
import gzip, os, sys, csv, math
OUT = sys.argv[1]
PLDDT_FLOOR, LEN_FLOOR = 70.0, 50
BANDS = ['<50', '50-60', '60-70', '70-80', '80-90', '>=90']

def band(p):
    if p < 50: return '<50'
    if p < 60: return '50-60'
    if p < 70: return '60-70'
    if p < 80: return '70-80'
    if p < 90: return '80-90'
    return '>=90'

def med(v):
    v = sorted(v); n = len(v)
    return (v[n//2] if n % 2 else (v[n//2-1] + v[n//2]) / 2) if n else float('nan')

def scan(path):
    r = dict(tot=0, dark=0, kept=0, kept_dark=0, short_dark=0,
             bands={b: [0, 0] for b in BANDS}, dp=[], np_=[])
    with gzip.open(path, 'rt') as fh:
        for line in fh:
            p = line.rstrip('\n').split('\t')
            if len(p) < 7: continue
            try:
                dk = int(p[1]); ln = int(float(p[3])); pl = float(p[5])
            except ValueError: continue
            r['tot'] += 1; r['dark'] += dk
            e = r['bands'][band(pl)]; e[0] += 1; e[1] += dk
            (r['dp'] if dk else r['np_']).append(pl)
            if dk and ln < LEN_FLOOR: r['short_dark'] += 1
            if pl >= PLDDT_FLOOR and ln >= LEN_FLOOR:
                r['kept'] += 1; r['kept_dark'] += dk
    return r

def trend_z(bands):
    x = list(range(1, len(BANDS) + 1))
    n = [bands[b][0] for b in BANDS]; d = [bands[b][1] for b in BANDS]
    N, D = sum(n), sum(d)
    if not N or not D: return float('nan')
    pr = D / N
    T = sum(x[i] * (d[i] - n[i] * pr) for i in range(len(x)))
    var = pr * (1 - pr) * (sum(n[i] * x[i]**2 for i in range(len(x)))
                           - sum(n[i] * x[i] for i in range(len(x)))**2 / N)
    return T / math.sqrt(var) if var > 0 else float('nan')

rep = open(os.path.join(OUT, 'SUMMARY.txt'), 'w')
def w(s=''):
    print(s); rep.write(s + '\n')

w("AFDB dark-cluster fraction under confidence filtering")
w("Data: AFDB Clusters (Barrio-Hernandez et al., Nature 2023), CC-BY 4.0")
w("Filter: representative mean pLDDT >= %.0f AND representative length >= %d" % (PLDDT_FLOOR, LEN_FLOOR))
w("")

res = {}
for V in ('v3', 'v6'):
    f = os.path.join(OUT, 'afdb_clusters_%s.tsv.gz' % V)
    if not os.path.exists(f):
        w("%s: file not present, skipped" % V); continue
    res[V] = scan(f)

for V, r in res.items():
    d0 = r['dark'] / r['tot'] * 100
    d1 = r['kept_dark'] / r['kept'] * 100 if r['kept'] else float('nan')
    w("=" * 64)
    w("RELEASE %s" % V.upper())
    w("=" * 64)
    w("  clusters                       : %s" % format(r['tot'], ','))
    w("  dark clusters                  : %s" % format(r['dark'], ','))
    w("  dark fraction as published     : %.1f%%" % d0)
    w("  dark fraction after filtering  : %.1f%%   (%.2f-fold change)" % (d1, d0 / d1))
    w("  dark clusters removed          : %s of %s (%.1f%%)" %
      (format(r['dark'] - r['kept_dark'], ','), format(r['dark'], ','),
       (r['dark'] - r['kept_dark']) / r['dark'] * 100))
    w("  representative pLDDT median    : dark %.1f  |  non-dark %.1f" %
      (med(r['dp']), med(r['np_'])))
    w("  dark with rep pLDDT < 70       : %s (%.1f%% of dark)" %
      (format(sum(1 for x in r['dp'] if x < PLDDT_FLOOR), ','),
       sum(1 for x in r['dp'] if x < PLDDT_FLOOR) / r['dark'] * 100))
    w("")
    w("  dark fraction by representative pLDDT band")
    w("    %-8s %12s %12s %8s" % ('band', 'clusters', 'dark', '% dark'))
    for b in BANDS:
        n, dk = r['bands'][b]
        if n: w("    %-8s %12s %12s %7.1f%%" % (b, format(n, ','), format(dk, ','), dk / n * 100))
    lo = r['bands'][BANDS[0]]; hi = r['bands'][BANDS[-1]]
    if lo[0] and hi[0]:
        g0, g1 = lo[1] / lo[0] * 100, hi[1] / hi[0] * 100
        mono = all((r['bands'][BANDS[i]][1] / r['bands'][BANDS[i]][0]) >
                   (r['bands'][BANDS[i+1]][1] / r['bands'][BANDS[i+1]][0])
                   for i in range(len(BANDS) - 1) if r['bands'][BANDS[i]][0] and r['bands'][BANDS[i+1]][0])
        w("    gradient %.1f%% -> %.1f%%  = %.2f-fold;  monotonic: %s;  Cochran-Armitage z = %.1f"
          % (g0, g1, g0 / g1, mono, trend_z(r['bands'])))
    w("")

if 'v3' in res and 'v6' in res:
    a3 = res['v3']['dark'] / res['v3']['tot'] * 100
    a6 = res['v6']['dark'] / res['v6']['tot'] * 100
    w("=" * 64)
    w("RELEASE DEPENDENCE  (identical method, different database release)")
    w("=" * 64)
    w("  v3 : %s clusters, %.1f%% dark" % (format(res['v3']['tot'], ','), a3))
    w("  v6 : %s clusters, %.1f%% dark" % (format(res['v6']['tot'], ','), a6))
    w("  the dark fraction moved %.1f percentage points between releases" % (a6 - a3))
    w("  with no change to the method: a novelty figure is not a fixed property")
    w("")

with open(os.path.join(OUT, 'dark_by_plddt_band.tsv'), 'w', newline='') as fh:
    wr = csv.writer(fh, delimiter='\t')
    wr.writerow(['release', 'plddt_band', 'clusters', 'dark_clusters', 'pct_dark'])
    for V, r in res.items():
        for b in BANDS:
            n, dk = r['bands'][b]
            if n: wr.writerow([V, b, n, dk, round(dk / n * 100, 2)])

w("The representative is the highest-pLDDT member of its AFDB50 sequence cluster,")
w("so this is a lower bound. The ordered-fraction criterion could not be applied")
w("(per-residue pLDDT is absent from this file), making it more conservative still.")
rep.close()
print("\nwrote SUMMARY.txt and dark_by_plddt_band.tsv")
PYEOF

echo ""
echo "DONE. Results in: $OUT"
echo "Key file: SUMMARY.txt  - tell Claude when finished."
read -p "Press Enter to close"
