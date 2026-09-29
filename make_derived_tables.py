# -*- coding: utf-8 -*-
"""Derived tables the Data availability section promises but that no earlier
stage wrote out.

Run after prepare_upload_folders.command has staged the Zenodo tree; it adds

  03_panel_correction/queried_per_protein.tsv   all 8,011 PDB100 queries
  05_figure_source/self_match_counts.tsv        the five-organism self-hit counts

The first matters because reassigned_per_protein.tsv holds only the 3,073
proteins PDB100 moved to a known fold. Without the other 4,938 a reader cannot
see the denominator, and the manuscript claims coverage of all 8,011.

Usage:  python3 make_derived_tables.py <downloads_dir>
"""
import csv, glob, json, os, sys

HOME = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser('~/Downloads')
Z = os.path.join(HOME, 'paper1_upload', 'zenodo')
XS = os.path.join(HOME, 'pdb100_crossspecies')
NUMBERS = os.path.join(HOME, 'paper1_methods', 'numbers.json')

# Same predicate run_pdb100_crossspecies.command used to stage query structures.
NOVELISH = {'novel', 'no_hit', 'twilight'}


def build_queried_table():
    q = {}
    for f in sorted(glob.glob(os.path.join(Z, '01_novelty_tables', '*_novelty.tsv'))):
        with open(f, encoding='utf-8') as fh:
            for r in csv.DictReader(fh, delimiter='\t'):
                if r['verdict'] in NOVELISH and r['hypothetical'] == '1':
                    q[r['accession']] = (r['species_key'], r['label'], r['verdict'],
                                         r['best_tmscore'], r['mean_plddt'], r['length'])

    # Cross-check against what the run actually staged, per species. A mismatch
    # means the novelty tables and the PDB100 run have drifted apart, which
    # would silently invalidate the correction.
    base = os.path.join(Z, '03_panel_correction', 'panel_baseline.tsv')
    if os.path.exists(base):
        staged = {r['species_key']: int(r['staged'])
                  for r in csv.DictReader(open(base, encoding='utf-8'), delimiter='\t')}
        got = {}
        for sk, *_ in q.values():
            got[sk] = got.get(sk, 0) + 1
        bad = {k: (got.get(k, 0), v) for k, v in staged.items() if got.get(k, 0) != v}
        if bad:
            raise SystemExit(f'  ERROR: reconstructed query set does not match staged counts: {bad}')

    m8 = os.path.join(XS, 'pdb100_panel_hits.m8')
    best = {}
    if os.path.exists(m8):
        with open(m8, encoding='utf-8') as fh:
            for line in fh:
                p = line.rstrip('\n').split('\t')
                if len(p) < 10:
                    continue
                acc = p[0].split('-')[1] if p[0].startswith('AF-') else p[0]
                try:
                    s = float(p[3])          # qtmscore: query-normalised
                except ValueError:
                    continue
                if acc not in best or s > best[acc][1]:
                    best[acc] = (p[1], s, p[5])
    else:
        print(f'  note: {m8} absent; PDB100 columns will be blank')

    of = os.path.join(XS, 'entry_organisms.json')
    org = json.load(open(of, encoding='utf-8')) if os.path.exists(of) else {}
    rf = os.path.join(Z, '03_panel_correction', 'reassigned_per_protein.tsv')
    reass = {r['accession']: r for r in
             csv.DictReader(open(rf, encoding='utf-8'), delimiter='\t')} if os.path.exists(rf) else {}

    out = os.path.join(Z, '03_panel_correction', 'queried_per_protein.tsv')
    with open(out, 'w', newline='', encoding='utf-8') as fh:
        w = csv.writer(fh, delimiter='\t')
        w.writerow(['accession', 'species_key', 'label', 'verdict_afsp', 'best_afsp_tmscore',
                    'mean_plddt', 'length', 'best_pdb100_target', 'best_pdb100_qtm',
                    'best_pdb100_prob', 'reassigned_by_pdb100', 'own_genus', 'entry_organisms'])
        for acc, (sk, lab, v, tm, pl, ln) in sorted(q.items(), key=lambda x: (x[1][0], x[0])):
            b, rr = best.get(acc), reass.get(acc)
            w.writerow([acc, sk, lab, v, tm, pl, ln,
                        b[0] if b else '', f'{b[1]:.4f}' if b else '', b[2] if b else '',
                        '1' if rr else '0',
                        (rr or {}).get('own_genus', ''),
                        (rr or {}).get('entry_organisms', '') or
                        (';'.join(org.get(b[0], [])) if b else '')])
    print(f'  queried_per_protein.tsv      {len(q):,} rows ({len(reass):,} reassigned)')


def build_self_match_table():
    if not os.path.exists(NUMBERS):
        print('  note: numbers.json absent; skipping self_match_counts.tsv')
        return
    N = json.load(open(NUMBERS, encoding='utf-8'))
    out = os.path.join(Z, '05_figure_source', 'self_match_counts.tsv')
    with open(out, 'w', newline='', encoding='utf-8') as fh:
        w = csv.writer(fh, delimiter='\t')
        w.writerow(['organism', 'proteins_with_hit', 'hits_to_own_proteome', 'pct_self'])
        for k, v in N['self_hits'].items():
            w.writerow([k, v['with_hit'], v['self_hits'], f"{v['pct']:.1f}"])
    print(f"  self_match_counts.tsv        {len(N['self_hits'])} organisms")


def patch_readme():
    """The README is rewritten from scratch by prepare_upload_folders.command,
    so the descriptions of these two files have to be reapplied here."""
    p = os.path.join(Z, 'README.md')
    if not os.path.exists(p):
        return
    s = open(p, encoding='utf-8').read()
    if 'queried_per_protein' in s:
        return

    s = s.replace(
        "`reassigned_per_protein.tsv` lists every reassignment with its\nmatched entry and source organism.",
        "`queried_per_protein.tsv` covers all 8,011 structures that\n"
        "were searched against PDB100, whether or not they were reassigned, giving the\n"
        "AlphaFold/Swiss-Prot verdict, the best PDB100 target and query-normalised\n"
        "TM-score, and the own-genus flag. `reassigned_per_protein.tsv` is the 3,073-row\n"
        "subset that PDB100 moved to a known fold.")

    s = s.replace(
        "band table, secondary-structure table, and the five-organism comparison used to\ndemonstrate the self-matching artefact.",
        "band table, secondary-structure table, and the five-organism comparison used to\n"
        "demonstrate the self-matching artefact. `self_match_counts.tsv` gives, for each\n"
        "of those organisms, how many of its confidently novel hypothetical proteins\n"
        "matched an entry from its own proteome: the counts that make three of the five\n"
        "bars uninterpretable.")

    tag = '## Not included here'
    if tag in s:
        i = s.index(tag)
        j = s.find('\n## ', i + 1)
        s = s[:i] + (
            "## Not included here\n"
            "The raw Foldseek alignment output for the forward searches (20.9 million rows\n"
            "across the 15 genomes, about 1.6 GB) is not deposited. The per-protein best-hit\n"
            "summary in `01_novelty_tables/` carries the columns every reported number\n"
            "depends on: best target, TM-score, E-value and query coverage. The full output\n"
            "regenerates exactly from the deposited scripts and the pinned proteome panel,\n"
            "and is available from the author on request.\n") + (s[j:] if j != -1 else '')
    open(p, 'w', encoding='utf-8').write(s)
    print('  README.md                    descriptions reapplied')


if __name__ == '__main__':
    print('--- derived tables ---')
    build_queried_table()
    build_self_match_table()
    patch_readme()
