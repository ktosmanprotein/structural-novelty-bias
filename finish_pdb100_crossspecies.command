#!/bin/bash
# =============================================================================
# Fast finisher for the cross-species PDB100 pass.
#
#   Reads the Foldseek output that the main run already produced
#   (pdb100_crossspecies/pdb100_panel_hits.m8) and does everything after it:
#   source-organism lookup, own-genus control, corrected panel, summary.
#
#   Use this INSTEAD of letting run_pdb100_crossspecies.command do its own
#   lookup. That version calls the RCSB REST API once per polymer entity, and
#   ribosome / ATP-synthase entries have 40+ each, so it takes 1-2 hours. This
#   uses the batched GraphQL endpoint: same data, ~2 minutes.
#
#   Safe to run repeatedly. Organism lookups are cached in entry_organisms.json
#   and shared with the other script, so nothing is fetched twice.
#
# WHEN TO RUN: once "Raw hits: N lines" has appeared in the main run's output.
# At that point press Ctrl-C to stop the slow lookup, then run this.
#
# Double-click, or:  bash ~/Downloads/finish_pdb100_crossspecies.command
# =============================================================================
set -e
APICO="$HOME/apico_structural_analysis"
OUT="$HOME/Downloads/pdb100_crossspecies"
M8="$OUT/pdb100_panel_hits.m8"
stop() { echo ""; echo "$1"; read -p "Press Enter to close"; exit 1; }

[ -s "$M8" ] || stop "ERROR: $M8 is missing or empty.
The Foldseek search has not finished yet. Wait for the line
  'Raw hits: N lines'
in the main run, then come back to this."
[ -d "$APICO/results/novelty" ] || stop "ERROR: $APICO/results/novelty not found."

ENV=/opt/miniconda3/envs/pfstruct
PY="$ENV/bin/python3"; [ -x "$PY" ] || PY=python3
echo "Reading $(wc -l < "$M8" | tr -d ' ') alignments"
echo ""

"$PY" - "$APICO" "$OUT" <<'PYEOF'
import csv, os, re, glob, sys, json, time, urllib.request
APICO, OUT = sys.argv[1], sys.argv[2]
NOVELISH = {'novel', 'no_hit', 'twilight'}

# ── best PDB100 hit per protein, query-normalised ────────────────────────────
best = {}
for line in open(f'{OUT}/pdb100_panel_hits.m8'):
    p = line.rstrip('\n').split('\t')
    if len(p) < 10: continue
    m = re.search(r'AF-(.+?)-F1', p[0]); a = m.group(1) if m else p[0]
    try: q = float(p[3])                      # qtmscore
    except ValueError: continue
    if a not in best or q > best[a][0]: best[a] = (q, p[1])
print(f"  {len(best):,} proteins returned at least one alignment")

def entry_of(target):
    return target.split('-')[0].split('_')[0].lower()

entries = sorted({entry_of(v[1]) for v in best.values() if v[0] >= 0.50})
print(f"  {len(entries):,} distinct PDB entries among reassignments")

# ── batched GraphQL organism lookup ──────────────────────────────────────────
cache_p, title_p = f'{OUT}/entry_organisms.json', f'{OUT}/entry_titles.json'
cache = json.load(open(cache_p)) if os.path.exists(cache_p) else {}
titles = json.load(open(title_p)) if os.path.exists(title_p) else {}
todo = [e for e in entries if e not in cache]
print(f"  {len(todo):,} to fetch ({len(entries) - len(todo):,} already cached)")

GQL = """query($ids:[String!]!){entries(entry_ids:$ids){rcsb_id
 struct{title} polymer_entities{rcsb_entity_source_organism{scientific_name}}}}"""

def fetch(ids):
    body = json.dumps({'query': GQL, 'variables': {'ids': [i.upper() for i in ids]}}).encode()
    req = urllib.request.Request('https://data.rcsb.org/graphql', data=body,
                                 headers={'Content-Type': 'application/json'})
    d = json.load(urllib.request.urlopen(req, timeout=120))
    for e in (d.get('data', {}).get('entries') or []):
        if not e: continue
        rid = e['rcsb_id'].lower()
        orgs = []
        for pe in (e.get('polymer_entities') or []):
            for s in (pe.get('rcsb_entity_source_organism') or []):
                nm = s.get('scientific_name')
                if nm and nm not in orgs: orgs.append(nm)
        cache[rid] = orgs
        titles[rid] = ((e.get('struct') or {}).get('title') or '?')[:120]

