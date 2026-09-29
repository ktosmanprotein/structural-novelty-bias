# structural-novelty-bias

Code for *Three correctable biases inflate estimates of structural novelty from
predicted-structure databases*.

Every numeric value in the manuscript and figures is generated from the source
tables at build time. Nothing is transcribed by hand, so a discrepancy between
the text and the data surfaces as a build failure rather than as a silent error.

## Reproducing the paper

```
python3 audit_numbers.py     # source tables -> numbers.json
python3 build_ms.py          # manuscript .docx
```

`audit_numbers.py` must run first: it writes `numbers.json`, from which the
manuscript builder and the figure code both read. Every value plotted in the
figures, including the exact binomial confidence intervals in Fig 1B, is
computed there rather than at plotting time; the rendering scripts only style
what is already in `numbers.json`, so they are not included here.

## What each script does

| Script | Purpose |
|---|---|
| `audit_numbers.py` | Recomputes every reported value from the source tables into `numbers.json` |
| `build_ms.py` | Builds the manuscript, pulling all numbers from `numbers.json` |
| `run_pdb100_crossspecies.command` | Panel-wide PDB100 correction, 8,011 structures |
| `finish_pdb100_crossspecies.command` | Fast finisher for the above (batched organism lookup) |
| `verify_pdb100_hits.command` | US-align confirmation of *P. falciparum* PDB100 candidates |
| `run_afdb_darkcluster_reanalysis.command` | AFDB dark-cluster re-analysis, releases v3 and v6 |
| `make_derived_tables.py` | Writes the per-protein tables the data deposit promises |
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
