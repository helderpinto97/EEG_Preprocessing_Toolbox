# EEG Source Reconstruction Validation Plan

## Objective

Validate source reconstruction of preprocessed EEG for the information-theoretic analyses of the WEAVE project (WP2 and WP4): O-information, local O-information, gradients of O-information, and its spectral and dynamic forms, computed on parcel time series of stroke patients.

The main questions are:

1. Which inverse method recovers the sign and size of O-information between parcels?
2. How much spurious redundancy does source leakage create when the sources are independent?
3. How many parcels can be used before the parcel time series become linearly dependent?
4. How much does a stroke lesion that the head model ignores change the result?
5. Do the steps of the preprocessing pipeline (average reference, bad channels, IC subtraction) change the answer?

## Why ground truth is possible here

For Gaussian variables, O-information follows exactly from the covariance matrix. The source signals of a simulation have a known covariance, so the true O-information of every multiplet is known before any EEG is generated. For VAR models the O-information rate and its spectral decomposition also follow from the model parameters (Faes et al. 2022).

```text
Source model with known covariance / VAR parameters
        |
        +----> true O-information (analytic)
        |
        v
Forward model (lead field, with or without lesion)
        |
        v
Scalp EEG + background + artifacts
        |
        v
prep pipeline (lib/)
        |
        v
Inverse model -> parcel time series
        |
        v
Estimated O-information
        |
        v
Compare with the true value
```

## 1. Source models with known higher-order structure

Place each multiplet on the centroids of chosen parcels. Use the motor network of the grip task (M1, PMd, SMA, S1, in both hemispheres) and also pairs of parcels at increasing distances, so that leakage can be related to distance.

### Null: independent sources

```matlab
X = randn(n, T);          % true O-information = 0
```

Any nonzero estimate is produced by the forward and inverse models. This is the most important condition.

### Redundant multiplet: common driver

```matlab
s = randn(1, T);
X = a * repmat(s, n, 1) + randn(n, T);   % O-information > 0
```

### Synergistic multiplet

```matlab
x1 = randn(1, T);
x2 = randn(1, T);
x3 = x1 + x2 + b * randn(1, T);          % O-information < 0
X  = [x1; x2; x3];
```

### Dynamic multiplets

Generate VAR(p) processes with known coupling, including a common driver and a target driven jointly by two sources. These give the true O-information rate and its value per frequency band.

### Gaussian O-information from the covariance

```matlab
function O = oinfo_gauss(C)
% O-information of a Gaussian vector with covariance C (nats).
n = size(C, 1);
H = @(S) 0.5 * log((2*pi*exp(1))^size(S,1) * det(S));
O = (n - 2) * H(C);
for j = 1:n
    rest = setdiff(1:n, j);
    O = O + H(C(j,j)) - H(C(rest,rest));
end
end
```

The same function gives the true value (source covariance) and the estimate (parcel covariance, or the Gaussian copula transform of the parcel time series).

### Vary

* coupling strength (`a`, `b`)
* multiplet order (3, 4, 5)
* distance between the parcels of a multiplet
* depth (cortical surface or deep sources)
* hemisphere (same side as the lesion or opposite side)

## 2. Background, artifacts and preprocessing

Add the multiplet sources to the background, alpha and theta sources of `sim_clean_eeg.m`, then add artifacts with the existing artifact layer (`sim_inject.m`) and run the pipeline in `lib/`.

Conditions:

* sources only, no background (upper bound)
* sources + background
* sources + background + artifacts, after the pipeline

This shows how the drop in rank from IC subtraction and from removed channels affects the source estimates.

## 3. Head models

Simulating and inverting with the same head model (the inverse crime) gives results that are too good. Use a different model for the inverse.

| Forward (simulation) | Inverse | Purpose |
|----------------------|---------|---------|
| HArtMuT New York Head | HArtMuT New York Head | Upper bound only |
| HArtMuT New York Head | Template BEM (fsaverage or ICBM152, OpenMEEG) | Realistic case for subjects without MRI |
| FEM with lesion | FEM without lesion | Error from ignoring the lesion |
| FEM with lesion | FEM with lesion | Benefit of a lesion-aware model |

### Lesion head model

Build an FEM from a template MRI segmentation (ICBM152, SimNIBS `charm` or FieldTrip + DUNEuro). Mark a sphere at `sim.lesionCentre` with radius `sim.lesionRadius` as a separate compartment, so the lesion matches the stroke conditions of the preprocessing validation. This template lesion is a quick first check; Stage 3 (Section 10) uses head models built from the patient MRIs instead.

