# Validation

Simulations with a known ground truth, kept outside `lib/` so the pipeline
stays general. Two parts:

- **Preprocessing**: does the pipeline remove artifacts without damaging the
  EEG? Plan: `tests/EEG Preprocessing Validation Plan.md`.
- **Source reconstruction and higher-order interactions**: can O-information
  (static and rate) between brain regions be recovered from scalp EEG after
  preprocessing and source reconstruction? Plan:
  `tests/EEG Source Reconstruction Validation Plan.md`.

## Layout

```text
validation/
├── README.md              this file
├── preprocessing/         artifact simulation and pipeline validation
│   ├── run_validation.m   entry point; settings in sim_config.m
│   ├── report_figures.m   figures of the preprocessing report
│   └── sim_*.m            clean EEG, artifacts, injection, metrics
├── source/                source reconstruction and O-information
│   ├── run_src_validation.m   Stage 1: sources + sensor noise only
│   ├── run_src_stage2.m       Stage 2: + background EEG, artifacts, pipeline
│   ├── src_config.m           all parameters of both stages
│   ├── src_heads.m            New York Head (simulation), ICBM152 BEM (inverse)
│   ├── src_atlas.m            DKT 62 and coarse 20 parcellations
│   ├── src_triplets.m         target triplets and all parcel triplets
│   ├── src_patches.m          15 mm source patch per parcel
│   ├── src_sources.m          white sources, static ground truth
│   ├── src_sources_var.m      AR(2) oscillators with lagged coupling (rate ground truth)
│   ├── src_interp.m           template lead field at the 10-10 sites
│   ├── src_inverse.m          eLORETA and LCMV through FieldTrip
│   ├── src_pc1.m              parcel time series: first principal component
│   ├── src_oinfo3.m           static Gaussian O-information of triplets
│   ├── src_boot.m             moving block bootstrap
│   ├── src_oir3.m             O-information rate, VAR per triplet (OIR toolbox)
│   ├── src_oir_full.m         O-information rate, one VAR on all parcels (SIR toolbox)
│   ├── src_figure.m           Stage 1 summary figure
│   ├── src_figure_s2.m        Stage 2 summary figure
│   ├── src_brain_s2.m         brain maps: leakage and recovery per parcel
│   ├── src_oinfo_brain_s2.m   brain maps: true and estimated O per parcel
│   ├── src_parcels_figure.m   the parcellation and the target triplets
│   └── test_src_*.m           unit tests (runtests)
└── results/
    ├── preprocessing/     one folder per run, report_revision/ (report and figures)
    └── source/            one folder per run, report_source/, parcels_dkt62.png
```

Every run writes to `results/<part>/<yyyyMMdd_HHmmss>_<runName>/`.

## Requirements

All in `lib/toolboxes/` (not tracked by git):

| Toolbox | Used for |
|---|---|
| EEGLAB with the pipeline plugins | data handling, the pipeline |
| SEREEGA, HArtMuT (New York Head) | simulated EEG; the ICBM152 BEM ships with SEREEGA |
| FieldTrip 20251218 | eLORETA and LCMV (`src_inverse`) |
| OIR (github.com/danielemarinazzo/OIR, Faes et al. 2022) | O-information rate per triplet, lagged/instantaneous split |
| SIR_toolbox (github.com/LauraSparacino/SIR_toolbox) | spectral matrices, order selection, full-VAR OIR |

MATLAB R2025b on the UGent machine needs the UGent VPN for the licence.

## How to run

```matlab
addpath validation/preprocessing validation/source
R = run_validation();                         % preprocessing validation
R = run_src_validation();                     % source Stage 1 (static, ~1 h)
R = run_src_stage2();                         % source Stage 2 (static, 3 seeds x 300 s, ~2-3 h)

% quick Stage 2 (~6 min): 1 seed, 60 s, regional signals 10 dB above background
c = src_config(); c.s2.seeds = 1; c.s2.secs = 60; c.s2.parcelDb = 10;
R = run_src_stage2(struct('s2', c.s2, 'nBoot', 100));

% O-information rate: per triplet (DKT 62) or one full VAR (coarse 20)
c.s2.measure = 'OIR';
R = run_src_stage2(struct('s2', c.s2, 'nBoot', 50));
c.s2.oirFit = 'full'; c.s2.atlas = 'coarse20';
R = run_src_stage2(struct('s2', c.s2, 'nBoot', 50));

% figures from a run folder
src_figure_s2(outDir);                        % summary (also made by the run)
src_brain_s2(outDir, 'sparse', 'syn_near', 'art_pipe', 1);
src_oinfo_brain_s2(outDir, 'sparse', 'art_pipe', 1);
src_parcels_figure('dkt62');

runtests('test_src_oinfo3'); runtests('test_src_oir_full');
```

## Results index

### Preprocessing (`results/preprocessing/`)

| Folder | Content |
|---|---|
| `20260926_153251`, `20260926_163106` | first validation runs (default settings) |
| `20260926_202123_*` | per scenario: combinedA, combinedB, electrode, stroke_acute, stroke_chronic |
| `20260927_1050*_v2_*` | reruns after the ECG, pop and drift fixes |
| `20260927_1314*_v3_*`, `*_v3base_*` | muscle threshold comparison (v3) against baseline |
| `20260927_151117_v3base_combined2` | baseline, combined artifacts, second run |
| `report_revision/` | preprocessing report (`report.tex`, `report.pdf`) and fig1 to fig12 |

### Source reconstruction (`results/source/`)

