# Validation Plan: Genuine Interactions Through Artifacts and Cleaning

## Objective

The preprocessing validation (run_validation, run_it_validation) shows that
artifacts create spurious high-order and brain-heart interactions and that
the pipeline removes most of them. Its ground truth, however, has almost no
interactions: the mean true O-information is -0.003 to 0.013 nats and the
clean EEG is independent of the heart. Whether cleaning also preserves
genuine interactions therefore remains untested.

This plan adds known interactions to the clean EEG and asks, for each
artifact and severity:

1. Does the artifact hide, inflate or reverse a genuine interaction?
2. Does the pipeline restore it, leave it unchanged, or remove it together
   with the artifact?

## Relation to existing work

- Source Stage 2 (validation/source, run_src_stage2) already adds known
  redundant and synergistic regional signals to the same background and
  runs the pipeline. The analysis there is in source space, with one
  artifact mixture at 5 dB, and the result is dominated by source leakage
  ("the pipeline and the artifacts change little"). The present plan works
  at the sensor level, where the effect of cleaning is isolated, per
  artifact and per severity.
- Literature check (2026-10-14): no study found that tests the effect of
  artifact removal on O-information or on the O-information rate (OIR).
  Separation of the heartbeat-evoked potential (HEP) from the cardiac field
  artifact is an active topic (isoelectric EEG, beamforming, 2026
  preprints), but not for information-theoretic brain-heart measures.

## Ground truth

The clean EEG of sim_clean_eeg (the background) plus, per seed:

| Structure | Generator | True property |
|---|---|---|
| Redundant triplet | 3 cortical sources, AR(2) oscillators at 10 Hz, common driver x1 -> x2, x1 -> x3 at lag 2 (src_sources_var) | source OIR +0.38 nats |
| Synergistic triplet | 3 other cortical sources, common target x1 -> x3, x2 -> x3 | source OIR -0.38 nats |
| Heart -> brain coupling | 1 cortical theta source (4 to 8 Hz) whose log amplitude in heart period n depends on RR(n-1) | TE RR -> EEG > 0, TE EEG -> RR = 0 |
| Heartbeat-evoked potential | 1 cortical source, positive wave 0.3 s after each R peak | HEP of known amplitude |

The heart period series is shared by the brain-heart source, the HEP source
and the cardiac artifact (sim_heart), so the artifact beats with the
genuine coupling, as in a real recording.

Sources are drawn far apart (lf_get_source_spaced). The truth is the scalp
data of background plus structures, with the band-pass, channels and
reference of the pipeline output (sim_match), as in run_it_validation. The
structure is defined at the sensor level by comparison with the background
alone (same seed): channel triplets with O_true - O_bg > oGen are genuine
redundant triplets, those below -oGen genuine synergistic triplets.

## Tests

**T0. Ground truth check (gate, before any pipeline run).** On the clean
data of each seed:
- at least 10 genuine redundant and 10 genuine synergistic channel
  triplets (|O_true - O_bg| > 0.05 nats);
- TE RR -> EEG in the theta band at the peak channel of the brain-heart
  source significant (asymptotic chi-square test, p < 0.05) in all seeds,
  TE EEG -> RR not significant in at least 4 of 5;
- HEP at its peak channel above twice the floor (HEP of the background
  alone).

If a criterion fails, the strength is raised (coupledDb, bhDepth, hepUv) and
the value reported. Synergy at the scalp is the uncertain part: linear
mixing can turn it into redundancy.

**T1. Cleaning without artifacts.** Pipeline on the clean data only.
Genuine effects in the output against the truth: share of genuine triplets
with the true sign, ratio O_out / O_true, OIR of the target triplets
(lagged and instantaneous parts), TE RR -> EEG and its significance, HEP
amplitude and waveform correlation. Expected: preserved (ratio 0.8 to 1.2).
Checked as well: number of components removed, and whether the heartbeat
rule or ICLabel flags the HEP or brain-heart source.

**T2. Masking by artifacts.** Input against truth, per artifact and
severity, same measures. Hypotheses: ocular and cardiac artifacts add
redundancy and pull genuine synergy towards redundancy; the cardiac
artifact inflates the HEP and the instantaneous brain-heart term and may
dilute the lagged TE.

**T3. Recovery after cleaning.** Output against truth, same measures, plus
the spurious measures of run_it_validation on the remaining triplets.
Hypotheses: recovery for ocular, cardiac, line and pop artifacts; partial
for muscle. Open question: does removing the cardiac component also remove
part of the genuine HEP?

**T4. Decision level.** Share of genuine effects still detected (TE
significance, sign of O on genuine triplets) and share of null effects
detected (TE EEG -> RR, background triplets), input against output. This
is the result a user of the measures needs.

## Factors

