#!/bin/bash
# =============================================================================
# Matched PDB100 correction across the whole 15-species panel
#
#   WHY: the P. falciparum novel-fold set was corrected against PDB100, but the
#   other species were only ever searched against AF-SwissProt. Plotting a
#   PDB100-corrected P. falciparum against uncorrected relatives would invent a
#   Pf-specific drop that is an artefact of which relatives happen to have had
#   their complexes solved. This applies the same correction to every species so
#   the cross-species panel is internally consistent on both databases.
#
#   Only "novel-ish" hypothetical proteins are queried (verdict = novel, no_hit
#   or twilight): a protein already called known-fold cannot become more known,
#   so the rest cannot change. That is 8,011 structures, all already on disk.
#
#   READ-ONLY on ~/apico_structural_analysis. All output goes to Downloads.
#
# Double-click, or:  bash ~/Downloads/run_pdb100_crossspecies.command
# Output: ~/Downloads/pdb100_crossspecies/
# =============================================================================
set -e
APICO="$HOME/apico_structural_analysis"
DB="$HOME/Downloads/foldseek_dbs/pdb100"
OUT="$HOME/Downloads/pdb100_crossspecies"
mkdir -p "$OUT"/{queries,tmp}
exec > >(tee "$OUT/run.log") 2>&1
stop() { echo ""; echo "$1"; read -p "Press Enter to close"; exit 1; }

[ -d "$APICO/results/novelty" ] || stop "ERROR: $APICO/results/novelty not found."
[ -f "${DB}.dbtype" ] || stop "ERROR: pdb100 database not found at $DB"

ENV=/opt/miniconda3/envs/pfstruct
FS=""
for C in "$ENV/bin/foldseek" "$(command -v foldseek 2>/dev/null)" /opt/miniconda3/bin/foldseek /opt/homebrew/bin/foldseek; do
  [ -n "$C" ] && [ -x "$C" ] && FS="$C" && break
done
[ -z "$FS" ] && stop "ERROR: foldseek not found."
PY="$ENV/bin/python3"; [ -x "$PY" ] || PY=python3
echo "Foldseek : $FS"
echo "Apicofold: $APICO  (read-only)"
echo ""

# ── stage the query structures ───────────────────────────────────────────────
echo "=== Selecting novel-ish hypothetical proteins and staging structures ==="
"$PY" - "$APICO" "$OUT" <<'PYEOF'
import csv, os, glob, shutil, sys
APICO, OUT = sys.argv[1], sys.argv[2]
NOVELISH = {'novel', 'no_hit', 'twilight'}
qdir = os.path.join(OUT, 'queries')
rows = []
for f in sorted(glob.glob(f'{APICO}/results/novelty/*_novelty.tsv')):
    key = os.path.basename(f).replace('_novelty.tsv', '')
    R = list(csv.DictReader(open(f), delimiter='\t'))
    conf = [r for r in R if r['verdict'] not in ('low_confidence', 'no_model')]
    nov = [r for r in conf if r['verdict'] in NOVELISH]
    hyp_conf = [r for r in conf if r['hypothetical'] == '1']
    hyp_nov = [r for r in nov if r['hypothetical'] == '1']
    staged = 0
    for r in hyp_nov:
        src = f"{APICO}/data/structures/{key}/AF-{r['accession']}-F1-model_v6.pdb"
        if os.path.exists(src):
            dst = os.path.join(qdir, os.path.basename(src))
            if not os.path.exists(dst):
                shutil.copy2(src, dst)          # copy, never move
            staged += 1
    rows.append((key, r['label'] if hyp_nov else key, len(hyp_conf), len(hyp_nov), staged))
    print(f"  {key:<17} hypothetical confident {len(hyp_conf):>5}   novel-ish {len(hyp_nov):>5}   staged {staged:>5}")
with open(os.path.join(OUT, 'panel_baseline.tsv'), 'w', newline='') as f:
    w = csv.writer(f, delimiter='\t')
    w.writerow(['species_key', 'label', 'hypo_confident', 'hypo_novelish', 'staged'])
    w.writerows(rows)
print(f"\n  staged {len(os.listdir(qdir))} structures total")
PYEOF

N=$(ls "$OUT/queries" | wc -l | tr -d ' ')
[ "$N" -gt 0 ] || stop "ERROR: no query structures staged."

