#!/bin/bash
# =============================================================================
# Completeness check for the 316 confident novel-fold proteins
#
#   PART 1  PDB100  — full search, all 316 proteins, local database
#   PART 2  ESMAtlas (MGnify ESM30) — targeted spot-check, 23 proteins
#           (18 drug-target candidates + 6 validated fold assignments),
#           run through the Foldseek web server so no huge download is needed
#
# Double-click in Finder, or:  bash ~/Downloads/run_pdb100_and_esmatlas.command
# Output: ~/Downloads/pdb100_esmatlas_check_<date>/
# =============================================================================
set -e
cd "$HOME/Downloads"
OUT="$HOME/Downloads/pdb100_esmatlas_check_$(date +%Y%m%d_%H%M)"
mkdir -p "$OUT"/{targets,tmp,esm}
exec > >(tee "$OUT/run.log") 2>&1
stop() { echo ""; echo "$1"; read -p "Press Enter to close"; exit 1; }

ENV=/opt/miniconda3/envs/pfstruct
FS=""
for C in "$ENV/bin/foldseek" "$(command -v foldseek 2>/dev/null)" /opt/miniconda3/bin/foldseek /opt/homebrew/bin/foldseek; do
  [ -n "$C" ] && [ -x "$C" ] && FS="$C" && break
done
[ -z "$FS" ] && stop "ERROR: foldseek not found."
PY="$ENV/bin/python3"; [ -x "$PY" ] || PY=python3
echo "Foldseek: $FS ($($FS version 2>/dev/null))"

