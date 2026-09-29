import math
"""Regenerates every number Paper 1 cites, from source files only. No hardcoding."""
import csv, glob, os, json, re, statistics as st
DL='/sessions/clever-sharp-pasteur/mnt/Downloads'
AP='/sessions/clever-sharp-pasteur/mnt/apico_structural_analysis'
OUT={}
def f(x):
    try: return float(x)
    except: return None

# ---- 1. CONFIDENCE BIAS -----------------------------------------------------
bands=list(csv.DictReader(open(f'{DL}/pf_reanalysis_out/novelty_by_confidence.tsv'),delimiter='\t'))

# --- exact binomial confidence intervals -------------------------------------
# Clopper-Pearson, via the incomplete beta function (scipy is not a dependency).
# These belong here, not in the plotting code: they are a reported statistical
# result, so they have to live in numbers.json alongside every other number the
# manuscript cites. The top pLDDT band is 0 of 134, where the normal
# approximation is not valid, which is why the exact interval is used.
def _betacf(a, b, x, itmax=200, eps=3e-12):
    qab, qap, qam = a + b, a + 1.0, a - 1.0
    c, d = 1.0, 1.0 - qab * x / qap
    if abs(d) < 1e-30: d = 1e-30
    d = 1.0 / d; h = d
    for m in range(1, itmax + 1):
        m2 = 2 * m
        aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1.0 + aa * d; c = 1.0 + aa / c
        if abs(d) < 1e-30: d = 1e-30
        if abs(c) < 1e-30: c = 1e-30
        d = 1.0 / d; h *= d * c
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1.0 + aa * d; c = 1.0 + aa / c
        if abs(d) < 1e-30: d = 1e-30
        if abs(c) < 1e-30: c = 1e-30
        d = 1.0 / d; de = d * c; h *= de
        if abs(de - 1.0) < eps: break
    return h


def betainc(a, b, x):
    if x <= 0.0: return 0.0
    if x >= 1.0: return 1.0
    lbeta = (math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b)
             + a * math.log(x) + b * math.log(1.0 - x))
    if x < (a + 1.0) / (a + b + 2.0):
        return math.exp(lbeta) * _betacf(a, b, x) / a
    return 1.0 - math.exp(lbeta) * _betacf(b, a, 1.0 - x) / b


def _beta_ppf(q, a, b, tol=1e-10):
    lo, hi = 0.0, 1.0
    for _ in range(200):
        mid = (lo + hi) / 2.0
        if betainc(a, b, mid) < q: lo = mid
        else: hi = mid
        if hi - lo < tol: break
    return (lo + hi) / 2.0


def clopper_pearson(k, n, alpha=0.05):
    """Exact binomial interval, returned as percentages."""
    if n == 0: return (0.0, 100.0)
    lo = 0.0 if k == 0 else _beta_ppf(alpha / 2, k, n - k + 1)
    hi = 1.0 if k == n else _beta_ppf(1 - alpha / 2, k + 1, n - k)
    return (lo * 100.0, hi * 100.0)


OUT['pf_plddt_bands']=[(b['plddt_band'],int(b['n']),int(b['n_novel']),float(b['pct_novel']))
                       for b in bands]
# 5th and 6th fields: exact binomial 95% CI, low and high, in percent.
OUT['pf_plddt_bands']=[t+tuple(round(v,4) for v in clopper_pearson(t[2],t[1]))
                       for t in OUT['pf_plddt_bands']]
OUT['pf_bands_total_n']=sum(int(b['n']) for b in bands)
OUT['pf_bands_total_novel']=sum(int(b['n_novel']) for b in bands)

infl=[]
for p in sorted(glob.glob(f'{AP}/results/novelty/*_novelty.tsv')):
    k=os.path.basename(p).replace('_novelty.tsv','')
    R=[r for r in csv.DictReader(open(p),delimiter='\t') if r['hypothetical']=='1']
    mod=[r for r in R if r['verdict']!='no_model']
    conf=[r for r in mod if r['verdict']!='low_confidence']
    def nv(rows): return sum(1 for r in rows if (f(r['best_tmscore']) is None or f(r['best_tmscore'])<0.50))
    if not conf: continue
    u=nv(mod)/len(mod)*100; c=nv(conf)/len(conf)*100
    infl.append(dict(key=k,label=R[0]['label'],n_models=len(mod),unfilt=u,n_conf=len(conf),filt=c,ratio=u/c))
OUT['inflation']=infl
OUT['inflation_median']=st.median(x['ratio'] for x in infl)
OUT['inflation_range']=(min(x['ratio'] for x in infl),max(x['ratio'] for x in infl))