| Folder | Stage, measure | Settings | Content |
|---|---|---|---|
| `20261012_123032_src_initial` | Stage 1, static O | 5 seeds, 120 s, white sensor noise 10 dB, both atlases, 32/62 ch, template and matched head | metrics.csv (1000 rows), summary figure |
| `20261012_144211_src_stage2_quick` | Stage 2 quick, static O | 1 seed, 60 s, regional signals 0 dB over background | summary, brain maps (leakage, recovery) |
| `20261012_151122_src_stage2_quick_10dB` | Stage 2 quick, static O | as above, +10 dB | summary, leakage/recovery and O brain maps |
| `20261012_165325_src_stage2_quick_10dB_OIR` | Stage 2 quick, OIR per triplet | DKT 62, VAR(10), 150 control triplets, +10 dB | summary; lagged and instantaneous parts in metrics.csv |
| `20261012_163752_src_stage2_quick_10dB_OIRfull_c20` | Stage 2 quick, OIR full VAR | coarse 20, order by MDL (max 15), all 1140 triplets, +10 dB | summary |
| `20261012_175546_src_stage2_quick_10dB_champagne` | Stage 2 quick, static O | as `_10dB`, with Champagne as a third inverse | summary |
| `report_source/` | methods and Stage 1 report | | `source_methods.tex`, `.pdf`, `fig_stage1.pdf` |
| `parcels_dkt62.png` | the DKT 62 parcels and the target triplets | | |

Each run folder holds `metrics.csv` (one row per dataset, variant and method),
`distance.csv` (null condition against parcel distance), `setup.mat`, the
summary figure, and for Stage 2 the QC log of the pipeline (`derivatives/`).
The EEG data of the quick Stage 2 runs (`sim/`, `derivatives/*.set`) were
deleted on 2026-10-14 to save space; the brain-map scripts need them, so a
brain map of these runs means running them again.

## Findings so far

Single seeds and short recordings for Stage 2; read as direction, not size.

1. **The O-information estimator is correct.** On the true sources the error
   is below 0.011 nats and the false positive rate is about 0 (static), and
   the OIR estimate matches the exact value of the true VAR (-0.385 against
   -0.382).
2. **Source reconstruction creates most of the error; the pipeline and the
   artifacts change little.** In Stage 2 the four data variants (clean or with
   artifacts, with or without the pipeline) give nearly the same results.
3. **Leakage makes most independent triplets significant**: 50 to 90% for
   both inverse methods (Stage 1: 67 to 98%). With long recordings even tiny
   spurious values are significant, so the size of spurious O (`O0_abs_p95`,
   `fpr_eff`) matters more than the false positive rate.
4. **eLORETA blurs**: neighbouring parcels share one signal, which inflates
   redundancy (up to 1.5 nats against a true 0.40) and turns true synergy into
   redundancy under sparse activity.
5. **Beamformers lose the regional signals**: vertex LCMV, parcel-subspace
   LCMV, nulling beamformers and MCMV all recover |r| < 0.3 for interacting
   parcels. Cause: correlated (coherent) sources cancel, within each 15 mm
   patch and between interacting parcels, and small forward model errors
   cancel the target at high SNR. Not a code error (FieldTrip equals the
   textbook formula to 1e-12) and not the template head (the matched head
   fails too). With the exact parcel topographies LCMV recovers 0.86 to 0.99.
6. **Far triplets are lost** when one member is deep or medial (left V1 in the
   pericalcarine sulcus).
7. **Line noise must be removed before rate measures**: a pure sinusoid makes
   the fitted VAR deterministic and the OIR undefined (`src_oir3` returns NaN).
   Without the pipeline, LCMV still gives outliers of about 9 nats.
8. **The total OIR fails like static O** (both estimators): eLORETA inflates
   near redundancy, turns near synergy into redundancy (+0.2 to +0.6 against
   -0.38), and loses far triplets; LCMV flips signs.
9. **The lagged part of the OIR resists leakage but is insensitive.** Leakage
   goes mostly into the instantaneous part: spurious lagged OIR of
   independent triplets (95th percentile) 0.006 to 0.07 nats against 0.06 to
   0.24 for the instantaneous part (eLORETA). The lagged part never flips sign
   (near synergy: about 0 instead of +0.3), but keeps only 8 to 35% of the
   true lagged effect (far redundancy 0.04 to 0.07 of 0.20; far synergy
   -0.03 to -0.04 of -0.38) under sparse activity, and about 0 under dense
   activity. Specific, not sensitive.
10. **Champagne (sparse Bayesian learning) removes most of the blur but also
    the signal.** Spurious static O of independent triplets is the smallest
    of the three inverses (95th percentile 0.02 to 0.06 nats; eLORETA 0.04 to
    0.41, LCMV 0.12 to 0.17) and true redundancy is no longer inflated, but
    the target O shrinks towards 0 (near redundancy 0.10 to 0.18 of 0.40, far
    triplets about 0, synergy about 0 to +0.15) because it switches off weak
    or deep triplet members. Specific, not sensitive, like the lagged OIR.

## Next steps

See the source plan, section 14 "Status and next steps", for details.

1. Leakage null: per triplet, the O that leakage alone produces (independent
   sources through the same forward and inverse model); count only O above
   it. Combine with the lagged OIR.
2. Sensitivity of the lagged OIR: full Stage 2 with 300 s and 3 seeds,
   regional signal strength sweep, stronger and slower coupling, VAR order by
   criterion on downsampled data.
3. Triplet selection by cross-talk (resolution matrix), first for the UKE
   motor triplet M1, PMv, SMA.
4. Higher orders (4 to 6 parcels) and O-information gradients as brain maps.
5. Report: add Stage 2, the beamformer comparison and the OIR results to
   `source_methods.tex`. Later: Stage 3 (lesion head models from UKE MRIs).
