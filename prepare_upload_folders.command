#!/bin/bash
# =============================================================================
# Assemble upload-ready folders for Paper 1
#
#   ~/Downloads/paper1_upload/github/   -> push to GitHub (code, MIT licence)
#   ~/Downloads/paper1_upload/zenodo/   -> upload to Zenodo (derived data)
#
#   WHAT GOES WHERE, AND WHY
#   GitHub gets the code: every script, plus a README that tells a reader how to
#   reproduce each figure and each number. Small, diffable, version-controlled.
#
#   Zenodo gets the derived data tables: the per-protein novelty calls, the
#   verification output, the corrected panel, the AFDB re-analysis. These are the
#   files a reader needs to check a claim without re-running a 4-hour search.
#
#   DELIBERATELY EXCLUDED (re-downloadable or regenerable, several GB):
#     - raw Foldseek .m8 alignment output (1.6 GB + 188 MB)
#     - downloaded mmCIF files from the PDB (1.8 GB)
#     - downloaded AlphaFold structures (1.5 GB)
#     - the AFDB cluster source file (48 MB, one URL)
#   Each is documented in the Zenodo README with its source, so the deposit is
#   complete as a record without being bloated.
#
# Double-click, or:  bash ~/Downloads/paper1_methods/prepare_upload_folders.command
# =============================================================================
set -e
D="$HOME/Downloads"
P="$D/paper1_methods"
AP="$HOME/apico_structural_analysis"
OUT="$D/paper1_upload"
GH="$OUT/structural-novelty-bias"
ZE="$OUT/zenodo"
rm -rf "$OUT"
mkdir -p "$GH"/scripts "$ZE"/{01_novelty_tables,02_pdb100_verification,03_panel_correction,04_afdb_reanalysis,05_figure_source}
exec > >(tee "$OUT/prepare.log") 2>&1
echo "=== Assembling upload folders ==="
echo ""

# ---------------------------------------------------------------- GITHUB ----
echo "--- GitHub repo: structural-novelty-bias ---"
# Figure-rendering and structure-image scripts are NOT shipped. Every value they
# draw, including the exact binomial intervals in Fig 1B, is computed by
# audit_numbers.py into numbers.json; the plotting code only styles it.
for f in audit_numbers.py build_ms.py make_derived_tables.py \
         run_afdb_darkcluster_reanalysis.command prepare_upload_folders.command; do
  [ -f "$P/$f" ] && cp "$P/$f" "$GH/scripts/" && echo "  scripts/$f"
done
for f in "$D/run_pdb100_crossspecies.command" "$D/finish_pdb100_crossspecies.command" \
         "$D/verify_pdb100_hits.command" "$D/run_pdb100_and_esmatlas.command"; do
  [ -f "$f" ] && cp "$f" "$GH/scripts/" && echo "  scripts/$(basename $f)"
done
# Rendered figures are deliberately NOT committed: they are build outputs, they
# go stale the moment a figure script changes, and p1_fig*.py regenerate them
# from numbers.json. The published versions travel with the paper and the
# Zenodo record instead.

cat > "$GH/LICENSE" <<'EOF'
MIT License

Copyright (c) 2026 Khan Osman

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF

