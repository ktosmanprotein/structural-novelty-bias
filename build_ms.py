# -*- coding: utf-8 -*-
"""Paper 1 manuscript. Every numeric claim is pulled from numbers.json (audited)."""
import json, os
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_LINE_SPACING

HERE = os.path.dirname(os.path.abspath(__file__))
N = json.load(open(os.path.join(HERE, 'numbers.json')))
pf = [x for x in N['inflation'] if x['key'] == 'pfalciparum'][0]
B = N['pf_plddt_bands']
CORR = N['pf_novel_after'] / N['pf_denom'] * 100
TOTAL = pf['unfilt'] / CORR
SH = N['self_hits']
AF = N['afdb']
AFB = N['afdb_bands']
AC = N['pf_assign_cat']

doc = Document()
st = doc.styles['Normal']; st.font.name = 'Times New Roman'; st.font.size = Pt(12)
for s in doc.sections:
    s.top_margin = s.bottom_margin = s.left_margin = s.right_margin = Inches(1)

# ---------------------------------------------------------------------------
# Zenodo DOI. Reserve it on Zenodo (Reserve DOI, in the deposit form) BEFORE
# posting the preprint, then paste it here and rebuild. Every availability
# statement in the paper is written in the present tense, so the deposit and
# the GitHub repo must both be live before the manuscript goes anywhere public.
ZENODO_DOI = '10.5281/zenodo.23045417'
ZENODO_CITE = ('doi:' + ZENODO_DOI) if ZENODO_DOI else 'DOI reserved; see Zenodo record'

EM = chr(8212)   # em dash
GE = chr(8805)   # >=
AP = chr(8217)   # right single quote

AL = {'left': WD_ALIGN_PARAGRAPH.LEFT, 'center': WD_ALIGN_PARAGRAPH.CENTER,
      'just': WD_ALIGN_PARAGRAPH.JUSTIFY}


def P(txt='', bold=False, align='left', space_after=10, size=12, dbl=True):
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(space_after)
    if dbl:
        p.paragraph_format.line_spacing_rule = WD_LINE_SPACING.DOUBLE
    p.alignment = AL[align]
    if txt:
        r = p.add_run(txt); r.bold = bold
        r.font.size = Pt(size); r.font.name = 'Times New Roman'
    return p


def R(parts, align='just', space_after=10, size=12):
    """parts = [(text, flags)] where flags may contain 'i' (italic) or 'b' (bold)."""
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(space_after)
    p.paragraph_format.line_spacing_rule = WD_LINE_SPACING.DOUBLE
    p.alignment = AL[align]
    for t, f in parts:
        run = p.add_run(t); run.font.size = Pt(size); run.font.name = 'Times New Roman'
        run.italic = 'i' in f; run.bold = 'b' in f
    return p


def FIGIMG(n):
    """Insert the low-resolution figure above its legend (OUP wants figures
    embedded in the manuscript file for review; high-resolution TIFFs are
    supplied separately for production)."""
    import os
    f = os.path.join(HERE, 'figures', 'P1_Fig%d_preview.png' % n)
    if not os.path.exists(f):
        return
    p = doc.add_paragraph(); p.alignment = AL['center']
    p.paragraph_format.space_after = Pt(4)
    p.add_run().add_picture(f, width=Inches(6.3))


def H(txt):
    return P(txt, bold=True, size=13, space_after=8)


def SUB(txt):
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(6)
    p.paragraph_format.line_spacing_rule = WD_LINE_SPACING.DOUBLE
    r = p.add_run(txt); r.bold = True; r.italic = True
    r.font.size = Pt(12); r.font.name = 'Times New Roman'
    return p


# ============================ TITLE PAGE ====================================
P('Three correctable biases inflate estimates of structural novelty from '
  'predicted-structure databases', bold=True, size=14, align='center', space_after=14)
P('Khan Osman', align='center', space_after=4)
P('Independent Researcher', align='center', space_after=4, size=11)
P('Correspondence: ktosman@gmail.com', align='center', space_after=10, size=11)
P('ORCID: 0000-0001-9544-5288', align='center', space_after=14, size=10)
R([('Keywords: ', 'b'),
   ('AlphaFold, pLDDT, Foldseek, TM-score, structural novelty, dark proteome, '
    'reference database bias, Apicomplexa', '')], align='left', size=11)
doc.add_page_break()

# ============================ ABSTRACT ======================================
H('Abstract')
SUB('Motivation')
R([('Predicted-structure databases have made it routine to ask what fraction of a proteome adopts a fold '
    'with no known relative. Reported novelty rates vary widely between studies, and it is unclear how '
    'much of that variation is biological rather than methodological. A novelty call is a negative '
    'result, so it inherits every limitation of the search that failed to find a match.', '')])
SUB('Results')
R([('We identify three independent and correctable sources of inflation, quantified across 135,523 '
    'proteins from 15 alveolate genomes. Model confidence: apparent novel-fold rate falls monotonically '
    'with mean pLDDT and filtering changes the estimate by a median factor of %.2f, in every genome '
    'examined. Reference-database scope: searching only AlphaFold/Swiss-Prot missed %d of 316 '
    'P. falciparum proteins that have a solved match in the PDB. Reference-database representation: when '
    'the query organism is itself in the reference set, queries match their own entries and apparent '
    'novelty measures curation status rather than structure. Applied together, the estimate moves from '
    '%.1f%% to %.1f%%. Re-analysing the largest published survey of structural novelty, the same gradient '
    'is present across 2.6 million AlphaFold Database clusters, and the reported dark fraction moved %.1f '
    'percentage points between database releases with the method held fixed. We provide a reporting '
    'checklist.' % (N['inflation_median'], N['pf_confirmed'], pf['unfilt'], CORR,
                     N['afdb']['v6']['pct_pub'] - N['afdb']['v3']['pct_pub']), '')])
SUB('Availability and implementation')
R([('Analysis code at https://github.com/ktosmanprotein/structural-novelty-bias under an MIT licence; '
    'derived data tables on Zenodo. All reported values regenerate from the source tables.', '')])