| Stage | Lesion conductivity | Note |
|-------|---------------------|------|
| Chronic | CSF, 1.79 S/m | Cavity filled with CSF |
| Acute | sweep between brain (0.33 S/m) and CSF | Edema; the value is uncertain, so it is a parameter, not a fixed setting |

SEREEGA reads FieldTrip lead fields (`lf_generate_fromfieldtrip`), so the FEM lead field can feed the existing simulation code.

### Source space

* Remove the vertices inside the lesion from the inverse source space, and compare with keeping them.
* A parcel that lies fully inside the lesion has no true activity. Measure the power the inverse solution assigns to it.

## 4. Inverse methods

| Method | Notes |
|--------|-------|
| eLORETA | No noise covariance needed; smooth solution |
| LCMV beamformer | Data covariance regularised to the rank of the data |
| MNE / dSPM | Noise covariance from simulated sensor noise, and identity as the alternative |
| Champagne (optional) | Sparse, handles correlated sources |

The lead field must be average-referenced, like the data, and must contain only the channels that the pipeline kept.

## 5. Parcels and parcel time series

### Parcellations

* Coarse set of 20 to 30 parcels
* Desikan-Killiany, 68 parcels
* Brainnetome, 246 parcels (expected to fail with 32 or 64 channels; run it once to document the limit)
* Motor network subset only

### Parcel time series

* first principal component
* mean with sign flip
* vertex nearest the centroid

### Leakage correction

* none
* symmetric orthogonalisation (Colclough et al. 2015)

Orthogonalisation removes all zero-lag shared signal, including true redundancy. Report it as a separate condition, not as a fix.

## 6. Montage

* 32 channels (current simulation)
* 64 channels (UKE data)
* largest montage the lead field supports (San Camillo hd-EEG has 256)

## 7. Quantitative evaluation

### O-information

* error: estimated minus true, per multiplet
* sign accuracy: redundant, synergistic or null classified correctly
* rank correlation between true and estimated values over all multiplets
* false positive rate under the null, using the bootstrap test of the project Methods (p < 0.05); it should stay near 5%
* detection rate for the true multiplets
* for order 4 and above: whether the higher-order multiplet is found only when it adds information beyond its lower-order subsets

### Spectral and dynamic forms

* error of the O-information rate
* error per frequency band (delta to gamma)

### Source reconstruction

* peak localisation error and spatial spread of the point-spread and cross-talk functions
* correlation between true and reconstructed source time courses
* power assigned to lesioned parcels

### Parcel covariance

* effective rank and condition number
* number of parcels at which `det(C)` becomes unstable

### Pipeline

* rank of the data after the pipeline
* number of removed channels and components (from the QC table)

The key question is:

> Does the estimated O-information keep the sign and the ranking of the true multiplets, without creating redundancy between independent sources?

## 8. Acceptance criteria

Fix these before running the experiments:

* false positive rate under the null at or below 5% (after correction for the number of multiplets)
* sign accuracy above a set level, for example 90%, at the coupling strengths expected in real data
* no parcellation with more parcels than the rank of the data

A method and parcellation that pass in the healthy and the lesion conditions become the default for WP4. Settings tuned on the simulation stay options of the analysis, not defaults of the toolbox.

## 9. Real data checks

There is no ground truth in patient data. Check instead:

* agreement between eLORETA and LCMV
* split-half reliability of O-information within a recording
* power in lesioned parcels, against the simulation
* rank of every recording against the planned number of parcels
* removed components in patients against controls (ICLabel may mark slowing around the lesion as Eye or Channel Noise)

## 10. Stages

### Stage 1: Forward and inverse only

Healthy head, null and multiplet sources, no background. Compare inverse methods, parcellations, montages and leakage correction.

### Stage 2: Realistic data

Add background and artifacts, run the pipeline, repeat the best settings of Stage 1.

### Stage 3: Lesion, with head models from the patient MRIs

The lesion test uses head models built from the MRIs of the datasets, so lesion shape, atrophy and enlarged ventricles are real instead of a synthetic sphere. The source signals stay simulated.

#### Data

| Dataset | MRI | Use |
|---------|-----|-----|
| UKE | T1, FLAIR, DWI for all patients; lesions already delineated | Individual head models, acute and 1 year |
| San Camillo | MP-RAGE (and DTI) for about 40 of the 70+ patients | Individual head models for that subset; template for the rest |

Start with a few patients whose lesions differ in size and place (small subcortical, large cortical MCA, chronic cavity).

#### Head model steps (FieldTrip)