cat > "$GH/.gitignore" <<'EOF'
# large regenerable / re-downloadable inputs
*.m8
*.cif
*.tsv.gz
structures/
cif/
chains/
queries/
renders/*.pse
__pycache__/
*.pyc
.DS_Store
EOF

cat > "$GH/requirements.txt" <<'EOF'
# Python 3.10 or later
matplotlib==3.10.9
numpy
pillow
python-docx
# External tools (not pip-installable):
#   Foldseek  8.ef4e960  (forward searches)
#   Foldseek 10.941cd33  (PDB100 searches)
#   US-align             (independent re-scoring)
#   PyMOL                (structure renders)
EOF

cat > "$GH/README.md" <<'EOF'
# structural-novelty-bias

Code for *Three correctable biases inflate estimates of structural novelty from
predicted-structure databases*.

Every numeric value in the manuscript and figures is generated from the source
tables at build time. Nothing is transcribed by hand, so a discrepancy between
the text and the data surfaces as a build failure rather than as a silent error.

## Reproducing the paper

```
python3 scripts/audit_numbers.py     # source tables -> numbers.json
python3 scripts/build_ms.py          # manuscript .docx
```

`audit_numbers.py` must run first: it writes `numbers.json`, which every figure
script and the manuscript builder read.

## What each script does

| Script | Purpose |
|---|---|
| `audit_numbers.py` | Recomputes every reported value from the source tables into `numbers.json` |
| `build_ms.py` | Builds the manuscript, pulling all numbers from `numbers.json` |
| `render_p1_structures.command` | PyMOL renders: confidence gradient and superpositions |
| `run_pdb100_crossspecies.command` | Panel-wide PDB100 correction, 8,011 structures |
| `finish_pdb100_crossspecies.command` | Fast finisher for the above (batched organism lookup) |
| `verify_pdb100_hits.command` | US-align confirmation of *P. falciparum* PDB100 candidates |
| `run_afdb_darkcluster_reanalysis.command` | AFDB dark-cluster re-analysis, releases v3 and v6 |
| `prepare_upload_folders.command` | Assembles this repository and the Zenodo deposit |

## Data

Derived data tables are deposited on Zenodo:
[10.5281/zenodo.23045417](https://doi.org/10.5281/zenodo.23045417). Large inputs
are not redistributed here and are re-obtainable from their sources:

- AlphaFold structures: https://alphafold.ebi.ac.uk (v6)
- AFDB cluster data: https://cluster.foldseek.com (CC-BY 4.0)
- PDB entries: https://www.rcsb.org
- UniProt reference proteomes: https://www.uniprot.org

## Dependencies

See `requirements.txt`. External tools: Foldseek (8.ef4e960 for forward
searches, 10.941cd33 for PDB100), US-align, PyMOL.

## Licence

MIT (see `LICENSE`). Re-analysed AFDB cluster data are CC-BY 4.0,
Barrio-Hernandez et al., *Nature* 2023.
EOF
echo "  LICENSE, .gitignore, requirements.txt, README.md"

# ---------------------------------------------------------------- ZENODO ----
echo ""
echo "--- Zenodo: derived data ---"
n=0
for f in "$AP"/results/novelty/*_novelty.tsv; do
  [ -f "$f" ] && cp "$f" "$ZE/01_novelty_tables/" && n=$((n+1))
done
echo "  01_novelty_tables/  $n per-genome tables"
[ -f "$AP/data/proteomes/_panel_summary.tsv" ] && cp "$AP/data/proteomes/_panel_summary.tsv" "$ZE/01_novelty_tables/"
[ -f "$D/apicofold/config/species.tsv" ] && cp "$D/apicofold/config/species.tsv" "$ZE/01_novelty_tables/panel_species.tsv"

for f in verification.tsv tiers.tsv novel_211_accessions.txt removed_105_accessions.txt \
         ss_211.tsv partial_180.txt true_nohit_31.txt SUMMARY.txt; do
  [ -f "$D/pdb100_verification/$f" ] && cp "$D/pdb100_verification/$f" "$ZE/02_pdb100_verification/"
done
echo "  02_pdb100_verification/  $(ls "$ZE/02_pdb100_verification" | wc -l | tr -d ' ') files"

for f in panel_corrected.tsv reassigned_per_protein.tsv panel_baseline.tsv SUMMARY.txt entry_organisms.json; do
  [ -f "$D/pdb100_crossspecies/$f" ] && cp "$D/pdb100_crossspecies/$f" "$ZE/03_panel_correction/"
done
echo "  03_panel_correction/  $(ls "$ZE/03_panel_correction" | wc -l | tr -d ' ') files"

for f in SUMMARY.txt dark_by_plddt_band.tsv; do
  [ -f "$P/afdb_reanalysis/$f" ] && cp "$P/afdb_reanalysis/$f" "$ZE/04_afdb_reanalysis/"
done
echo "  04_afdb_reanalysis/  $(ls "$ZE/04_afdb_reanalysis" | wc -l | tr -d ' ') files"

[ -f "$P/numbers.json" ] && cp "$P/numbers.json" "$ZE/05_figure_source/"
[ -f "$D/pf_reanalysis_out/novelty_by_confidence.tsv" ] && cp "$D/pf_reanalysis_out/novelty_by_confidence.tsv" "$ZE/05_figure_source/"
[ -f "$D/ss_316.tsv" ] && cp "$D/ss_316.tsv" "$ZE/05_figure_source/"
[ -f "$D/cross_species_out/cross_species_summary.tsv" ] && cp "$D/cross_species_out/cross_species_summary.tsv" "$ZE/05_figure_source/"
for o in H_sapiens S_cerevisiae_S288C E_coli_K-12 T_gondii_ME49; do
  [ -f "$D/cross_species_out/$o/novelty.tsv" ] && cp "$D/cross_species_out/$o/novelty.tsv" "$ZE/05_figure_source/${o}_novelty.tsv"
done
echo "  05_figure_source/  $(ls "$ZE/05_figure_source" | wc -l | tr -d ' ') files"

cat > "$ZE/README.md" <<'EOF'
# Data for: Three correctable biases inflate estimates of structural novelty from predicted-structure databases

Khan Osman. Deposited under CC-BY 4.0.

These are the derived tables underlying every figure and numeric claim in the
manuscript. Analysis code: https://github.com/ktosmanprotein/structural-novelty-bias

## Contents

### 01_novelty_tables/
Per-protein novelty calls for all 135,523 proteins across the 15-species
alveolate panel, one file per genome. Columns: accession, species, clade,
gene and VEuPathDB identifiers, protein name, hypothetical flag, length, mean
pLDDT, ordered fraction, best target, best TM-score, E-value, query coverage,
verdict. `panel_species.tsv` gives the pinned UniProt reference-proteome
accessions and taxon identifiers with the date they were verified.

### 02_pdb100_verification/
PDB100 search and independent confirmation for the 316 confident novel-fold
*P. falciparum* proteins. `verification.tsv` gives, for each of the 137
candidates, the Foldseek and US-align query-normalised TM-scores, matched PDB
entry and chain, source organism and entry title. `tiers.tsv` groups the 105
confirmed matches by evidence strength. Accession lists give the resulting sets.

### 03_panel_correction/
Panel-wide PDB100 correction applied identically to all 15 genomes.
`panel_corrected.tsv` gives per-genome novel-fold rates before and after, with
own-genus counts. `reassigned_per_protein.tsv` lists every reassignment with its
matched entry and source organism.

### 04_afdb_reanalysis/
Re-analysis of the AlphaFold Database dark-cluster fraction under confidence
filtering, for releases v3 and v6. `dark_by_plddt_band.tsv` gives the dark
fraction by representative pLDDT band for each release.

### 05_figure_source/
`numbers.json` is the single file from which every figure and every numeric
claim in the manuscript is generated. Also included: the *P. falciparum* pLDDT
band table, secondary-structure table, and the five-organism comparison used to
demonstrate the self-matching artefact.

## Not included here

The following are large and obtainable from their original sources:

| Excluded | Size | Source |
|---|---|---|
| Foldseek alignment output (.m8) | ~1.8 GB | Regenerate with the scripts in the repository |
| AlphaFold structures | ~1.5 GB | https://alphafold.ebi.ac.uk (v6) |
| PDB mmCIF entries | ~1.8 GB | https://www.rcsb.org |
| AFDB cluster source file | 48 MB | https://cluster.foldseek.com (CC-BY 4.0) |

## Attribution

The AFDB cluster data re-analysed in `04_afdb_reanalysis/` were published by
Barrio-Hernandez et al., *Nature* 2023, under CC-BY 4.0.
EOF

# checksums for both
( cd "$GH" && find . -type f ! -name SHA256SUMS -exec shasum -a 256 {} \; > SHA256SUMS )
( cd "$ZE" && find . -type f ! -name SHA256SUMS -exec shasum -a 256 {} \; > SHA256SUMS )

# Tables the Data availability section promises that no earlier stage writes.
python3 "$P/make_derived_tables.py" "$D"

echo ""
echo "=== Done ==="
printf "  structural-novelty-bias : %s  (%s files)\n" "$(du -sh "$GH" | cut -f1)" "$(find "$GH" -type f | wc -l | tr -d ' ')"
printf "  zenodo : %s  (%s files)\n" "$(du -sh "$ZE" | cut -f1)" "$(find "$ZE" -type f | wc -l | tr -d ' ')"
echo ""
echo "Folders: $OUT"
read -p "Press Enter to close"
