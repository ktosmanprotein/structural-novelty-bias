#!/bin/bash
# =============================================================================
# Independent verification of the PDB100 hits
#
#   For every one of the 316 proteins whose best PDB100 match reached
#   query-normalised TM >= 0.50, this:
#     1. downloads the matched PDB entry and extracts the matched chain
#     2. re-scores the pair with US-align (independent of Foldseek)
#     3. records what the PDB entry actually is (title + source organism)
#
#   The organism field is the decisive one: a P. falciparum entry means the
#   protein's own structure has been solved, not that it shares a fold with
#   something else.
#
# Double-click, or:  bash ~/Downloads/verify_pdb100_hits.command
# Output: ~/Downloads/pdb100_verification/
# =============================================================================
set -e
SRC=$(ls -d "$HOME"/Downloads/pdb100_esmatlas_check_*/ 2>/dev/null | tail -1)
[ -z "$SRC" ] && { echo "ERROR: no pdb100_esmatlas_check_* folder found."; read -p "Press Enter"; exit 1; }
OUT="$HOME/Downloads/pdb100_verification"
mkdir -p "$OUT"/{cif,chains}
exec > >(tee "$OUT/run.log") 2>&1

ENV=/opt/miniconda3/envs/pfstruct
PY="$ENV/bin/python3"; [ -x "$PY" ] || PY=python3
US=""
for C in "$ENV/bin/USalign" "$(command -v USalign 2>/dev/null)"; do [ -n "$C" ] && [ -x "$C" ] && US="$C" && break; done
[ -z "$US" ] && { echo "ERROR: USalign not found in $ENV/bin"; read -p "Press Enter"; exit 1; }
echo "Source run : $SRC"
echo "US-align   : $US"

"$PY" - "$SRC" "$OUT" "$US" <<'PYEOF'
import sys, os, re, csv, json, subprocess, urllib.request, time
SRC, OUT, US = sys.argv[1], sys.argv[2], sys.argv[3]
cols = "query target alntmscore qtmscore ttmscore prob evalue alnlen qlen tlen".split()
def acc(t):
    m = re.search(r'AF-(.+?)-F1', t); return m.group(1) if m else t
best = {}
for line in open(os.path.join(SRC, 'pdb100_hits.m8')):
    p = line.rstrip('\n').split('\t')
    if len(p) < 10: continue
    r = dict(zip(cols, p)); a = acc(r['query'])
    for k in ('alntmscore','qtmscore','ttmscore','evalue'): r[k] = float(r[k])
    for k in ('alnlen','qlen','tlen'): r[k] = int(r[k])
    r['cov'] = r['alnlen']/r['qlen']; r['acc'] = a
    if a not in best or r['qtmscore'] > best[a]['qtmscore']: best[a] = r
sel = sorted([r for r in best.values() if r['qtmscore'] >= 0.50], key=lambda r: -r['qtmscore'])
print(f"{len(sel)} proteins to verify\n")

nohit = set(open(os.path.expanduser('~/Downloads/259_nohit_accessions.txt')).read().split())
meta_cache = {}
def entry_meta(pdb):
    """title + source organisms, from the RCSB REST API"""
    if pdb in meta_cache: return meta_cache[pdb]
    title, orgs = '?', []
    try:
        u = f'https://data.rcsb.org/rest/v1/core/entry/{pdb}'
        d = json.load(urllib.request.urlopen(u, timeout=30))
        title = d.get('struct', {}).get('title', '?')
        n = d.get('rcsb_entry_info', {}).get('polymer_entity_count', 0)
        for i in range(1, min(n, 40) + 1):
            try:
                ue = f'https://data.rcsb.org/rest/v1/core/polymer_entity/{pdb}/{i}'
                e = json.load(urllib.request.urlopen(ue, timeout=30))
                for s in e.get('rcsb_entity_source_organism', []) or []:
                    nm = s.get('scientific_name')
                    if nm and nm not in orgs: orgs.append(nm)
            except Exception: pass
    except Exception as ex:
        title = f'(lookup failed: {ex})'
    meta_cache[pdb] = (title, orgs); time.sleep(0.3); return meta_cache[pdb]