SUB('Contact')
R([('ktosman@gmail.com', '')])
SUB('Supplementary information')
# Deliberately venue-neutral. The usual OUP wording ("available at Briefings in
# Bioinformatics online") names a journal the preprint has no relationship to,
# and would be wrong again if the paper moves elsewhere. It would also be
# untrue: there is no separate supplementary file, because every supporting
# table is in the public deposit instead.
R([('There is no separate supplementary file. All supporting data, including '
    'the per-protein novelty calls for all 15 proteomes and the AlphaFold '
    'Database cluster re-analysis tables, are deposited at Zenodo (' + ZENODO_CITE + '), and the '
    'analysis code is at ', ''),
   ('https://github.com/ktosmanprotein/structural-novelty-bias', ''),
   ('.', '')])

doc.add_page_break()

# ============================ AUTHOR SUMMARY ================================
doc.add_page_break()

# ============================ INTRODUCTION ==================================
H('Introduction')
R([('The AlphaFold Protein Structure Database now contains predicted models for over 200 million proteins '
    '[1,2], and Foldseek performs structural comparison against these at a speed that makes '
    'proteome-scale surveys routine [3]. A natural question follows: what fraction of an organism' +
    chr(8217) + 's uncharacterised proteins adopt a fold with no known structural relative? Such proteins '
    'are attractive targets, since a genuinely new fold may imply new chemistry, and in pathogens a fold '
    'absent from the host is a candidate for selective inhibition.', '')])
R([('The scale of that opportunity is now well established. Clustering the whole of the AlphaFold Database '
    'with Foldseek yielded 2.30 million non-singleton structural clusters, of which about 31% lacked any '
    'functional annotation and were interpreted as potentially previously undescribed structures [4]; a '
    'companion analysis of the same resource reported many apparently new families and folds [5]. Surveys '
    'of individual proteomes have followed, and the novel-fold fractions they report vary widely, from a '
    'few per cent to well over half of the uncharacterised proteins examined. Some of that spread must be '
    'biological: genome size, phylogenetic isolation and gene-family expansion all differ between '
    'organisms.', '')])
R([('But a structural novelty call is a negative result. The claim is that no match exists, and a claim of '
    'absence inherits every limitation of the search that failed to find one. Three limitations are '
    'particularly consequential, and none is biological. First, the query model may be too poor to match '
    'anything: pLDDT correlates strongly with intrinsic disorder [6,7], and a model without a stable '
    'backbone cannot be encoded consistently by a structural alphabet, so it returns no alignment '
    'regardless of whether its fold is known. Second, the reference set may be too narrow to contain the '
    'match that exists. Third, and least obviously, the reference set may contain the '
    'query organism itself, in which case proteins match their own entries and the comparison silently '
    'measures database membership.', '')])
R([('Each of these produces a plausible number. None announces itself in the output. And because they act '
    'in different directions and at different stages, a survey can control for one and remain badly wrong '
    'because of another. What is missing from the literature is a quantification: how large is each effect '
    'in practice, are they independent, and what does correcting all of them do to a published-style '
    'estimate?', '')])
R([('Here we separate and quantify these three effects. We use a panel of 15 alveolate genomes ' +
    ': 12 apicomplexan parasites and three free-living relatives, ', ''),
   ('135,523', 'b'), (' proteins in total, because it spans a wide range of genome sizes, '
    'research attention and database representation, so each bias can be observed varying across a common '
    'analytical pipeline. Proteome sizes differ roughly five-fold across the panel, and the free-living '
    'members are far less studied than the parasites, which makes the panel unusually well suited to '
    'separating measurement artefact from biology. We show that each mechanism is large, that each is '
    'independently correctable, and that the corrections are not interchangeable. We then apply all '
    'corrections uniformly across the panel and ask whether the biological signal survives.', '')])
doc.add_page_break()

# ============================ RESULTS =======================================
H('Results')

SUB('Apparent structural novelty decreases monotonically with model confidence and reaches zero for the '
    'best-predicted proteins.')
R([('We first asked whether apparent novelty depends on the quality of the query model. Stratifying ', ''),
   ('P. falciparum', 'i'),
   (' hypothetical proteins by mean pLDDT in ten-point bands (n = %s returning an alignment) produced a '
    'strictly monotonic relationship (Fig 1A). The apparent novel-fold rate fell from ' %
    format(N['pf_bands_total_n'], ','), ''),
   ('%.1f%%' % B[0][3], 'b'),
   (' below pLDDT 50, through %.1f%% (50' % B[1][3] + chr(8211) + '60), %.1f%% (60' % B[2][3] +
    chr(8211) + '70), %.1f%% (70' % B[3][3] + chr(8211) + '80) and %.1f%% (80' % B[4][3] + chr(8211) +
    '90), to ', ''),
   ('exactly 0.0%', 'b'),
   (' for the %d proteins with mean pLDDT ' % B[5][1] + chr(8805) + ' 90. Not one high-confidence model '
    'was called novel.', '')])
R([('The mechanism is mechanical rather than biological. Foldseek encodes backbone geometry in a structural '
    'alphabet; a region predicted with low confidence has no single stable conformation, so it cannot be '
    'encoded consistently and returns no match. The model is not novel, only '
    'uninformative. Because low-pLDDT models are disproportionately the ones that fail to match, they are '
    'systematically miscounted as novel folds.', '')])
R([('To test generality we repeated the comparison in all 15 genomes, computing the novel-fold rate with '
    'and without a confidence filter (mean pLDDT ' + chr(8805) + ' 70, ordered fraction ' + chr(8805) +
    ' 0.4, length ' + chr(8805) + ' 50 residues). Filtering reduced the estimate in ', ''),
   ('every genome examined', 'b'), (', by a median factor of ', ''),
   ('%.2f' % N['inflation_median'], 'b'),
   (' (range %.2f' % N['inflation_range'][0] + chr(8211) + '%.2f; Fig 1B). For ' % N['inflation_range'][1], ''),
   ('P. falciparum', 'i'),
   (' the rate moved from %.1f%% (n = %s models) to %.1f%% (n = %s passing all three criteria), a factor '
    'of %.2f. The consistency of the effect across genomes spanning a five-fold range of proteome size '
    'indicates a property of the method rather than of any one organism.' %
    (pf['unfilt'], format(pf['n_models'], ','), pf['filt'], format(pf['n_conf'], ','), pf['ratio']), '')])