1. Segment the MRI. Use SimNIBS `charm` when the lesion is large; the standard SPM segmentation of `ft_volumesegment` often fails there.
2. Add the lesion mask (from FLAIR or DWI) as its own compartment: CSF conductivity (1.79 S/m) for chronic data, a sweep between brain (0.33 S/m) and CSF for acute data.
3. Build the head model with `ft_prepare_headmodel`: FEM (`duneuro` or `simbio`) with the lesion compartment, and a 3-shell BEM (`openmeeg`) without it.
4. Build the source model with `ft_prepare_sourcemodel` by warping one template grid (or template cortex with atlas) to each MRI, so every patient has the same parcels. O-information across patients and the comparison with the MSA results of WP3 both need this.
5. Remove the sources inside the lesion, and compare with keeping them.
6. Electrodes: digitised positions if they exist; otherwise a template cap fitted to the scalp of the MRI.

#### Simulate with one model, reconstruct with another

| Simulate with | Reconstruct with | Question |
|---------------|------------------|----------|
| Patient FEM with lesion | Same patient, BEM without lesion | Error from ignoring the lesion |
| Patient FEM with lesion | Template (ICBM152 BEM) | Error from having no MRI |
| Patient FEM with lesion | Same patient, FEM with lesion | Upper bound only |

Use the source models, multiplets and measures of Stage 1, and add the power assigned to lesioned parcels (Section 7).

#### Before starting

* Check that the data-sharing agreements (UKE ethics approval, EBRAINS for San Camillo) cover building head models from the MRIs and processing them at UGent.
* This is the first stage that uses real data (MRIs), unlike the preprocessing validation; report it as a separate stage.
* FEM with lesion compartments is slow and needs checking per patient; budget time per head model.

### Stage 4: Spectral and dynamic O-information

VAR sources, O-information rate and the spectral decomposition. Started; see section 14.

### Stage 5: Real data

UKE (64 channels, acute and 1 year) and San Camillo (256 channels).

## 11. MATLAB structure

The code is in `validation/source/`, next to the preprocessing simulation in `validation/preprocessing/`, and outside `lib/`. `validation/README.md` lists every file, how to run each stage and every result folder.

Toolboxes in `lib/toolboxes/`: FieldTrip 20251218 (eLORETA, LCMV), OIR (Faes et al. 2022) and SIR_toolbox (Sparacino et al.) for the O-information rate. Stage 3 also needs the OpenMEEG or DUNEuro binaries and SimNIBS, which are not installed yet.

## 12. Recommended initial experiment

1. Healthy head, 32 and 64 channels.
2. Null sources and one redundant and one synergistic triplet in the motor network, at near and far parcel distances.
3. eLORETA and LCMV on a template BEM.
4. 20-parcel set and Desikan-Killiany.
5. Measure the false positive rate under the null and the sign accuracy for the triplets.
6. Then add background, artifacts and the pipeline.
7. Then the lesion head model.

## 13. Central experimental principle

```text
              KNOWN SOURCE COVARIANCE
                         |
             +-----------+-----------+
             v                       v
      True O-information        Scalp EEG
                                     |
                              Pipeline + inverse
                                     |
                                     v
                          Estimated O-information
                                     |
              +----------------------+
              v                      v
      Spurious redundancy     Recovery of true
        under the null          multiplets
```

A source reconstruction is useful for this project only if it recovers the true multiplets and does not create multiplets from leakage.

## 14. Status and next steps

Updated 12 October 2026. Result folders and how to run: `validation/README.md`.

### Done

**Stage 1 (static, complete).** Run `20261012_123032_src_initial`: 5 seeds, 120 s, white sources on 15 mm patches, sensor noise at 10 dB, DKT 62 and coarse 20, 32 and 62 channels, template and matched head, eLORETA and LCMV through FieldTrip. Reported in `validation/results/source/report_source/source_methods.pdf`.

* True sources: error below 0.011 nats, false positive rate below 0.1%.
* Independent triplets flagged: eLORETA 67 to 94%, LCMV 88 to 98%; the head model changes this by at most 7 points.
* eLORETA inflates near redundancy (0.6 to 1.8 against 0.40) and turns synergy into redundancy under sparse activity; LCMV removes redundancy and creates false synergy. Errors are systematic (seed SD at most 0.035).

**Stage 2 (static, quick runs only).** 1 seed, 60 s, background EEG (SEREEGA), five artifacts at 5 dB, the pipeline, four variants (clean or with artifacts, with or without the pipeline). Runs at 0 dB and +10 dB of regional signal over background.

* The pipeline and the artifacts change the results little; source reconstruction dominates.
* Independent triplets flagged: 47 to 90%. At +10 dB eLORETA recovers far parcels better (weakest triplet parcel |r| 0.66 to 0.78) but near redundancy grows to 1.1 to 1.6 nats.
* Brain maps (leakage, recovery, true and estimated O per parcel) show spurious O over whole lobes; the true triplet does not stand out.