# ---- 2. DATABASE SCOPE ------------------------------------------------------
V=list(csv.DictReader(open(f'{DL}/pdb100_verification/verification.tsv'),delimiter='\t'))
conf_ok=[r for r in V if r['usalign_q'] and float(r['usalign_q'])>=0.50]
OUT['pf_candidates']=len(V); OUT['pf_confirmed']=len(conf_ok)
OUT['pf_confirm_rate']=len(conf_ok)/len(V)*100
OUT['pf_novel_before']=316; OUT['pf_novel_after']=316-len(conf_ok)
OUT['pf_denom']=1017
T=list(csv.DictReader(open(f'{DL}/pdb100_verification/tiers.tsv'),delimiter='\t'))
OUT['tiers']={t:sum(1 for r in T if r['tier']==t) for t in ('1','2','3')}
def cat(r):
    t=r['title'].lower()
    if 'toxoplasma gondii mitochondrial atp syn' in t: return 'ATP synthase'
    if 'ribosom' in t: return 'ribosome/mitoribosome'
    return 'other'
from collections import Counter
OUT['pf_assign_cat']=dict(Counter(cat(r) for r in conf_ok))

# ---- 3. DATABASE REPRESENTATION (self-hits) --------------------------------
sh={}
for d,lab in [('H_sapiens','H. sapiens'),('S_cerevisiae_S288C','S. cerevisiae'),
              ('E_coli_K-12','E. coli'),('T_gondii_ME49','T. gondii')]:
    best={}
    for l in open(f'{DL}/cross_species_out/{d}/foldseek.m8'):
        p=l.rstrip('\n').split('\t')
        m=re.search(r'AF-(.+?)-F1',p[0]); q=m.group(1) if m else p[0]
        mt=re.search(r'AF-(.+?)-F1',p[1]); t=mt.group(1) if mt else p[1]
        v=f(p[2])
        if v is None: continue
        if q not in best or v>best[q][0]: best[q]=(v,t)
    s=sum(1 for q,(v,t) in best.items() if q==t)
    sh[lab]=dict(with_hit=len(best),self_hits=s,pct=s/len(best)*100)
OUT['self_hits']=sh
cs={r['label']:r for r in csv.DictReader(open(f'{DL}/cross_species_out/cross_species_summary.tsv'),delimiter='\t')}
OUT['outgroup_reported']={k:(int(v['n_confident']),float(v['pct_novel'])) for k,v in cs.items()}

# ---- 4. CORRECTED PANEL -----------------------------------------------------
P=list(csv.DictReader(open(f'{DL}/pdb100_crossspecies/panel_corrected.tsv'),delimiter='\t'))
OUTG={'pmarinus','tthermophila','vbrassicaformis'}
for p in P:
    p['grp']='OUT' if p['species_key'] in OUTG else 'APIC'
    p['reass_rate']=int(p['reassigned_by_pdb100'])/int(p['novelish_afsp'])*100
OUT['panel']=P
for g in ('APIC','OUT'):
    s=[p for p in P if p['grp']==g]
    OUT[f'{g}_mean_drop']=st.mean(float(p['drop_points']) for p in s)
    OUT[f'{g}_mean_reass_rate']=st.mean(p['reass_rate'] for p in s)

json.dump(OUT,open('numbers.json','w'),indent=1,default=str)

# ---- REPORT -----------------------------------------------------------------
print("="*78); print("PAPER 1 — VERIFIED NUMBERS"); print("="*78)
print("\n[1] CONFIDENCE BIAS")
print(f"  Pf pLDDT bands (n={OUT['pf_bands_total_n']:,} with alignments, {OUT['pf_bands_total_novel']} novel):")
for b,n,nn,p,lo,hi in OUT['pf_plddt_bands']:
    print(f"     {b:<8} n={n:>4}  novel={nn:>3}  {p:>5.2f}%   95% CI {lo:>5.2f}-{hi:>5.2f}")