# ── the 316 target structures ────────────────────────────────────────────────
cp within259_analysis/structures/*.pdb            "$OUT/targets/"
cp pf_tgondii_overlap/pf_novel_structures/*.pdb   "$OUT/targets/"
N=$(ls "$OUT/targets" | wc -l | tr -d ' ')
echo "Targets: $N structures"
[ "$N" -eq 316 ] || stop "ERROR: expected 316 target structures, found $N"

# =============================================================================
# PART 1 — PDB100, all 316
# =============================================================================
echo ""
echo "=== PART 1: PDB100 (downloads ~10-15 GB on first run; re-used afterwards) ==="
DB="$HOME/Downloads/foldseek_dbs"
mkdir -p "$DB"
if [ ! -f "$DB/pdb100.dbtype" ]; then
  echo "Downloading the PDB database (one-off, can take 10-30 min)..."
  "$FS" databases PDB "$DB/pdb100" "$DB/tmp_dl" || stop "ERROR: database download failed."
else
  echo "Using existing database at $DB/pdb100"
fi

COLS="query,target,alntmscore,qtmscore,ttmscore,prob,evalue,alnlen,qlen,tlen"
"$FS" createdb "$OUT/targets" "$OUT/tmp/q316" --threads 4 >/dev/null
echo "Searching 316 proteins against PDB100..."
"$FS" search "$OUT/tmp/q316" "$DB/pdb100" "$OUT/tmp/res_pdb" "$OUT/tmp/w" \
  --alignment-type 1 -e 10 -a --threads 4 >/dev/null
"$FS" convertalis "$OUT/tmp/q316" "$DB/pdb100" "$OUT/tmp/res_pdb" \
  "$OUT/pdb100_hits.m8" --format-output "$COLS" >/dev/null
echo "Raw hits written: $(wc -l < "$OUT/pdb100_hits.m8" | tr -d ' ') lines"

# =============================================================================
# PART 2 — ESMAtlas spot-check, 23 proteins, via the Foldseek web server
# =============================================================================
echo ""
echo "=== PART 2: ESMAtlas (MGnify ESM30) spot-check on 23 proteins ==="
cat > "$OUT/esm/accessions.txt" <<'ACC'
A0A143ZX23
A0A144A4C1
C0H4N7
C0H4S6
C6KT42
O77379
O97333
Q8I2A3
Q8I2W2
Q8I331
Q8I3H6
Q8IB46
Q8IBQ4
Q8IBV2
Q8IDD5
Q8IEL0
Q8IEL2
Q8IJ78
Q8IJJ3
Q8IKN7
Q8IKQ7
Q8ILP8
Q8IM47
ACC
echo "Submitting to search.foldseek.com (one at a time, with pauses)..."
: > "$OUT/esm/esmatlas_best.tsv"
printf 'uniprot\tbest_target\tbest_alntm\tbest_prob\tn_hits\n' >> "$OUT/esm/esmatlas_best.tsv"
while read -r ACC; do
  [ -z "$ACC" ] && continue
  F="$OUT/targets/AF-${ACC}-F1-model_v6.pdb"
  [ -f "$F" ] || { echo "  $ACC  (structure not found, skipped)"; continue; }
  TICKET=$(curl -s -X POST -F q=@"$F" -F 'mode=tmalign' -F 'database[]=mgnify_esm30' \
           https://search.foldseek.com/api/ticket | "$PY" -c 'import sys,json;print(json.load(sys.stdin).get("id",""))' 2>/dev/null)
  if [ -z "$TICKET" ]; then echo "  $ACC  submission failed (server busy?) - rerun later"; sleep 5; continue; fi
  for i in $(seq 1 60); do
    ST=$(curl -s "https://search.foldseek.com/api/ticket/$TICKET" | "$PY" -c 'import sys,json;print(json.load(sys.stdin).get("status",""))' 2>/dev/null)
    [ "$ST" = "COMPLETE" ] && break
    [ "$ST" = "ERROR" ] && break
    sleep 5
  done
  if [ "$ST" != "COMPLETE" ]; then echo "  $ACC  status=$ST - skipped"; sleep 3; continue; fi
  curl -s "https://search.foldseek.com/api/result/$TICKET/0" > "$OUT/esm/${ACC}.json"
  "$PY" - "$OUT/esm/${ACC}.json" "$ACC" >> "$OUT/esm/esmatlas_best.tsv" <<'PYEOF'
import sys, json
try:
    d = json.load(open(sys.argv[1])); acc = sys.argv[2]
    al = [a for r in d.get('results', []) for a in r.get('alignments', [])]
    al = [x for y in al for x in (y if isinstance(y, list) else [y])]
    if not al:
        print(f"{acc}\t-\t0\t0\t0")
    else:
        def tm(a):
            for k in ('alntmscore', 'tmscore', 'qtmscore'):
                if k in a:
                    try: return float(a[k])
                    except (TypeError, ValueError): pass
            return 0.0
        b = max(al, key=tm)
        print(f"{acc}\t{b.get('target','?')}\t{tm(b):.4f}\t{b.get('prob',0)}\t{len(al)}")
except Exception as e:
    print(f"{sys.argv[2]}\tPARSE_ERROR\t0\t0\t0")
PYEOF
  echo "  $ACC  done"
  sleep 4
done < "$OUT/esm/accessions.txt"

# =============================================================================
# SUMMARY
# =============================================================================
"$PY" - "$OUT" <<'PYEOF'
import sys, os, re, csv
out = sys.argv[1]
cols = "query target alntmscore qtmscore ttmscore prob evalue alnlen qlen tlen".split()
def acc(t):
    m = re.search(r'AF-(.+?)-F1', t); return m.group(1) if m else t
best = {}
for line in open(f'{out}/pdb100_hits.m8'):
    p = line.rstrip('\n').split('\t')
    if len(p) < 10: continue
    r = dict(zip(cols, p)); a = acc(r['query']); v = float(r['alntmscore'])
    if a not in best or v > best[a][0]: best[a] = (v, r['target'], float(r['qtmscore']))
targets = [acc(f) for f in os.listdir(f'{out}/targets')]
nohit = set(open(os.path.expanduser('~/Downloads/259_nohit_accessions.txt')).read().split())
rep = open(f'{out}/SUMMARY.txt', 'w')
def w(s=''): print(s); rep.write(s + '\n')
w("PART 1 - PDB100, all 316 confident novel-fold proteins")
w(f"  proteins returning any PDB100 alignment : {len(best)} of 316")
ge5 = {a: v for a, v in best.items() if v[0] >= 0.50}
w(f"  proteins with best TM >= 0.50           : {len(ge5)}   <-- these would NOT be novel-fold")
if ge5:
    w("")
    w(f"  {'uniprot':<12}{'subset':<13}{'bestTM':>8}  target")
    for a, v in sorted(ge5.items(), key=lambda x: -x[1][0]):
        w(f"  {a:<12}{'no-hit' if a in nohit else 'partial-hit':<13}{v[0]:>8.3f}  {v[1]}")
w("")
w(f"  next 10 highest (below 0.50):")
for a, v in sorted([x for x in best.items() if x[1][0] < 0.5], key=lambda x: -x[1][0])[:10]:
    w(f"  {a:<12}{'no-hit' if a in nohit else 'partial-hit':<13}{v[0]:>8.3f}  {v[1]}")
with open(f'{out}/pdb100_best_per_protein.tsv', 'w') as f:
    f.write('uniprot\tsubset\tbest_alntm\tbest_qtm\tbest_target\n')
    for a in sorted(targets):
        v = best.get(a)
        f.write(f"{a}\t{'no-hit' if a in nohit else 'partial-hit'}\t" +
                (f"{v[0]:.4f}\t{v[2]:.4f}\t{v[1]}\n" if v else "0\t0\t(no alignment)\n"))
p2 = f'{out}/esm/esmatlas_best.tsv'
if os.path.exists(p2):
    rows = list(csv.DictReader(open(p2), delimiter='\t'))
    w(""); w("PART 2 - ESMAtlas (MGnify ESM30) spot-check")
    w(f"  proteins queried : {len(rows)}")
    hi = [r for r in rows if float(r['best_alntm'] or 0) >= 0.50]
    w(f"  best TM >= 0.50  : {len(hi)}")
    for r in sorted(rows, key=lambda r: -float(r['best_alntm'] or 0))[:8]:
        w(f"  {r['uniprot']:<12}{float(r['best_alntm'] or 0):>8.3f}  {r['best_target']}")
w(""); w("Files: pdb100_best_per_protein.tsv (all 316), pdb100_hits.m8 (raw), esm/esmatlas_best.tsv")
rep.close()
PYEOF

rm -rf "$OUT/tmp"
echo ""
echo "DONE. Results in: $OUT"
echo "Key file: SUMMARY.txt  - tell Claude when finished."
read -p "Press Enter to close"
