# EEG Preprocessing Validation Plan

## Objective

Develop a controlled simulation and artifact-injection framework to validate an EEG preprocessing pipeline implemented in MATLAB/EEGLAB.

The main goals are to determine whether the preprocessing pipeline:

1. Removes different EEG artifacts effectively.
2. Preserves genuine neural EEG activity.
3. Performs robustly across different artifact severities.
4. Preserves EEG characteristics relevant to acute and chronic stroke.

## Overall workflow

```text
Clean simulated EEG
        |
        +----> Add EOG artifacts
        +----> Add EMG artifacts
        +----> Add ECG artifacts
        +----> Add line noise
        +----> Add electrode drift
        +----> Add electrode pops
        +----> Add bad channels
        |
        v
Contaminated EEG
        |
        v
EEGLAB preprocessing pipeline
        |
        v
Processed EEG
        |
        v
Compare with clean ground truth
```

Always retain the original clean EEG as the **ground truth**.

## 1. Generate clean EEG

Use a MATLAB EEG simulation toolbox such as **SEREEGA** to generate physiologically plausible clean EEG.

For the stroke application, later include characteristics such as:

* altered spectral power
* focal abnormalities
* slowing
* hemispheric asymmetry
* other physiologically relevant changes

This avoids validating the preprocessing pipeline only on healthy-looking synthetic EEG.

## 2. Artifact injection

Create a MATLAB artifact-injection layer that takes clean EEG and adds controlled artifacts.

General principle:

```matlab
EEG_contaminated = EEG_clean + alpha * artifact;
```

where `alpha` controls artifact strength.

Use several severity levels:

* Low
* Medium
* High
* Severe

Preferably define severity using a reproducible metric such as SNR.

## 3. EOG / eye-blink artifacts

Use real EOG/ocular artifact segments when possible.

```text
Real EOG artifact
       |
       v
Extract artifact segment
       |
       v
Scale artifact
       |
       v
Inject into clean EEG
```

Test:

* eye blinks
* horizontal eye movements
* vertical eye movements
* different artifact strengths

## 4. EMG / muscle artifacts

Use real EMG-contaminated EEG segments where possible.

Inject into selected channels:

```matlab
channels = [1 2 3 4 5];

EEG_contaminated.data(channels,:) = ...
    EEG_clean.data(channels,:) + alpha * EMG_artifact;
```

Vary:

* amplitude
* duration
* affected channels
* artifact location

## 5. ECG / cardiac artifacts

Use real ECG contamination or ECG recordings when possible.

```matlab
EEG_contaminated.data = ...
    EEG_clean.data + alpha * ECG_artifact;
```

Test low, medium and high contamination.

## 6. Power-line noise

For a 50-Hz environment:

```matlab
fs = EEG.srate;
t = (0:size(EEG.data,2)-1) / fs;

line_noise = sin(2*pi*50*t);

EEG_contaminated.data = ...
    EEG_clean.data + alpha * line_noise;
```

Harmonics can also be added:

```matlab
line_noise = ...
    sin(2*pi*50*t) + ...
    0.5*sin(2*pi*100*t) + ...
    0.25*sin(2*pi*150*t);
```

Adapt the frequency to the recording environment.

## 7. Electrode drift

Generate slow variations or use real drift artifacts.

```matlab
drift = sin(2*pi*0.1*t);
```

Inject into selected channels:

```matlab
bad_channel = 15;

EEG_contaminated.data(bad_channel,:) = ...
    EEG_clean.data(bad_channel,:) + alpha * drift;
```

Test the ability of the pipeline to handle slow baseline changes and bad channels.

## 8. Electrode pops / transient artifacts

Generate short, high-amplitude transient events.

```matlab
duration = round(0.2 * fs);

artifact = zeros(1,length(t));

start = round(10*fs);

artifact(start:start+duration) = ...
    100 * sin(linspace(0,pi,duration+1));
```

Inject into one or more channels:

```matlab
EEG_contaminated.data(20,:) = ...
    EEG_clean.data(20,:) + artifact;
```

Vary:

* amplitude
* duration
* number of events
* location
* affected channels

## 9. Bad channels

Simulate channels that should be detected and rejected/interpolated.

### Completely noisy channel

```matlab
bad_channel = 20;

EEG_contaminated.data(bad_channel,:) = ...
    5 * randn(1,size(EEG.data,2));
```

### Flat channel

```matlab
EEG_contaminated.data(bad_channel,:) = 0;
```

Other conditions can include:

* excessive variance
* excessive line noise
* intermittent noise
* low correlation with neighboring channels