def fetch_chain(pdb, ch):
    """download mmCIF, write the single matched chain as PDB"""
    cif = os.path.join(OUT, 'cif', f'{pdb}.cif')
    if not os.path.exists(cif):
        urllib.request.urlretrieve(f'https://files.rcsb.org/download/{pdb}.cif', cif)
    outp = os.path.join(OUT, 'chains', f'{pdb}_{ch}.pdb')
    if os.path.exists(outp): return outp
    # minimal mmCIF -> PDB for one auth chain, CA-containing ATOM records
    keys, rows, in_loop, hdr = [], [], False, []
    for l in open(cif, errors='ignore'):
        if l.startswith('_atom_site.'):
            hdr.append(l.strip().split('.')[1]); in_loop = True; continue
        if in_loop:
            if l.startswith('#') or l.startswith('loop_'):
                if rows: break
                continue
            if l.startswith('ATOM') or l.startswith('HETATM'):
                rows.append(l.split())
            elif rows: break
    if not rows: return None
    ix = {k: i for i, k in enumerate(hdr)}
    need = ['group_PDB','label_atom_id','label_comp_id','auth_asym_id','auth_seq_id',
            'Cartn_x','Cartn_y','Cartn_z','label_alt_id','pdbx_PDB_model_num']
    if any(k not in ix for k in need): return None
    n = 0
    with open(outp, 'w') as f:
        for r in rows:
            if len(r) < len(hdr): continue
            if r[ix['group_PDB']] != 'ATOM': continue
            if r[ix['auth_asym_id']] != ch: continue
            if r[ix['pdbx_PDB_model_num']] not in ('1', '.'): continue
            alt = r[ix['label_alt_id']]
            if alt not in ('.', '?', 'A'): continue
            n += 1
            f.write("ATOM  %5d %-4s %3s %s%4s    %8.3f%8.3f%8.3f  1.00  0.00\n" % (
                n, r[ix['label_atom_id']][:4], r[ix['label_comp_id']][:3], 'A',
                r[ix['auth_seq_id']][:4], float(r[ix['Cartn_x']]), float(r[ix['Cartn_y']]), float(r[ix['Cartn_z']])))
        f.write("END\n")
    return outp if n else None

rows_out = []
for i, r in enumerate(sel, 1):
    pdb, ch = r['target'].split('-')[0], r['target'].split('_')[-1]
    qf = os.path.join(SRC, 'targets', f"AF-{r['acc']}-F1-model_v6.pdb")
    us_q = us_t = float('nan'); note = ''
    try:
        tf = fetch_chain(pdb, ch)
        if tf:
            o = subprocess.run([US, qf, tf, '-outfmt', '2'], capture_output=True, text=True, timeout=300).stdout
            ln = [x for x in o.splitlines() if x and not x.startswith('#')]
            if ln:
                f = ln[0].split('\t'); us_q, us_t = float(f[2]), float(f[3])
        else:
            note = 'chain extraction failed'
    except Exception as ex:
        note = f'{type(ex).__name__}'
    title, orgs = entry_meta(pdb)
    pf = any('falciparum' in o.lower() or 'plasmodium' in o.lower() for o in orgs)
    rows_out.append(dict(acc=r['acc'], group='no-hit' if r['acc'] in nohit else 'partial-hit',
        pdb=pdb, chain=ch, foldseek_qtm=round(r['qtmscore'],3), cov=round(r['cov'],2),
        usalign_q=round(us_q,3) if us_q == us_q else '', usalign_t=round(us_t,3) if us_t == us_t else '',
        plasmodium='YES' if pf else 'no', organisms='; '.join(orgs[:4]), title=title[:90], note=note))
    if i % 10 == 0 or i == len(sel): print(f'  {i}/{len(sel)} done')

with open(os.path.join(OUT, 'verification.tsv'), 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=list(rows_out[0].keys()), delimiter='\t'); w.writeheader(); w.writerows(rows_out)

ok = [r for r in rows_out if r['usalign_q'] != '' and float(r['usalign_q']) >= 0.50]
pfm = [r for r in rows_out if r['plasmodium'] == 'YES']
rep = open(os.path.join(OUT, 'SUMMARY.txt'), 'w')
def w2(s=''): print(s); rep.write(s + '\n')
w2(f"Foldseek proposed {len(rows_out)} proteins with a PDB100 match at query-normalised TM >= 0.50")
w2(f"  confirmed by US-align (TM >= 0.50) : {len(ok)}")
w2(f"  matched entry contains Plasmodium   : {len(pfm)}   <-- own structure solved, not a shared fold")
w2("")
w2(f"{'acc':<12}{'group':<13}{'PDB':<7}{'fs_qTM':>7}{'US_q':>7}{'Plasmo':>8}  title")
for r in sorted(rows_out, key=lambda r: -(float(r['usalign_q']) if r['usalign_q'] != '' else 0))[:40]:
    w2(f"{r['acc']:<12}{r['group']:<13}{r['pdb']:<7}{r['foldseek_qtm']:>7}{str(r['usalign_q']):>7}{r['plasmodium']:>8}  {r['title'][:60]}")
w2("")
w2("Full table: verification.tsv")
rep.close()
PYEOF

echo ""
echo "DONE. Results in: $OUT"
echo "Key file: SUMMARY.txt"
read -p "Press Enter to close"