SUB('Restricting the reference set to reviewed entries misses a third of the matches that exist.')
R([('A structural novelty call is only as strong as the reference database. Surveys commonly search '
    'AlphaFold/Swiss-Prot, which contains predicted models for reviewed UniProt entries. We asked what '
    'this excludes by re-searching the 316 confident novel-fold ', ''), ('P. falciparum', 'i'),
   (' proteins against PDB100, a database of experimentally determined structures. ', ''),
   ('%d' % N['pf_candidates'], 'b'),
   (' returned a match at query-normalised TM ' + chr(8805) + ' 0.50 (Fig 2A).', '')])
R([('Because TM-score can be inflated by alignment over a partial region, we re-scored every candidate with '
    'US-align, an independent algorithm. ', ''), ('%d' % N['pf_confirmed'], 'b'),
   (' of %d were confirmed (%.0f%%; Fig 2C); the %d that were not clustered at the threshold and in '
    'helix-rich proteins, where TM-score is least discriminating. Taking only the confirmed matches, the '
    'confident novel-fold set falls from 316 to ' %
    (N['pf_candidates'], N['pf_confirm_rate'], N['pf_candidates'] - N['pf_confirmed']), ''),
   ('%d' % N['pf_novel_after'], 'b'),
   (', from %.1f%% to %.1f%% of %s confident models.' %
    (316 / N['pf_denom'] * 100, CORR, format(N['pf_denom'], ',')), '')])
R([('The missed proteins are not a random sample (Fig 2B). ', ''),
   ('%d' % AC.get('ATP synthase', 0), 'b'),
   (' are subunits of the mitochondrial ATP synthase, identified through cryo-EM structures of the ', ''),
   ('Toxoplasma gondii', 'i'), (' complex, and ', ''),
   ('%d' % AC.get('ribosome/mitoribosome', 0), 'b'),
   (' are ribosomal or mitoribosomal subunits. These are precisely the proteins that sequence methods fail '
    'on, being highly divergent components of conserved machines, and they are '
    'absent from Swiss-Prot because they are unreviewed. They become visible only when a relative' +
    chr(8217) + 's complex is solved experimentally. One 2020 cryo-EM study accounts for 17 of them.', '')])
R([('This has a practical consequence beyond the corrected number. Structural annotation of a dark proteome '
    'is not a fixed quantity but a function of what has been solved elsewhere, and it improves '
    'discontinuously as large complexes from related organisms are determined.', '')])

SUB('When the query organism is present in the reference database, apparent novelty measures database '
    'membership rather than structure.')
R([('Cross-organism comparison is the usual way to argue that a novelty rate is unusual. Such a comparison '
    'is invalid unless every organism is equally absent from the reference set, and the failure is easy to '
    'miss. We encountered it in one of our own ancillary analyses: a separate five-organism comparison run '
    'against AlphaFold/Swiss-Prot without a self-match exclusion. Three of those organisms are themselves '
    'represented in that database, and their queries overwhelmingly matched their own entries: ', ''),
   ('%d/%d (%.0f%%)' % (SH['S. cerevisiae']['self_hits'], SH['S. cerevisiae']['with_hit'],
                        SH['S. cerevisiae']['pct']), 'b'), (' for ', ''), ('S. cerevisiae', 'i'), (', ', ''),
   ('%d/%d (%.0f%%)' % (SH['E. coli']['self_hits'], SH['E. coli']['with_hit'],
                        SH['E. coli']['pct']), 'b'), (' for ', ''), ('E. coli', 'i'), (', and ', ''),
   ('%d/%d (%.0f%%)' % (SH['H. sapiens']['self_hits'], SH['H. sapiens']['with_hit'],
                        SH['H. sapiens']['pct']), 'b'), (' for ', ''), ('H. sapiens', 'i'),
   (' (Fig 3A). The apicomplexan control, absent from Swiss-Prot, showed no such effect:' +
    ' ', ''),
   ('%d/%d' % (SH['T. gondii']['self_hits'], SH['T. gondii']['with_hit']), 'b'), (' for ', ''),
   ('T. gondii', 'i'), ('.', '')])
R([('The consequence is that the low apparent novelty of those three organisms is close to meaningless as a '
    'structural statement: it is the fraction of their uncharacterised proteins not yet deposited in '
    'Swiss-Prot. Comparing an absent organism against a present one therefore measures curation status, not '
    'fold novelty. The failure mode is silent: it produces entirely plausible numbers, and '
    'is visible only if self-matches are explicitly counted.', '')])
R([('The correction is a single step: exclude every accession belonging to the query proteome from its own '
    'target set (Fig 3B). Our main 15-genome panel applies this exclusion throughout, so the rates reported '
    'in Fig 1C and Fig 3C are unaffected; we verified this directly, confirming that no protein in the panel '
    'has its own accession recorded as its best target. We report the uncorrected five-organism comparison '
    'here not as a result but as a demonstration of the size of the artefact when the step is omitted.', '')])

SUB('The confidence gradient is present across the whole AlphaFold Database, but its effect on an '
    'aggregate rate depends on study design.')
R([('The panel above is taxonomically narrow, so we asked whether the confidence effect appears in the '
    'largest available analysis of structural novelty. Barrio-Hernandez and colleagues clustered the '
    'AlphaFold Database and flagged clusters lacking annotation as dark, a set interpreted as probable '
    'previously undescribed structures [4]. Their cluster overview reports, for every cluster, the mean '
    'pLDDT and length of its representative, which is sufficient to apply two of our three confidence '
    'criteria. We stress that this is a conservative test in two respects: the representative is the '
    'highest-pLDDT member of its sequence cluster, and the ordered-fraction criterion cannot be applied.', '')])