**Beamformer check.** The implementation is correct (FieldTrip equals the textbook formula to 1e-12). Vertex LCMV fails also with the matched head and with free orientation. Parcel-subspace LCMV, nulling beamformers and MCMV per triplet also lose the interacting parcels (|r| below 0.3). Causes: cancellation of coherent sources (within each patch and between interacting parcels) and self-cancellation from small forward model errors at high SNR. With the exact parcel topographies LCMV recovers 0.86 to 0.99. Beamformers are therefore unsuitable for this question unless the forward model of the whole active patch is nearly exact.

**Statistical point.** With long recordings the bootstrap flags very small spurious values (MCMV: 81% flagged, median |O| 0.004 nats). Report the size of spurious O (`O0_abs_p95`) and an effect-size rate (`fpr_eff`, |O| above 0.05 nats) next to the false positive rate.

**Stage 4 started (O-information rate).** Toolboxes OIR and SIR_toolbox installed. Dynamic ground truth: AR(2) oscillators, triplet coupled at 8 ms lag; common driver gives OIR +0.38 (lagged +0.20, instantaneous +0.18), common target gives -0.38 (all lagged). Two estimators:

* per triplet (`src_oir3`): VAR(10) per triplet, lagged/instantaneous split, 150 control triplets; NaN when the fitted VAR is near deterministic (line noise);
* full VAR (`src_oir_full`): one VAR on all coarse 20 parcels (order by MDL), restricted to each triplet through the spectral matrix; all triplets. The full model needs more data rank than parcels, so not DKT 62 (rank 48 to 61 after the pipeline).

Quick Stage 2 runs of both (+10 dB, 1 seed, 60 s): `20261012_165325_src_stage2_quick_10dB_OIR` and `20261012_163752_src_stage2_quick_10dB_OIRfull_c20`.

* True sources: estimate within 0.01 nats of the exact OIR, for both estimators.
* Total OIR fails like static O: eLORETA inflates near redundancy, turns near synergy into redundancy (+0.2 to +0.6 against -0.38) and loses far triplets; LCMV flips signs. Significance flags almost every independent triplet; |OIR| above 0.05 nats: eLORETA 6 to 34%, LCMV 35 to 86%.
* The lagged part resists leakage but is insensitive: spurious lagged OIR (95th percentile, eLORETA) 0.006 to 0.07 nats against 0.06 to 0.24 for the instantaneous part; it never flips sign, but keeps only 8 to 35% of the true lagged effect under sparse activity and about 0 under dense activity.
* With the pipeline the MDL order reaches the maximum (15): filtered data have long memory. Without the pipeline line noise makes fits near deterministic; LCMV then gives outliers of about 9 nats.

**Conclusion so far.** Between nearby regions neither static O nor total OIR can be trusted after linear source reconstruction from 62 channels; leakage produces O of the same size as the true interaction. The lagged OIR is the only measure that stays specific, at the cost of sensitivity.

**Corrections made along the way.** Two explanations of the LCMV failure were wrong (correlation between triplet members; template mismatch) before the tests above. ICLabel 'Other' is not removed by default. In the first OIR runs a variable name clash and a unit-circle VAR fit stopped the run; both fixed.

### Next steps

Ranked by expected gain against effort.

1. **Leakage null** (about 2 h of code, 20 min run): per triplet, the O that leakage alone produces, from independent sources passed through the same forward and inverse model (resolution matrix); count only O above it. Combine with the lagged OIR.
2. **Sensitivity of the lagged OIR**: full Stage 2 (3 seeds, 300 s, so ICA also has enough samples), sweep of regional signal strength (parcelDb), stronger and slower coupling, VAR order by criterion on downsampled data. Add a figure of lagged against instantaneous parts.
3. **Triplet selection by cross-talk** (about 1 h): resolution matrix per candidate triplet; first the UKE motor triplet M1, PMv, SMA.
4. **Higher orders**: multiplets of 4 to 6 parcels (log-determinant form), greedy search on DKT 62, exhaustive on coarse 20, O-information gradients as per-parcel maps.
5. **Report**: add Stage 2, the beamformer comparison and the OIR results to `source_methods.tex`.
6. **Stage 3**: ask UKE (Thomalla, Cheng) for the M1, PMv and SMA coordinates, the head models and the lesion masks; install SimNIBS and OpenMEEG or DUNEuro.
7. **Design**: contrasts between conditions or groups (acute against 1 year) cancel part of the leakage, but not when the lesion changes source power.