Artifacts as in the current per-artifact run (eog_blink, eog_vertical,
eog_horizontal, emg_temporal, emg_frontal, emg_neck, ecg, line, drift, pop,
eog_blink+ecg, emg_temporal+ecg), SNR 10, 5, 0, -5 dB, seeds 1 to 10.

## Statistics and pitfalls

- With 5 seeds the smallest two-sided p of a Wilcoxon signed-rank test is
  0.0625, so 10 seeds are planned; results are reported as medians and
  ranges, with paired differences input against output per seed.
- TE and MIR are linear Gaussian estimates from about 140 beats (120 s at
  70 bpm). The chi-square test is asymptotic; beat-shuffle surrogates are
  the check if p values are near 0.05. Longer recordings (300 s) reduce the
  bias but cost ICA time.
- The interacting sources are not independent, which violates the ICA
  model. The pipeline may merge each triplet into fewer components: this is
  part of what is tested, not a flaw of the test.
- Sensor-level O of genuine triplets depends on the source positions, so
  results are pooled over seeds with different positions.
- Removing components makes the data rank deficient. Triplets are not
  affected; larger multiplets would need care.
- The HEP waveform has power below 8 Hz, outside the QRS band of the
  heartbeat rule; a flag of the HEP component would come from ICLabel or
  from merging with the cardiac component.

## Implementation

| File | Change |
|---|---|
| validation/preprocessing/sim_heart.m | new: R peak times, RR (AR(4)) and the beat-level log amplitude of the brain-heart source, with heart -> brain and brain -> heart couplings |
| validation/preprocessing/sim_coupled.m | new: the four structures, projected through the lead field, with their source indices and peak channels |
| validation/preprocessing/mir_lin.m | moved out of run_it_validation (needed by T0) |
| validation/preprocessing/sim_ecg.m | uses sim.beats when present (shared heart) |
| validation/preprocessing/sim_config.m | sim.coupling and its parameters, off by default |
| validation/preprocessing/run_validation.m | adds the structures when sim.coupling is on; saves the background as ground_truth/s<seed>_bg.set |
| validation/preprocessing/run_it_validation.m | genuine-structure measures (T1 to T4) when the run has coupling |
| validation/preprocessing/check_coupled_truth.m | T0 |

Run order: check_coupled_truth (T0, a few minutes), then

    s = struct('runName', 'genuine', 'coupling', true, 'seeds', 1:5, 'secs', 300, ...
               'coupledDb', -5, 'hepUv', 3, 'artifacts', {{'eog_blink', 'eog_vertical', ...
               'eog_horizontal', 'emg_temporal', 'emg_frontal', 'emg_neck', 'ecg', ...
               'line', 'drift', 'pop', 'eog_blink+ecg', 'emg_temporal+ecg'}});
    run_validation(s)
    run_it_validation(runDir)

An interrupted run continues with run_validation([], runDir).

## Status (2026-10-14)

**T0, 5 seeds:**

| Setting | Triplets per sign | TE RR -> EEG | TE EEG -> RR | HEP > 2 x floor |
|---|---|---|---|---|
| 120 s, triplets 0 dB, HEP 2 uV | 870 to 1680 | p < 0.007 in 5/5 | p > 0.2 in 5/5 | 0/5 |
| 120 s, triplets -5 dB, HEP 2 uV | 770 to 1520 | p < 0.013 in 5/5 | p > 0.2 in 5/5 | 0/5 |
| 300 s, triplets -5 dB, HEP 3 uV | 780 to 1620 | p < 1e-7 in 5/5 | p > 0.08 in 5/5 | 3/5 |

- The HEP floor is the beat average of everything but the HEP: about 1 uV
  even at 300 s, because the channel SD is 10 to 20 uV. Seeds 4 and 5 stay
  below 2 x floor (HEP 1.1 and 1.7 uV). The HEP results of these seeds are
  read as noisy.
- The genuine structure is strong: about a third of all channel triplets
  change by more than 0.05 nats. Weaker settings (coupledDb -10) are an
  option for a sensitivity check.

**Smoke test** (1 seed, 60 s, ecg at -5 dB; output deleted). Not a result,
only a check that the code runs:
- The input reverses genuine synergy (O -0.062 true, +0.075 input). The
  output restores it (ratio 0.99, sign kept in 97% of triplets).
- TE RR -> EEG is unchanged in input and output.
- The HEP keeps 86% of its amplitude after cleaning (2.28 against 2.66 uV,
  waveform r 0.88).
- On the clean data the pipeline rejected F8 and Fp1 as bad channels. F8 is
  the HEP peak channel and Fp1 lies next to the brain-heart peak (Fp2). If
  the full run confirms this, bad-channel detection removes genuine focal
  activity. Otherwise the simulated sources are too focal.
  bh_peak_kept and hep_peak_kept record it.

**Run time estimate:** about 245 datasets at 300 s, roughly 3 min each,
so about 12 h for 5 seeds. 10 seeds would take about 24 h.