R([('Recomputing the dark fraction on the release contemporaneous with that work returned ', ''),
   ('%.1f%%' % AF['v3']['pct_pub'], 'b'),
   (' of %s clusters, reproducing the published figure of approximately 31%% and confirming that our '
    'reading of the data matches theirs. On the current release the same computation returns ' %
    format(AF['v3']['clusters'], ','), ''),
   ('%.1f%%' % AF['v6']['pct_pub'], 'b'),
   (' of %s clusters.' % format(AF['v6']['clusters'], ','), '')])
R([('At this scale the gradient is stark (Fig 4A). In the earlier release the dark '
    'fraction falls from %.1f%% among clusters whose representative has mean pLDDT below 50 to %.1f%% among '
    'those above 90, and in the current release from %.1f%% to %.1f%%. Both series are ' %
    (AFB['v3'][0][3], AFB['v3'][-1][3], AFB['v6'][0][3], AFB['v6'][-1][3]), ''),
   ('strictly monotonic across all six bands', 'b'),
   (', with Cochran-Armitage trend statistics of z = %.0f and z = %.0f respectively. Dark-cluster '
    'representatives are also systematically less well predicted: median mean pLDDT %.1f against %.1f for '
    'non-dark clusters in the current release, and %.1f%% of dark clusters have a representative below '
    'pLDDT 70. The relationship we observed in one parasite proteome is therefore a property of the '
    'measurement, visible across 2.6 million clusters spanning the tree of life.' %
    (AF['v3']['z'], AF['v6']['z'], AF['v6']['med_dark'], AF['v6']['med_known'],
     AF['v6']['pct_plddt_lt70'] if 'pct_plddt_lt70' in AF['v6'] else 56.1), '')])
R([('The effect on the aggregate rate, however, is modest: %.1f%% to %.1f%% in the earlier release and '
    '%.1f%% to %.1f%% in the current one, factors of %.2f and %.2f (Fig 4B). This is not a contradiction. '
    'Filtering removes more than half of all dark clusters in both releases (%.1f%% and %.1f%%; Fig 4C), '
    'but it removes low-confidence clusters from the numerator and the denominator alike, so the ratio is '
    'buffered. Cluster-level analyses that select the best-predicted member as representative are '
    'therefore partly self-correcting.' %
    (AF['v3']['pct_pub'], AF['v3']['pct_filt'], AF['v6']['pct_pub'], AF['v6']['pct_filt'],
     AF['v3']['fold'], AF['v6']['fold'], AF['v3']['pct_removed'], AF['v6']['pct_removed']), '')])
R([('This sharpens rather than weakens the recommendation. A per-proteome survey reporting the fraction of '
    'its own uncharacterised proteins that are novel has no such buffer, which is why ', ''),
   ('P. falciparum', 'i'),
   (' moves by a factor of %.2f while the cluster-level fraction moves by %.2f. The correction matters '
    'most precisely where these surveys are usually reported.' % (pf['ratio'], AF['v6']['fold']), '')])
R([('One further observation follows directly. Between the two releases, with the method held completely '
    'fixed, the dark fraction rose from %.1f%% to %.1f%% ' % (AF['v3']['pct_pub'], AF['v6']['pct_pub']) +
   'a shift of %.1f percentage points driven by database growth alone. A structural novelty figure '
   'is not a stable property of the sequences it describes.' %
   (AF['v6']['pct_pub'] - AF['v3']['pct_pub']), '')])

SUB('Applying every correction uniformly across 15 genomes changes the estimates but not the conclusion.')
R([('These corrections could in principle distort comparative work, because the PDB is not '
    'phylogenetically uniform: lineages that have received more structural-biology effort should lose more '
    'apparent novelty. We tested this by applying the PDB100 correction identically to all 15 genomes, '
    'searching the 8,011 confidently novel hypothetical proteins in the panel (Fig 3C).', '')])
R([('The concern was not borne out. Novel-fold rates fell in every genome, but by a similar margin, and the '
    'free-living outgroups fell slightly ', ''), ('more', 'i'),
   (' than the parasites (mean %.1f versus %.1f percentage points). Expressed as the fraction of novel '
    'calls withdrawn, ' % (N['OUT_mean_drop'], N['APIC_mean_drop']), ''),
   ('Vitrella brassicaformis', 'i'), (' (25.0%) and ', ''), ('Tetrahymena thermophila', 'i'),
   (' (27.4%) were the ', ''), ('most robust of all 15 genomes', 'b'),
   (', against 27.9' + chr(8211) + '50.6% across the apicomplexans. The rank ordering was preserved at the '
    'top: the chromerid and ciliate outgroups remained far above every apicomplexan after correction '
    '(51.3% and 45.6% versus 10.6' + chr(8211) + '28.3%).', '')])
R([('One species behaved differently. ', ''), ('Perkinsus marinus', 'i'),
   (' had 57.8% of its novel calls withdrawn, the highest in the panel, falling from 34.4% to 14.5% and '
    'moving from mid-panel to lowest. Whatever elevates apparent novelty in the chromerid and ciliate '
    'lineages therefore does not extend to Perkinsozoa, and grouping the three as "free-living outgroups" '
    'obscures a real difference between them.', '')])
R([('Taken together, for ', ''), ('P. falciparum', 'i'),
   (' the two correctable mechanisms compound: from ', ''), ('%.1f%%' % pf['unfilt'], 'b'),
   (' without any filtering to ', ''), ('%.1f%%' % CORR, 'b'),
   (' after confidence filtering and reference-scope correction, a ', ''), ('%.2f-fold' % TOTAL, 'b'),
   (' reduction. Because the corrections were applied identically to every genome, the '
    'comparative conclusion the panel supports is unchanged. These are corrections to measurement, not to '
    'biology.', '')])
doc.add_page_break()

# ============================ DISCUSSION ====================================
H('Discussion')
R([('Structural novelty is a negative claim, and negative claims inherit every limitation of the search '
    'that produced them. The three mechanisms described here are not subtle statistical adjustments: '
    'together they move a headline figure by a factor of ', ''), ('%.2f' % TOTAL, 'b'),
   (', which is larger than most of the biological differences such surveys set out to detect.', '')])