## 10. Combined artifacts

Suggested conditions:

```text
Dataset 1:  Clean

Dataset 2:  Clean + EOG
Dataset 3:  Clean + EMG
Dataset 4:  Clean + ECG
Dataset 5:  Clean + line noise
Dataset 6:  Clean + bad channels
Dataset 7:  Clean + electrode drift
Dataset 8:  Clean + electrode pops

Dataset 9:  EOG + EMG
Dataset 10: EOG + ECG
Dataset 11: EOG + line noise
Dataset 12: EMG + ECG
Dataset 13: EOG + EMG + ECG
Dataset 14: EOG + EMG + bad channels
Dataset 15: Multiple artifacts
```

Test each condition at several severity levels.

## 11. Quantitative evaluation

Compare:

```text
Clean ground truth
        vs.
Preprocessed contaminated EEG
```

Possible metrics:

### Signal similarity

* Pearson correlation
* RMSE
* mean absolute error

### Artifact suppression

* SNR before preprocessing
* SNR after preprocessing
* residual artifact amplitude
* artifact-to-signal ratio

### Spectral preservation

Compare power spectra before contamination and after preprocessing.

Measure:

* delta
* theta
* alpha
* beta
* gamma
* absolute power
* relative power

### ERP preservation

If event-related activity is simulated:

* ERP amplitude
* ERP latency
* waveform correlation
* area under the ERP

### Pipeline behavior

Record:

* number of rejected channels
* number of interpolated channels
* number of rejected epochs
* number of ICA components removed
* percentage of data removed
* preprocessing failures

The key question is:

> Did the pipeline remove the artifact while preserving genuine EEG activity?

## 12. Real artifact data

After testing synthetic artifacts, incorporate real artifact recordings.

```text
Real artifact recording
        |
        v
Extract artifact segment
        |
        v
Normalize / scale
        |
        v
Inject into clean EEG
        |
        v
EEGLAB preprocessing
```

Potential sources:

* EOG segments
* EMG segments
* ECG segments
* electrode movement/pop segments

This provides more physiologically realistic contamination while retaining experimental control.

## 13. Stroke-specific validation

Use three levels.

### Stage 1 — Technical validation

```text
Clean simulated EEG
        +
Controlled artifacts
        |
        v
EEGLAB preprocessing
        |
        v
Compare with clean ground truth
```

### Stage 2 — Physiological/stroke-relevant validation

Generate or use EEG with characteristics relevant to stroke:

* spectral slowing
* hemispheric asymmetry
* focal abnormalities
* altered band power
* other clinically relevant EEG features

Then add controlled artifacts.

The objective is to determine whether preprocessing preserves potentially important stroke-related EEG characteristics.

### Stage 3 — Real EEG validation

Apply the final pipeline to:

* acute stroke EEG
* chronic stroke EEG

Compare the behavior observed in real data with the simulation results.

## 14. Suggested MATLAB project structure

```text
EEG_Simulation/
│
├── main_simulation.m
│
├── generate_clean_EEG.m
│
├── artifacts/
│   ├── add_EOG.m
│   ├── add_EMG.m
│   ├── add_ECG.m
│   ├── add_line_noise.m
│   ├── add_drift.m
│   ├── add_electrode_pop.m
│   └── add_bad_channel.m
│
├── preprocessing/
│   └── run_EEGLAB_pipeline.m
│
├── evaluation/
│   ├── calculate_SNR.m
│   ├── calculate_RMSE.m
│   ├── calculate_correlation.m
│   ├── compare_spectrum.m
│   └── compare_ERP.m
│
├── configs/
│   └── simulation_parameters.m
│
└── results/
```

## 15. Recommended initial experiment

Start small:

1. Generate clean EEG.
2. Add EOG at four contamination levels.
3. Run the EEGLAB preprocessing pipeline.
4. Compare processed EEG against clean EEG.
5. Repeat for EMG, ECG and line noise.
6. Test combinations of artifacts.
7. Introduce real artifact segments.
8. Repeat using EEG characteristics relevant to acute and chronic stroke.

## 16. Central experimental principle

```text
                  KNOWN GROUND TRUTH
                         |
                         v
                     Clean EEG
                         |
                  Add known artifact
                         |
                         v
                Contaminated EEG
                         |
                         v
                EEGLAB pipeline
                         |
                         v
                 Processed EEG
                         |
              ┌──────────┴──────────┐
              v                     v
       Artifact removal       Neural signal
          performance           preservation
```

A successful preprocessing pipeline should not only remove artifacts; it should also preserve the EEG features relevant to the scientific question.