# ── one Foldseek search for the whole panel ──────────────────────────────────
echo ""
echo "=== Searching $N structures against PDB100 (this is the long step) ==="
COLS="query,target,alntmscore,qtmscore,ttmscore,prob,evalue,alnlen,qlen,tlen"
"$FS" createdb "$OUT/queries" "$OUT/tmp/qpanel" --threads 4 >/dev/null
"$FS" search "$OUT/tmp/qpanel" "$DB" "$OUT/tmp/res" "$OUT/tmp/w" \
  --alignment-type 1 -e 10 -a --threads 4 >/dev/null
"$FS" convertalis "$OUT/tmp/qpanel" "$DB" "$OUT/tmp/res" \
  "$OUT/pdb100_panel_hits.m8" --format-output "$COLS" >/dev/null
echo "Raw hits: $(wc -l < "$OUT/pdb100_panel_hits.m8" | tr -d ' ') lines"

# ── recompute the panel ──────────────────────────────────────────────────────
echo ""
echo "=== Corrected novelty rates ==="
"$PY" - "$APICO" "$OUT" <<'PYEOF'
import csv, os, re, glob, sys
APICO, OUT = sys.argv[1], sys.argv[2]
NOVELISH = {'novel', 'no_hit', 'twilight'}
cols = "query target alntmscore qtmscore ttmscore prob evalue alnlen qlen tlen".split()
best = {}
for line in open(f'{OUT}/pdb100_panel_hits.m8'):
    p = line.rstrip('\n').split('\t')
    if len(p) < 10: continue
    m = re.search(r'AF-(.+?)-F1', p[0]); a = m.group(1) if m else p[0]
    q = float(p[3])                      # qtmscore: query-normalised, conservative
    if a not in best or q > best[a][0]: best[a] = (q, p[1])
# ── same-organism control ────────────────────────────────────────────────────
# PDB100 targets are PDB entries, so an accession self-match cannot occur. The
# meaningful control is whether the matched entry comes from the query's OWN
# genus: that means the protein's own structure has been solved, which is a
# different claim from sharing a fold with something distant. Species whose
# relatives are well represented in the PDB will be corrected harder for
# reasons of research effort, so both rates are reported.
GENUS = {'pfalciparum':'plasmodium','pvivax':'plasmodium','pknowlesi':'plasmodium',
         'pberghei':'plasmodium','tgondii':'toxoplasma','ncaninum':'neospora',
         'etenella':'eimeria','cparvum':'cryptosporidium','chominis':'cryptosporidium',
         'bbovis':'babesia','tannulata':'theileria','tparva':'theileria',
         'pmarinus':'perkinsus','tthermophila':'tetrahymena','vbrassicaformis':'vitrella'}
import json, urllib.request, time
cache_p = f'{OUT}/entry_organisms.json'
cache = json.load(open(cache_p)) if os.path.exists(cache_p) else {}
entries = sorted({v[1].split('-')[0].split('_')[0].lower()
                  for v in best.values() if v[0] >= 0.50})
todo = [e for e in entries if e not in cache]
print(f"Looking up source organisms for {len(todo)} PDB entries ({len(entries)-len(todo)} cached)...")
for i, e in enumerate(todo, 1):
    orgs = []
    try:
        d = json.load(urllib.request.urlopen(
            f'https://data.rcsb.org/rest/v1/core/entry/{e}', timeout=30))
        n = d.get('rcsb_entry_info', {}).get('polymer_entity_count', 0)
        for j in range(1, min(n, 40) + 1):
            try:
                pe = json.load(urllib.request.urlopen(
                    f'https://data.rcsb.org/rest/v1/core/polymer_entity/{e}/{j}', timeout=30))
                for s in pe.get('rcsb_entity_source_organism', []) or []:
                    nm = s.get('scientific_name')
                    if nm and nm not in orgs: orgs.append(nm)
            except Exception: pass
    except Exception: pass
    cache[e] = orgs
    if i % 100 == 0:
        print(f'   {i}/{len(todo)}'); json.dump(cache, open(cache_p, 'w'))
    time.sleep(0.2)
json.dump(cache, open(cache_p, 'w'))

def same_genus(species_key, target):
    g = GENUS.get(species_key)
    if not g: return False
    e = target.split('-')[0].split('_')[0].lower()
    return any(g in o.lower() for o in cache.get(e, []))