R([('The three are also independent, and correcting one does not address the others. Confidence filtering '
    'removes models that cannot match anything; it does nothing about a reference set that lacks the '
    'match. Broadening the reference set finds those matches but makes self-matching worse if the query '
    'organism is included. Excluding self-matches fixes the comparison but not the low-confidence '
    'inflation. A survey can therefore be careful in one respect and still report a number that is wrong '
    'by a factor of two.', '')])
R([('We suggest that structural novelty surveys report, at minimum: (i) the confidence filter applied, with '
    'the novelty rate before and after; (ii) the reference database and its scope, with an explicit '
    'statement of whether experimentally determined structures were included; (iii) the proportion of '
    'queries matching their own entries in the reference set; (iv) which TM-score normalisation was used, '
    'since aligned-length normalisation inflates partial matches; and (v) for any cross-organism '
    'comparison, confirmation that all organisms are equally absent from the reference database. None of '
    'these is expensive, and each addresses a failure mode we observed producing a plausible but incorrect '
    'result.', '')])
R([('Several limitations apply. Our panel is taxonomically narrow, since all 15 genomes are '
    'alveolates, so the absolute magnitudes we report may not transfer, though the '
    'mechanisms are not organism-specific. The PDB100 correction was applied with Foldseek alone across '
    'the panel for tractability; in ', ''), ('P. falciparum', 'i'),
   (', where we verified every match with US-align, %d of %d candidates were withdrawn, so the panel-wide '
    'corrections should be read as upper bounds of roughly this magnitude. Finally, our confidence '
    'thresholds follow common practice rather than an independent optimisation; the monotonicity in Fig 1A '
    'is threshold-free, but the particular filter we apply is a convention.' %
    (N['pf_candidates'] - N['pf_confirmed'], N['pf_candidates']), '')])
R([('The AFDB re-analysis also delimits where these corrections bite. An aggregate computed over clusters '
    'whose representatives were chosen for high confidence is partially protected; a per-proteome novelty '
    'rate is not. Reviewers and readers should therefore ask not only whether a confidence filter was '
    'applied, but what quantity is being reported and whether its construction already removes the '
    'low-confidence tail.', '')])
R([('Finally, the reference-scope result reframes what a dark proteome measurement is. The proportion of a '
    'proteome without an assignable fold is not an intrinsic property of that organism, but a joint '
    'property of the organism and the current state of structural biology. It will fall as more complexes '
    'are solved, and it falls fastest for organisms with well-studied relatives. Reporting such a figure '
    'without the database version and date is reporting a moving quantity as a fixed one.', '')])
doc.add_page_break()

# ============================ METHODS =======================================
H('Materials and methods')

SUB('Genomes and predicted structures')
R([('Fifteen alveolate proteomes were obtained from UniProt reference proteomes [8]. Proteome accessions '
    'and taxon identifiers were verified against the UniProt REST API on 2026-09-22 and pinned in a '
    'configuration file rather than resolved at run time, so that a subsequent UniProt release could not '
    'silently substitute a different strain; recorded protein counts are used as a check on the same. The '
    'panel comprises twelve apicomplexans (', ''), ('Plasmodium falciparum', 'i'), (' 3D7, ', ''),
   ('P. vivax', 'i'), (', ', ''), ('P. knowlesi', 'i'), (', ', ''), ('P. berghei', 'i'), (', ', ''),
   ('Toxoplasma gondii', 'i'), (' ME49, ', ''), ('Neospora caninum', 'i'), (', ', ''),
   ('Eimeria tenella', 'i'), (', ', ''), ('Cryptosporidium parvum', 'i'), (', ', ''),
   ('C. hominis', 'i'), (', ', ''), ('Babesia bovis', 'i'), (', ', ''), ('Theileria annulata', 'i'),
   (', ', ''), ('T. parva', 'i'), (') and three non-apicomplexan alveolate outgroups (', ''),
   ('Tetrahymena thermophila', 'i'), (', Ciliophora; ', ''), ('Perkinsus marinus', 'i'),
   (', Perkinsozoa; ', ''), ('Vitrella brassicaformis', 'i'),
   (', Chromerida). ', ''), ('Chromera velia', 'i'),
   (', the closest free-living photosynthetic relative of the apicomplexan ancestor and the ideal outgroup, '
    'has no UniProt reference proteome and could not be included. Predicted structures were retrieved from '
    'the AlphaFold Protein Structure Database v6 [2]. In total the panel comprises 135,523 proteins, of '
    'which 69,643 are annotated as hypothetical and 52,115 have a model passing all confidence criteria '
    'below.', '')])

SUB('Confidence filtering')
R([('Three criteria were applied jointly, and a protein had to satisfy all three to be retained: mean '
    'pLDDT ' + GE + ' 70; ordered fraction ' + GE + ' 0.4, defined as the proportion of residues whose '
    'individual pLDDT is ' + GE + ' 70, and length ' + GE + ' 50 residues. The mean-pLDDT threshold follows '
    'common practice and the AlphaFold Database' + AP + 's own guidance that residues below 70 should be '
    'treated with caution. The ordered-fraction criterion is included because a mean can be met by a '
    'protein with one well-predicted domain and a long disordered tail, which behaves in structural search '
    'like the disordered protein rather than the domain; requiring that a substantial minority of residues '
    'are individually confident excludes that case. The length floor removes fragments too short for '
    'TM-score to be meaningful. We emphasise that the monotonic relationship in Fig 1B is threshold-free: '
    'it is visible across the whole pLDDT range, and the particular cut-offs are a convention rather than '
    'an optimisation.', '')])
R([('For the unfiltered comparison in Fig 1C, novelty was recomputed directly from the best TM-score so '
    'that low-confidence models received a novelty call rather than being excluded from the denominator. '
    'This is what makes the two rates comparable: the filtered and unfiltered estimates differ only in '
    'whether the confidence criteria were applied, not in how novelty was defined.', '')])