print(f"  Inflation across {len(infl)} genomes: median {OUT['inflation_median']:.2f}x  range {OUT['inflation_range'][0]:.2f}-{OUT['inflation_range'][1]:.2f}x")
pf=[x for x in infl if x['key']=='pfalciparum'][0]
print(f"  P. falciparum: {pf['unfilt']:.1f}% unfiltered (n={pf['n_models']:,}) -> {pf['filt']:.1f}% filtered (n={pf['n_conf']:,}) = {pf['ratio']:.2f}x")
print("\n[2] DATABASE SCOPE")
print(f"  Pf: {OUT['pf_candidates']} Foldseek candidates -> {OUT['pf_confirmed']} US-align confirmed ({OUT['pf_confirm_rate']:.0f}%)")
print(f"  novel-fold {OUT['pf_novel_before']} -> {OUT['pf_novel_after']}  ({OUT['pf_novel_before']/OUT['pf_denom']*100:.1f}% -> {OUT['pf_novel_after']/OUT['pf_denom']*100:.1f}% of {OUT['pf_denom']:,})")
print(f"  tiers: {OUT['tiers']}   assignment categories: {OUT['pf_assign_cat']}")
print("\n[3] DATABASE REPRESENTATION")
for k,v in sh.items(): print(f"  {k:<14} {v['self_hits']:>4}/{v['with_hit']:<4} self-hits = {v['pct']:>5.1f}%")
print("\n[4] CORRECTED PANEL")
print(f"  APIC mean drop {OUT['APIC_mean_drop']:.1f} pts, reass rate {OUT['APIC_mean_reass_rate']:.1f}%")
print(f"  OUT  mean drop {OUT['OUT_mean_drop']:.1f} pts, reass rate {OUT['OUT_mean_reass_rate']:.1f}%")
print("\n[COMBINED, P. falciparum]")
print(f"  {pf['unfilt']:.1f}% unfiltered -> {OUT['pf_novel_after']/OUT['pf_denom']*100:.1f}% fully corrected = {pf['unfilt']/(OUT['pf_novel_after']/OUT['pf_denom']*100):.2f}x total inflation")
print("\nwrote numbers.json")


# --- AFDB re-analysis ---------------------------------------------------------
# Parsed back out of run_afdb_darkcluster_reanalysis.command's own output rather
# than recomputed: that stage re-reads two multi-gigabyte cluster files. Reading
# it here means audit_numbers.py can be run on its own without silently dropping
# the AFDB keys from numbers.json, which is exactly what happened once.
def _load_afdb(d=os.path.join(os.path.dirname(os.path.abspath(__file__)), 'afdb_reanalysis')):
    band_f = os.path.join(d, 'dark_by_plddt_band.tsv')
    sum_f = os.path.join(d, 'SUMMARY.txt')
    if not (os.path.exists(band_f) and os.path.exists(sum_f)):
        return None, None
    bands = {'v3': [], 'v6': []}
    with open(band_f, encoding='utf-8') as fh:
        next(fh)
        for line in fh:
            p = line.rstrip('\n').split('\t')
            if len(p) >= 5:
                bands[p[0]].append([p[1], int(p[2]), int(p[3]), float(p[4])])
    txt = open(sum_f, encoding='utf-8').read()
    afdb, cur = {}, None
    for line in txt.split('\n'):
        m = re.match(r'^RELEASE (V\d)$', line.strip())
        if m:
            cur = m.group(1).lower(); afdb[cur] = {}
            continue
        if cur is None:
            continue
        s = line.strip()
        for key, pat in (
                ('clusters',     r'^clusters\s*:\s*([\d,]+)'),
                ('dark',         r'^dark clusters\s*:\s*([\d,]+)'),
                ('pct_pub',      r'^dark fraction as published\s*:\s*([\d.]+)%'),
                ('pct_filt',     r'^dark fraction after filtering\s*:\s*([\d.]+)%'),
                ('fold',         r'\(([\d.]+)-fold change\)'),
                ('pct_removed',  r'^dark clusters removed\s*:.*\(([\d.]+)%\)'),
                ('pct_plddt_lt70', r'^dark with rep pLDDT < 70\s*:.*\(([\d.]+)% of dark\)'),
                ('z',            r'Cochran-Armitage z = (-?[\d.]+)')):
            m = re.search(pat, s)
            if m and key not in afdb[cur]:
                v = m.group(1).replace(',', '')
                afdb[cur][key] = int(v) if key in ('clusters', 'dark') else float(v)
        m = re.search(r'representative pLDDT median\s*:\s*dark ([\d.]+)\s*\|\s*non-dark ([\d.]+)', s)
        if m:
            afdb[cur]['med_dark'] = float(m.group(1))
            afdb[cur]['med_known'] = float(m.group(2))
    return afdb, bands


_afdb, _bands = _load_afdb()
if _afdb:
    OUT['afdb'] = _afdb
    OUT['afdb_bands'] = _bands
    json.dump(OUT, open('numbers.json', 'w'), indent=1, default=str)
    print(f"\n[5] AFDB RE-ANALYSIS (restored from afdb_reanalysis/)")
    for r in ('v3', 'v6'):
        a = _afdb[r]
        print(f"  {r}: {a['clusters']:,} clusters  {a['pct_pub']}% -> {a['pct_filt']}% "
              f"({a['fold']}x)  removed {a['pct_removed']}%  z={a['z']}")
else:
    print("\n  !! afdb_reanalysis/ not found - AFDB keys not written")