def fetch_rest(e):
    """Proven per-entry REST path. Slower, used only if GraphQL is unavailable."""
    orgs, title = [], '?'
    try:
        d = json.load(urllib.request.urlopen(
            f'https://data.rcsb.org/rest/v1/core/entry/{e}', timeout=30))
        title = (d.get('struct', {}).get('title') or '?')[:120]
        n = d.get('rcsb_entry_info', {}).get('polymer_entity_count', 0)
        for j in range(1, min(n, 40) + 1):
            try:
                pe = json.load(urllib.request.urlopen(
                    f'https://data.rcsb.org/rest/v1/core/polymer_entity/{e}/{j}', timeout=30))
                for s in (pe.get('rcsb_entity_source_organism') or []):
                    nm = s.get('scientific_name')
                    if nm and nm not in orgs: orgs.append(nm)
            except Exception: pass
    except Exception: pass
    cache[e] = orgs; titles[e] = title

B, use_graphql = 100, True
for i in range(0, len(todo), B):
    chunk = todo[i:i + B]
    if use_graphql:
        ok = False
        for attempt in range(3):
            try:
                fetch(chunk); ok = True; break
            except Exception as ex:
                err = f'{type(ex).__name__}: {ex}'
                time.sleep(2 * (attempt + 1))
        if not ok:
            if i == 0:
                print(f"    GraphQL unavailable ({err}).")
                print("    Falling back to the per-entry REST API - slower (allow ~1-2 h),")
                print("    but it is the same path the verification run used successfully.")
                use_graphql = False
            else:
                print(f"    batch {i//B+1} failed via GraphQL; using REST for it")
    if not use_graphql or not ok:
        for e in chunk:
            if e not in cache:
                fetch_rest(e); time.sleep(0.15)
    json.dump(cache, open(cache_p, 'w')); json.dump(titles, open(title_p, 'w'))
    print(f"    {min(i+B, len(todo)):,}/{len(todo):,}")
filled = sum(1 for e in entries if cache.get(e))
print(f"  lookup done - organisms resolved for {filled:,}/{len(entries):,} entries")
if filled < len(entries) * 0.5:
    print("  WARNING: over half the entries returned no organism. The own-genus and")
    print("  apicomplexan columns below will understate the true counts.")

# ── own-genus control ────────────────────────────────────────────────────────
# PDB100 targets are PDB entries, so an accession self-match cannot occur. The
# meaningful control is whether the match comes from the query's OWN genus:
# that means the protein's own structure is solved, not a shared distant fold.
GENUS = {'pfalciparum':'plasmodium','pvivax':'plasmodium','pknowlesi':'plasmodium',
         'pberghei':'plasmodium','tgondii':'toxoplasma','ncaninum':'neospora',
         'etenella':'eimeria','cparvum':'cryptosporidium','chominis':'cryptosporidium',
         'bbovis':'babesia','tannulata':'theileria','tparva':'theileria',
         'pmarinus':'perkinsus','tthermophila':'tetrahymena','vbrassicaformis':'vitrella'}
CLADE = {'pfalciparum':'Haemosporida','pvivax':'Haemosporida','pknowlesi':'Haemosporida',
         'pberghei':'Haemosporida','tgondii':'Coccidia','ncaninum':'Coccidia',
         'etenella':'Coccidia','cparvum':'Cryptosporidia','chominis':'Cryptosporidia',
         'bbovis':'Piroplasmida','tannulata':'Piroplasmida','tparva':'Piroplasmida',
         'pmarinus':'OUTGROUP','tthermophila':'OUTGROUP','vbrassicaformis':'OUTGROUP'}
APICO_GENERA = ('plasmodium','toxoplasma','neospora','eimeria','cryptosporidium',
                'babesia','theileria','hammondia','cyclospora','besnoitia','sarcocystis')

def orgs_of(target): return cache.get(entry_of(target), [])
def same_genus(key, target):
    g = GENUS.get(key)
    return bool(g) and any(g in o.lower() for o in orgs_of(target))
def apicomplexan(target):
    return any(any(a in o.lower() for a in APICO_GENERA) for o in orgs_of(target))