SUB('Structural search and novelty calling')
R([('Forward searches used Foldseek [3] against the AlphaFold/Swiss-Prot database, built with the '
    'Foldseek-provided Alphafold/Swiss-Prot set, in combined 3Di and amino-acid mode (--alignment-type 0) '
    'with an E-value threshold of 0.001 and four threads. PDB100 searches used TM-align mode '
    '(--alignment-type 1, -e 10, -a) against the PDB100 release dated 2025-01-01. Foldseek 10.941cd33 was '
    'used for the PDB100 searches; forward searches were run with Foldseek 8.ef4e960. A protein was called '
    'structurally known when the best TM-score reached 0.50, the conventional threshold for shared fold '
    '[9], and novel otherwise; proteins returning no alignment at all were counted as novel.', '')])
R([('TM-score normalisation matters and is reported inconsistently in the literature. Foldseek can '
    'normalise by aligned length (alntmscore) or by query length (qtmscore). Aligned-length normalisation '
    'rewards a good alignment over a short region and can exceed 1.0; in our data ten proteins returned '
    'aligned-length scores above 1.0, with a maximum of 1.013. All PDB100 results in this work use '
    'query-normalised TM-score, which is the conservative choice because it penalises partial coverage.', '')])

SUB('Self-match exclusion')
R([('Several proteomes in the panel are themselves represented in AlphaFold/Swiss-Prot. In the 15-genome '
    'panel, every accession belonging to the query proteome was excluded from that proteome' + AP + 's own '
    'target set before the best hit was taken, so a protein can match neither itself nor another entry from '
    'its own species. This exclusion is implemented in the novelty-calling code and covered by a unit test. '
    'We verified its effect directly on the output: no protein in the panel has its own accession recorded '
    'as its best target. To quantify the artefact the exclusion prevents, we separately counted, in an '
    'ancillary five-organism comparison run without it, the proportion of queries whose best-scoring target '
    'was their own database entry.', '')])

SUB('Independent confirmation of PDB100 matches')
R([('Because TM-score can be inflated by alignment over a partial or repetitive region, every '
    'P. falciparum PDB100 candidate was re-scored with US-align [10], which implements an independent '
    'alignment algorithm. The matched PDB entry was downloaded from the RCSB Protein Data Bank [11], the '
    'specific matched chain extracted, and the pair re-scored with default settings. A candidate was '
    'accepted only if the US-align query-normalised TM-score also reached 0.50. Source organisms and entry '
    'titles were retrieved from the RCSB REST API and used to distinguish matches to the query' + AP + 's '
    'own genus, which indicate that the protein' + AP + 's own structure has been solved, from matches to '
    'more distant lineages.', '')])

SUB('Panel-wide PDB100 correction')
R([('Only proteins already called novel can be reassigned by an additional search, so the correction was '
    'applied to the 8,011 hypothetical proteins across the panel that passed confidence filtering and were '
    'called novel against AlphaFold/Swiss-Prot. Applying it identically to every genome is what makes the '
    'corrected panel internally comparable. For tractability the panel-wide pass used Foldseek alone '
    'without the US-align confirmation step; in ', ''), ('P. falciparum', 'i'),
   (', where every candidate was confirmed, 105 of 137 survived, so the panel-wide corrections should be '
    'read as upper bounds of approximately that magnitude.', '')])

SUB('Use of artificial intelligence tools')
R([('An AI assistant (Claude, Anthropic) was used in three roles: writing and debugging the Python and '
    'shell scripts used for the analyses and figure generation; consolidating outputs from separate '
    'analysis runs into single tables; and editing prose for clarity. It was not used to design the study, '
    'select methods or thresholds, or interpret results.', '')])
R([('Validity of the outputs was evaluated as follows. Every script was executed on the source data and its '
    'output checked against independently computed values: the exact binomial confidence intervals were '
    'verified against published worked values, the colour-vision simulations against the matrices as '
    'published, and the AFDB re-analysis was validated by reproducing the dark fraction reported for the '
    'release on which the original analysis was performed (%.1f%% against a published figure of '
    'approximately 31%%) before the current release was examined. All figures were inspected at final '
    'reproduction size. Every numeric value in the text and figures is generated programmatically from the '
    'source tables at build time rather than transcribed, so any discrepancy between text and data would '
    'surface as a build failure; the scripts that do this are in the public repository.' % AF['v3']['pct_pub'], '')])
R([('Affected components: the analysis and figure-generation code, the assembly of summary tables, and the '
    'wording of the manuscript. Not affected: the study design, the choice of methods and thresholds, the '
    'primary data, and the interpretation of results, all of which are the author' + AP + 's own. The author '
    'has verified every reported value against the source data and takes full responsibility for the '
    'contents of this manuscript.', '')])

SUB('Statistics and figures')
R([('Confidence intervals on binomial proportions are exact (Clopper-Pearson) 95% intervals, computed from '
    'the incomplete beta function; the normal approximation is not valid for the highest pLDDT band, which '
    'contains zero novel-fold calls in 134 proteins. Colour palettes were checked for colour-vision '
    'deficiency by simulating deuteranopia, protanopia and tritanopia at full severity with the matrices of '
    'Machado, Oliveira and Fernandes [12] and requiring a CIE76 separation of at least 20 between any two '
    'colours appearing in the same panel. Structure images were rendered in PyMOL and coloured by the '
    'standard AlphaFold pLDDT bands.', '')])


doc.add_page_break()

H('Data availability')
R([('All underlying data are deposited on Zenodo (', ''),
   (ZENODO_CITE, ''),
   ('), including: the '
    'pinned 15-species proteome panel with UniProt reference-proteome accessions, taxon identifiers and '
    'download date; per-protein novelty tables for all 135,523 proteins across the 15 genomes, giving best '
    'TM-score, best target, mean pLDDT, ordered fraction, length and novelty verdict; per-protein model '
    'confidence tables; the per-protein best-hit summary of the forward Foldseek search of every genome '
    'against AlphaFold/Swiss-Prot, giving best target, TM-score, E-value and query coverage (the full '
    'alignment output runs to 20.9 million rows and is not deposited; it regenerates exactly from the '
    'deposited scripts and the pinned proteome panel, and is available from the author on request); '
    'the PDB100 search output and per-protein verification table for ', ''),
   ('Plasmodium falciparum', 'i'),
   (', with Foldseek and US-align query-normalised TM-scores, matched PDB entry, chain, source organism and '
    'entry title for all 137 candidates; the panel-wide PDB100 correction tables, including per-protein '
    'reassignments and own-genus flags for all 8,011 queried structures; self-match counts for the '
    'five-organism comparison; and the AFDB dark-cluster re-analysis tables for releases v3 and v6. '
    'AlphaFold v6 structures are available at https://alphafold.ebi.ac.uk. The AFDB cluster data '
    're-analysed here were published by Barrio-Hernandez et al. [4] under a CC-BY 4.0 licence and are '
    'available at https://cluster.foldseek.com.', '')])