rep = open(f'{OUT}/SUMMARY.txt', 'w')
def w(s=''): print(s); rep.write(s + '\n')
w(f"Matched PDB100 correction, 15-species panel   (query-normalised TM >= 0.50)")
w(f"PDB100 release {open(f'{os.path.dirname(OUT)}/foldseek_dbs/pdb100.version').read().split()[1] if os.path.exists(f'{os.path.dirname(OUT)}/foldseek_dbs/pdb100.version') else '?'}")
w("")
w(f"{'species':<17}{'label':<19}{'denom':>6}{'AFSP%':>7}{'reass':>6}{'ownGen':>7}{'PDB100%':>8}{'xGenus%':>8}{'drop':>6}")
w('-' * 90)
out = []
for f in sorted(glob.glob(f'{APICO}/results/novelty/*_novelty.tsv')):
    key = os.path.basename(f).replace('_novelty.tsv', '')
    R = list(csv.DictReader(open(f), delimiter='\t'))
    conf = [r for r in R if r['verdict'] not in ('low_confidence', 'no_model')]
    hyp = [r for r in conf if r['hypothetical'] == '1']
    nov = [r for r in hyp if r['verdict'] in NOVELISH]
    lab = hyp[0]['label'] if hyp else key
    den = len(hyp)
    if not den: continue
    reass = [r for r in nov if best.get(r['accession'], (0,))[0] >= 0.50]
    own = [r for r in reass if same_genus(key, best[r['accession']][1])]
    old = len(nov) / den * 100
    new = (len(nov) - len(reass)) / den * 100
    xg = (len(nov) - (len(reass) - len(own))) / den * 100   # excluding own-genus entries
    w(f"{key:<17}{lab:<19}{den:>6}{old:>7.1f}{len(reass):>6}{len(own):>7}{new:>8.1f}{xg:>8.1f}{old-new:>6.1f}")
    out.append(dict(species_key=key, label=lab, hypo_confident=den, novelish_afsp=len(nov),
                    pct_afsp=round(old, 2), reassigned_by_pdb100=len(reass),
                    reassigned_own_genus=len(own),
                    novelish_pdb100=len(nov) - len(reass), pct_pdb100=round(new, 2),
                    pct_pdb100_excl_own_genus=round(xg, 2),
                    drop_points=round(old - new, 2)))
with open(f'{OUT}/panel_corrected.tsv', 'w', newline='') as fh:
    wr = csv.DictWriter(fh, fieldnames=list(out[0].keys()), delimiter='\t')
    wr.writeheader(); wr.writerows(out)
with open(f'{OUT}/reassigned_per_protein.tsv', 'w', newline='') as fh:
    wr = csv.writer(fh, delimiter='\t')
    wr.writerow(["species_key","accession","verdict_afsp","best_pdb100_qtm","best_pdb100_target","own_genus","entry_organisms"])
    for f in sorted(glob.glob(f'{APICO}/results/novelty/*_novelty.tsv')):
        key = os.path.basename(f).replace('_novelty.tsv', '')
        for r in csv.DictReader(open(f), delimiter='\t'):
            if r['hypothetical'] == '1' and r['verdict'] in NOVELISH:
                b = best.get(r['accession'])
                if b and b[0] >= 0.50:
                    wr.writerow([key, r['accession'], r['verdict'], f'{b[0]:.4f}', b[1],
                                 'YES' if same_genus(key, b[1]) else 'no',
                                 '; '.join(cache.get(b[1].split('-')[0].split('_')[0].lower(), [])[:3])])
w("")
w("COLUMNS")
w("  AFSP%    novel-fold rate against AF-SwissProt only (what the current figure plots)")
w("  reass    proteins reassigned to a known fold by PDB100")
w("  ownGen   of those, matched to an entry from the query's OWN genus, i.e. the")
w("           protein's own structure is solved rather than a shared distant fold")
w("  PDB100%  corrected rate, all reassignments removed")
w("  xGenus%  corrected rate counting ONLY cross-genus reassignments (own-genus")
w("           matches left as novel) — the conservative bound")
w("")
w("The 'drop' column is the quantity of interest: if it is large for species with")
w("well-studied relatives and small for the free-living outgroups, novel-fold")
w("rates are confounded by structural-biology effort rather than by biology.")
w("Compare PDB100% against xGenus%: a large gap means the correction is driven by")
w("the query lineage's own PDB representation, not by genuine fold sharing.")
w("")
w("Files: panel_corrected.tsv, reassigned_per_protein.tsv, entry_organisms.json,")
w("       pdb100_panel_hits.m8")
rep.close()
PYEOF

rm -rf "$OUT/tmp" "$OUT/queries"
echo ""
echo "DONE. Results in: $OUT"
echo "Key file: SUMMARY.txt  - tell Claude when finished."
read -p "Press Enter to close"