# ── corrected panel ──────────────────────────────────────────────────────────
rep = open(f'{OUT}/SUMMARY.txt', 'w')
def w(s=''): print(s); rep.write(s + '\n')
w("Matched PDB100 correction across the 15-species panel")
w("Foldseek query-normalised TM >= 0.50, identical treatment for every species.")
w("")
w(f"{'species':<16}{'label':<19}{'clade':<15}{'denom':>6}{'AFSP%':>7}{'reass':>6}{'own':>5}{'apic':>6}{'PDB%':>7}{'xGen%':>7}{'drop':>6}")
w('-' * 105)
out = []
for f in sorted(glob.glob(f'{APICO}/results/novelty/*_novelty.tsv')):
    key = os.path.basename(f).replace('_novelty.tsv', '')
    R = list(csv.DictReader(open(f), delimiter='\t'))
    conf = [r for r in R if r['verdict'] not in ('low_confidence', 'no_model')]
    hyp = [r for r in conf if r['hypothetical'] == '1']
    nov = [r for r in hyp if r['verdict'] in NOVELISH]
    den = len(hyp)
    if not den: continue
    lab = hyp[0]['label']
    reass = [r for r in nov if best.get(r['accession'], (0,))[0] >= 0.50]
    own = [r for r in reass if same_genus(key, best[r['accession']][1])]
    apic = [r for r in reass if apicomplexan(best[r['accession']][1])]
    old = len(nov) / den * 100
    new = (len(nov) - len(reass)) / den * 100
    xg = (len(nov) - (len(reass) - len(own))) / den * 100
    w(f"{key:<16}{lab:<19}{CLADE.get(key,'?'):<15}{den:>6}{old:>7.1f}{len(reass):>6}"
      f"{len(own):>5}{len(apic):>6}{new:>7.1f}{xg:>7.1f}{old-new:>6.1f}")
    out.append(dict(species_key=key, label=lab, clade=CLADE.get(key, '?'),
                    hypo_confident=den, novelish_afsp=len(nov), pct_afsp=round(old, 2),
                    reassigned=len(reass), reassigned_own_genus=len(own),
                    reassigned_apicomplexan_entry=len(apic),
                    novelish_pdb100=len(nov) - len(reass), pct_pdb100=round(new, 2),
                    pct_pdb100_excl_own_genus=round(xg, 2), drop_points=round(old - new, 2)))

with open(f'{OUT}/panel_corrected.tsv', 'w', newline='') as fh:
    wr = csv.DictWriter(fh, fieldnames=list(out[0].keys()), delimiter='\t')
    wr.writeheader(); wr.writerows(out)

with open(f'{OUT}/reassigned_per_protein.tsv', 'w', newline='') as fh:
    wr = csv.writer(fh, delimiter='\t')
    wr.writerow(['species_key', 'accession', 'verdict_afsp', 'best_pdb100_qtm',
                 'best_pdb100_target', 'own_genus', 'apicomplexan_entry',
                 'entry_title', 'entry_organisms'])
    for f in sorted(glob.glob(f'{APICO}/results/novelty/*_novelty.tsv')):
        key = os.path.basename(f).replace('_novelty.tsv', '')
        for r in csv.DictReader(open(f), delimiter='\t'):
            if r['hypothetical'] == '1' and r['verdict'] in NOVELISH:
                b = best.get(r['accession'])
                if b and b[0] >= 0.50:
                    wr.writerow([key, r['accession'], r['verdict'], f'{b[0]:.4f}', b[1],
                                 'YES' if same_genus(key, b[1]) else 'no',
                                 'YES' if apicomplexan(b[1]) else 'no',
                                 titles.get(entry_of(b[1]), '?'),
                                 '; '.join(orgs_of(b[1])[:4])])

# ── clade-level roll-up: the confounding test ────────────────────────────────
w('-' * 105)
agg = {}
for r in out:
    c = 'OUTGROUP' if r['clade'] == 'OUTGROUP' else 'APICOMPLEXA'
    a = agg.setdefault(c, dict(den=0, nov=0, reass=0, own=0, apic=0))
    a['den'] += r['hypo_confident']; a['nov'] += r['novelish_afsp']
    a['reass'] += r['reassigned']; a['own'] += r['reassigned_own_genus']
    a['apic'] += r['reassigned_apicomplexan_entry']
for c, a in sorted(agg.items()):
    w(f"{c:<16}{'':<19}{'':<15}{a['den']:>6}{a['nov']/a['den']*100:>7.1f}{a['reass']:>6}"
      f"{a['own']:>5}{a['apic']:>6}{(a['nov']-a['reass'])/a['den']*100:>7.1f}"
      f"{'':>7}{a['reass']/a['den']*100:>6.1f}")
w("")
w("COLUMNS")
w("  AFSP%  novel-fold rate vs AF-SwissProt only (what the current Fig 2B plots)")
w("  reass  proteins reassigned to a known fold by PDB100")
w("  own    of those, matched to the query's OWN genus -> own structure solved")
w("  apic   of those, matched to ANY apicomplexan entry")
w("  PDB%   corrected rate, all reassignments removed")
w("  xGen%  corrected rate keeping own-genus matches as novel (conservative bound)")
w("  drop   AFSP% - PDB%, in percentage points")
w("")
w("THE TEST: if 'drop' is large for the apicomplexans and small for the three")
w("free-living outgroups, novel-fold rates are confounded by how much structural")
w("biology has been done on each lineage rather than by biology itself. The 'apic'")
w("column localises the effect: reassignments driven by apicomplexan PDB entries")
w("cannot affect the outgroups, so they inflate the apparent parasite-outgroup gap.")
w("")
w("Files: panel_corrected.tsv, reassigned_per_protein.tsv,")
w("       entry_organisms.json, entry_titles.json, pdb100_panel_hits.m8")
rep.close()
PYEOF

echo ""
echo "DONE. Results in: $OUT"
echo "Key file: SUMMARY.txt  - tell Claude when finished."
read -p "Press Enter to close"