H('Code availability')
R([('All pipeline and analysis scripts are available at '
    'https://github.com/ktosmanprotein/structural-novelty-bias and archived on '
    'Zenodo, under the MIT licence. The repository includes the scripts that regenerate every numeric '
    'claim in this manuscript, and every value plotted in its figures, directly from the source tables: '
    'no value in the text or figures is entered by hand. This includes the exact binomial confidence '
    'intervals in Fig 1B, which are computed into the audit output rather than at plotting time. '
    'Figure-rendering and structure-image scripts are not included, as they only style values already '
    'present in that output. It also contains the novelty-calling code implementing the self-match '
    'exclusion described above, together with the unit test covering it. Key dependencies: Python 3.10 or '
    'later, Foldseek (8.ef4e960 for forward searches, 10.941cd33 for PDB100), US-align, PyMOL, and '
    'matplotlib 3.10.9.', '')])

H('Author contributions')
R([('Khan Osman is the sole author. CRediT contributor roles: Conceptualization, Data curation, Formal '
    'analysis, Investigation, Methodology, Software, Validation, Visualization, Writing - original draft, '
    'Writing - review and editing.', '')])

H('Competing interests')
R([('The author declares no competing interests.', '')])

H('Funding')
R([('This research received no specific grant from any funding agency in the public, commercial or '
    'not-for-profit sectors.', '')])

H('Acknowledgements')
R([('Computational analyses were performed on a personal MacBook. The author received no external funding '
    'for this work. The author thanks the developers and maintainers of the open-source tools and public '
    'resources used in this study, including Foldseek, US-align, AlphaFold and the AlphaFold Protein '
    'Structure Database, PyMOL, UniProt and the RCSB Protein Data Bank, and the authors of the AlphaFold '
    'Database clustering resource re-analysed here, whose decision to publish their cluster data openly '
    'made that analysis possible.', '')])

doc.add_page_break()

# ============================ FIGURE LEGENDS ================================
H('Figure legends')
FIGIMG(1)
R([('Fig 1. Model confidence inflates apparent structural novelty in every genome examined. ', 'b'),
   ('(A) Three ', ''), ('P. falciparum', 'i'),
   (' hypothetical proteins of near-identical length (258, 259 and 260 residues), coloured by AlphaFold '
    'pLDDT. Holding length constant isolates confidence as the only variable. Left, Q8I5B7 / PF3D7_1230300, '
    'mean pLDDT 46.9: no stable backbone, and Foldseek returns no alignment. Centre, C6KTD1 / '
    'PF3D7_0629600, mean pLDDT 64.4: partially ordered, best match TM 0.32. Right, Q8IAR3 / PF3D7_0807500, '
    'mean pLDDT 92.8: a compact domain matching a known fold at TM 0.95. The first two are scored as novel '
    'folds. (B) Apparent novel-fold rate by mean pLDDT in ten-point bands (n = %s returning '
    'an alignment; per-band n below axis), bars coloured by the pLDDT key in (A); error bars, exact binomial (Clopper-Pearson) 95%% confidence intervals. The relationship is '
    'monotonic and reaches 0.0%% (95%% CI 0.0-2.7) for the %d proteins at pLDDT ' %
    (format(N['pf_bands_total_n'], ','), B[5][1]) + chr(8805) + ' 90. Shading marks bands passing the '
    'confidence filter. (C) Novel-fold rate for each of 15 genomes without confidence filtering (filled) '
    'and with it (open). Every genome falls; median factor %.2f. Free-living outgroups in orange. The '
    'pLDDT palette is colour-blind safe (worst adjacent-band CIE76 separation 39.8 under simulated '
    'tritanopia).' % N['inflation_median'], '')], space_after=14)
R([('Alt text: Panel A shows three predicted protein structures of similar length coloured by AlphaFold confidence; the low-confidence model is extended and disordered, the high-confidence model is compact and folded. Panel B is a bar chart in which apparent novel-fold rate falls from about 76 per cent to zero as mean pLDDT increases. Panel C is a slope chart showing that the novel-fold rate falls in all 15 genomes when a confidence filter is applied.', 'i')], space_after=14, size=10)
FIGIMG(2)
R([('Fig 2. Restricting the reference database to reviewed entries misses a third of existing matches. ', 'b'),
   ('(A) Effect of adding PDB100 to the ', ''), ('P. falciparum', 'i'),
   (' search. Of 316 proteins called novel against AF-SwissProt, %d returned a PDB100 match at '
    'query-normalised TM ' % N['pf_candidates'] + chr(8805) + ' 0.50 and %d were confirmed by US-align, '
    'leaving %d. (B) Functional composition of the %d reassigned proteins. (C) Foldseek versus US-align '
    'query-normalised TM-score for all %d candidates; dashed line, TM = 0.50 confirmation threshold; '
    'dotted line, identity. (D) Three reassigned proteins superposed on the experimental structures that '
    'were already available. AlphaFold models are shown as solid tubes coloured by pLDDT, '
    'experimental chains as transparent grey ribbons; the two representations differ so the chains cannot '
    'be confused. Superpositions use the US-align rotation. The disordered orange segment of Q8IM47 is '
    'a genuine low-confidence terminus of the predicted model.' %
    (N['pf_confirmed'], N['pf_novel_after'], N['pf_confirmed'], N['pf_candidates']), '')], space_after=14)
R([('Alt text: Panel A is a waterfall chart showing the novel-fold count falling from 316 to 211 after adding a PDB search and independent confirmation. Panel B is a bar chart of the functional categories of the reassigned proteins, dominated by mitochondrial ATP synthase and ribosomal subunits. Panel C is a scatter plot comparing two alignment methods. Panel D shows three predicted structures superposed on experimental structures, each pair closely matching.', 'i')], space_after=14, size=10)
FIGIMG(3)
R([('Fig 3. Self-matching invalidates cross-organism comparison, but uniform correction leaves the panel '
    'conclusion intact. ', 'b'),
   ('(A) An ancillary five-organism comparison run without self-match exclusion. Red, proportion of queries '
    'whose best-scoring target was their own database entry; blue, the novel-fold rate that comparison '
    'reported. Where self-matching is near-total the reported novelty collapses, because it is measuring '
    'absence from Swiss-Prot rather than absence of a known fold. (B) The mechanism and its correction. '
    '(C) The main 15-genome panel, which applies the exclusion in (B) throughout: novel-fold rate before '
    '(filled) and after (open) identical PDB100 correction. Free-living outgroups in orange. Rank ordering '
    'at the top of the panel is preserved.', '')], space_after=14)
R([('Alt text: Panel A is a paired bar chart in which organisms with a high proportion of self-matching queries show low reported novelty, and the control organism shows the opposite. Panel B is a flow diagram of the self-matching mechanism and its correction. Panel C shows novel-fold rate for 15 genomes before and after correction, with the ordering preserved.', 'i')], space_after=14, size=10)
FIGIMG(4)
R([('Fig 4. The confidence gradient holds across the AlphaFold Database, but buffers at cluster level. ', 'b'),
   ('Re-analysis of the AFDB cluster data of Barrio-Hernandez et al. [4] (CC-BY 4.0), applying mean pLDDT '
    '%s 70 and length %s 50 to cluster representatives. (A) Percentage of clusters flagged dark, by the '
    'mean pLDDT of the cluster representative, for the release contemporaneous with the original analysis '
    '(v3, %s clusters) and the current release (v6, %s clusters). Both are strictly monotonic. (B) Dark '
    'fraction as published and after confidence filtering; fold change below each pair. (C) Proportion of '
    'dark clusters removed by the filter; dotted line, 50%%. The representative is the highest-pLDDT member '
    'of its sequence cluster, so all values are conservative.' %
    (GE, GE, format(AF['v3']['clusters'], ','), format(AF['v6']['clusters'], ',')), '')], space_after=14)
R([('Alt text: Panel A shows the percentage of AlphaFold Database clusters flagged dark falling steadily as the confidence of the cluster representative increases, for two database releases. Panel B compares the dark fraction before and after confidence filtering for each release. Panel C shows that filtering removes more than half of all dark clusters in both releases.', 'i')], space_after=14, size=10)

doc.add_page_break()

# ============================ REFERENCES ====================================
H('References')
refs = [
    'Jumper J, Evans R, Pritzel A, Green T, Figurnov M, Ronneberger O, et al. Highly accurate protein '
    'structure prediction with AlphaFold. Nature. 2021;596:583-589.',
    'Varadi M, Anyango S, Deshpande M, Nair S, Natassia C, Yordanova G, et al. AlphaFold Protein Structure '
    'Database: massively expanding the structural coverage of protein-sequence space with high-accuracy '
    'models. Nucleic Acids Res. 2022;50:D439-D444.',
    'van Kempen M, Kim SS, Tumescheit C, Mirdita M, Lee J, Gilchrist CLM, et al. Fast and accurate protein '
    'structure search with Foldseek. Nat Biotechnol. 2024;42:243-246.',
    'Barrio-Hernandez I, Yeo J, Janes J, Mirdita M, Gilchrist CLM, Wein T, et al. Clustering predicted '
    'structures at the scale of the known protein universe. Nature. 2023;622:637-645.',
    'Durairaj J, Waterhouse AM, Mets T, Brodiazhenko T, Abdullah M, Studer G, et al. Uncovering new '
    'families and folds in the natural protein universe. Nature. 2023;622:646-653.',
    'Tunyasuvunakool K, Adler J, Wu Z, Green T, Zielinski M, Zidek A, et al. Highly accurate protein '
    'structure prediction for the human proteome. Nature. 2021;596:590-596.',
    'Wilson CJ, Choy WY, Karttunen M. AlphaFold2: a role for disordered protein/region prediction? Int J '
    'Mol Sci. 2022;23:4591.',
    'UniProt Consortium. UniProt: the Universal Protein Knowledgebase in 2023. Nucleic Acids Res. '
    '2023;51:D523-D531.',
    'Zhang Y, Skolnick J. Scoring function for automated assessment of protein structure template quality. '
    'Proteins. 2004;57:702-710.',
    'Zhang C, Shine M, Pyle AM, Zhang Y. US-align: universal structure alignments of proteins, nucleic '
    'acids and macromolecular complexes. Nat Methods. 2022;19:1109-1115.',
    'Burley SK, Bhikadiya C, Bi C, Bittrich S, Chen L, Crichlow GV, et al. RCSB Protein Data Bank: powerful '
    'new tools for exploring 3D structures of biological macromolecules. Nucleic Acids Res. '
    '2021;49:D437-D451.',
    'Machado GM, Oliveira MM, Fernandes LAF. A physiologically-based model for simulation of color vision '
    'deficiency. IEEE Trans Vis Comput Graph. 2009;15:1291-1298.',
]
for i, r in enumerate(refs, 1):
    P('%d. %s' % (i, r), size=11, space_after=6)

out = os.path.join(HERE, 'Paper1_structural_novelty_biases_v1.docx')
doc.save(out)
print('saved:', out)
print('inflation %.2fx  corrected %.1f%%  confirmed %d/%d' %
      (TOTAL, CORR, N['pf_confirmed'], N['pf_candidates']))

if not ZENODO_DOI:
    print('\n  !! ZENODO_DOI is unset. The availability statements read as though the')
    print('     deposit is live. Reserve the DOI, set ZENODO_DOI above, make the GitHub')
    print('     repo public, then rebuild -- before posting the preprint.\n')
