# Automated EEG Preprocessing (`prep`)

A MATLAB toolbox for **preprocessing of EEG recordings** on top of EEGLAB.
It runs a pipeline over a folder of datasets. For every subject it writes a
cleaned dataset, a row in a group **quality-control table (QC)**, and
**diagnostic figures**.

## Pipeline 

```
import
  -> drop non-EEG channels          (labels + chanlocs.type)
  -> attach and verify positions    (errors below cfg.minLocFrac)
  -> resample
  -> line noise                     (zapline-plus, notch fallback)
  -> filter, two branches           (cfg.hpAnalysis and cfg.hpICA)
  -> bad channels                   (clean_rawdata)
  -> reference                      (average, none, or named channels)
  -> ICA                            (PCA dimension = measured rank)
  -> ICLabel                        (flag and subtract)
  -> [interpolate]
  -> [epoch]                        (+ baseline, + epoch rejection)
  -> save
```

**Two filter branches.** ICA converges better on 1 Hz high-passed data, but a
1 Hz high-pass also removes activity that many analyses depend on.

The pipeline estimates the unmixing matrix on a 1 Hz copy and applies it to
the `cfg.hpAnalysis` copy, so the components come from data ICA handles well
while the saved data keeps everything above `cfg.hpAnalysis`, 0.1 Hz by
default. Cutoffs between 0.5 and 1.5 Hz measure best for 64-channel ICA, which
is where the `cfg.hpICA` default of 1 Hz comes from. 

See:

- Zakeri, Z., Assecondi, S., Bagshaw, A. P., & Arvanitis, T. N. (2014). Influence of signal preprocessing on ICA-based EEG decomposition. IFMBE Proceedings, 41, 734-737. https://doi.org/10.1007/978-3-319-00846-2_182

- Tanner, D., Morgan-Short, K., & Luck, S. J. (2015). How inappropriate high-pass filters can produce artifactual effects and incorrect conclusions in ERP studies of language and cognition. Psychophysiology, 52(8), 997-1009. https://doi.org/10.1111/psyp.12437

- Winkler, I., Debener, S., Müller, K. R., & Tangermann, M. (2015). On the influence of high-pass filtering on ICA-based artifact reduction in EEG-ERP. Proceedings of the 37th Annual International Conference of the IEEE Engineering in Medicine and Biology Society (EMBC), 4101-4105. https://doi.org/10.1109/EMBC.2015.7319296

- Dimigen, O. (2020). Optimizing the ICA-based removal of ocular EEG artifacts from free viewing experiments. NeuroImage, 207, 116117. https://doi.org/10.1016/j.neuroimage.2019.116117

- Klug, M., & Gramann, K. (2021). Identifying key factors for improving ICA-based decomposition of EEG data in mobile and stationary experiments. European Journal of Neuroscience, 54, 8406-8420. https://doi.org/10.1111/ejn.14992

- van Driel, J., Olivers, C. N. L., & Fahrenfort, J. J. (2021). High-pass filtering artifacts in multivariate classification of neural time series data. Journal of Neuroscience Methods, 352, 109080. https://doi.org/10.1016/j.jneumeth.2021.109080

Treat this as a starting point. Several steps are optional, and you should
adapt both the parameter values and the choice of steps to your recording
setup and to the analysis that follows.

## Repository Structure

```
Automated_Pipeline_EEG_Preprocessing/
├── run_preprocessing.m   Batch entry point
├── lib/                  Pipeline functions
├── config/               Per-study parameter files
├── tests/                Pipeline validation and test data
└── README.md
```

### `lib/`

Listed in the order a batch uses them.

| File | Purpose |
|------|---------|
| `prep_config.m` | Holds the defaults, merges overrides, rejects unknown field names |
| `prep_checkcfg.m` | Validates parameter values before a batch starts |
| `prep_env.m` | Records MATLAB, EEGLAB and plugin versions; checks out required licences |
| `prep_saveconfig.m` | Saves the parameters next to the output files |
| `prep_find.m` | Locates the recordings, searching subfolders |
| `prep_subject.m` | Runs the pipeline for one recording |
| `prep_load.m` | Reads one recording, and names the reader a file extension needs |
| `prep_noneeg.m` | Drops non-EEG channels by label pattern and `chanlocs.type` |
| `prep_chanlocs.m` | Attaches electrode positions by label matching, then verifies them |
| `prep_reref.m` | Applies the reference: average, none, or named channels |
| `prep_rank.m` | Measures the numerical rank, which sets the ICA dimension |
| `prep_trial_time.m` | Works out when each trial happened, for the epoch figure |
| `prep_epoch.m` | Epochs (time-locked or fixed length), corrects the baseline, rejects bad epochs |
| `prep_epoch_labels.m` | Works out which condition each epoch is locked to, for the trial counts and the epoch figure |
| `prep_epoch_zero.m` | Finds the time-locking event of one epoch, the rule both of those depend on |
| `prep_event_str.m` | Reads an event type as text, whether it was stored as char, string or a number |
| `prep_snapshot.m` | Keeps a pre-filter spectrum, trace segment and event times for the QC figures |
| `prep_psd.m` | Computes a Welch spectrum, one column per channel |
| `prep_ic_summary.m` | Unpacks the ICLabel result the two component sheets both read |
| `prep_newfig.m` | Opens the off-screen figure a QC sheet is drawn into |
| `prep_savefig.m` | Writes one QC sheet to a PNG |
| `prep_qcfig.m` | Plots spectra, channel statistics and ICLabel decisions |
| `prep_qcfig_ics.m` | Plots scalp maps of removed and near-threshold components |
| `prep_qcfig_data.m` | Plots every channel trace, before and after, with event markers |
| `prep_qcfig_epochs.m` | Plots the average per condition, and how many trials were kept |
| `prep_qc_write.m` | Saves one small QC file per subject, as soon as that subject finishes |
| `prep_qc_merge.m` | Puts those files together into one `qc_log.csv` |

Used before a batch, not part of it:

| File | Purpose |
|------|---------|
| `prep_concat.m` | Merges the separate runs of one subject into a single file |


## Requirements

- MATLAB R2020a or later 
- **Signal Processing Toolbox** for `filtering`, `resampling`, `clean_rawdata`
- EEGLAB with `clean_rawdata`, `ICLabel`, `firfilt`, `dipfit`
- Optional: `zapline-plus` (line noise), `EEG-BIDS`

`prep_env` verifies all of this at startup and stops if something is missing.

## Quick Start

Put EEGLAB in `lib/toolboxes/eeglab`, or set `cfg.eeglabPath`. Then:

```matlab
run_preprocessing()                       % defaults
run_preprocessing('config/my_study.m')    % defaults + study overrides
run_preprocessing(struct('lp', 100))      % defaults + inline overrides
T = run_preprocessing(...);               % returns the QC table
```

A study file lists only what differs from the defaults:

```matlab
function cfg = my_study()
cfg.inDir  = 'D:\data\study_x\raw';
cfg.outDir = 'D:\data\study_x\derivatives';
cfg.lp     = 100;
cfg.events = {'S 1','S 2'};
end
```
`lib/prep_config.m` documents every parameter.

The pipeline looks inside subfolders, so you can leave a dataset in the
folder layout it came in: `S001/S001R01.edf`, `sub-01/eeg/`. Set
`cfg.recursive = false` to search only the top folder.

### Concatenating runs

ICA needs roughly `20*rank^2` samples (heuristic rule proposed by EEGLAB toolbox creators). Datasets split into short runs cannot
supply that per run, and the pipeline says so via `qc.ica_underpowered`. 

See:

- Makeig, S., & Onton, J. (2011). ERP features and EEG dynamics: An ICA perspective. In The Oxford Handbook of Event-Related Potential Components (pp. 51-86). Oxford University Press. https://doi.org/10.1093/oxfordhb/9780195374148.013.0035

- Kim, H., Luo, J., Chu, S., Cannard, C., Hoffmann, S., & Miyakoshi, M. (2023). ICA’s bug: How ghost ICs emerge from effective rank deficiency caused by EEG electrode interpolation and incorrect re-referencing. Frontiers in Signal Processing, 3, 1064138. https://doi.org/10.3389/frsip.2023.1064138

Merge a subjects runs first:

```matlab
prep_concat('data', 'data_concat', 'GroupBy', '^(sub-\d+)')
prep_concat(inDir, outDir, 'FileExt', '*.edf', 'GroupBy', '^(sub-\d+)')
```

`GroupBy` is required. It is a regexp whose first capture group is the
subject id in a file name. There is no default, because run naming belongs
to the dataset and guessing it wrong merges two subjects into one file.
`prep_concat` checks that sampling rate and channels match before it merges
anything.

### Epoching

Two ways to cut epochs. Set the parameter for the one you want:

```matlab
cfg.events   = {'S 1','S 2'};   % time-locked: event types to lock to
cfg.window   = [-0.2 0.8];      % SECONDS, around the event
cfg.baseline = [-200 0];        % MILLISECONDS; [] = no baseline correction
```

```matlab
cfg.epochLength  = 2;           % fixed length: seconds per epoch
cfg.epochOverlap = 0;           % fraction in [0, 1)
cfg.baseline     = [];          % fixed epochs start at 0, see below
```

Set neither and the data stays continuous. Setting both stops the batch
with an error, because there is no way to tell which one you meant.

Use fixed length for resting state, and for any recording whose triggers
mean nothing, where the epochs are only a way of cutting the time into
pieces. A recording with no usable triggers cannot be epoched time-locked at
all, while `cfg.epochLength = 2` cuts it into 2 s pieces regardless of what
the event table holds.

A fixed epoch runs from 0 to `cfg.epochLength`, so the default baseline of
`[-200 0]` cannot sit inside one. `prep_checkcfg` stops the batch and tells
you to set `cfg.baseline = []`, rather than skipping the correction without
saying so.

`qc.epoch_mode` says which of the two ran, and with what settings: `events
[-0.2 0.8] s`, `fixed 2 s`, or `fixed 2 s, 50% overlap`.

Baseline correction is a separate choice from epoching, and `[]` skips it.
It subtracts a constant per trial and per channel, so it changes every value
downstream. 

Epoch rejection is off by default. If you want it on:

```matlab
cfg.epochReject = true;
cfg.epochThresh = 150;   % uV, +/-;  [] = no amplitude criterion
cfg.epochProbSD = 5;     % joint probability, SD;  [] = no such criterion
```

`prep_epoch` checks both criteria first and then removes once, so an epoch
caught by both still counts as one. Above `cfg.epochMaxRejFrac` (0.40) you
get a warning and the batch carries on. Deciding which subjects to drop is
your job rather than the job of the pipeline, and the QC row is what you
decide from.

What ends up in `qc_log.csv`:

| Column | Meaning |
|--------|---------|
| `epoch_mode` | Which of the two ran, and with what settings |
| `epoch_events` | Event types found and used, or `fixed` |
| `epoch_missing` | Requested types with no events in this recording |
| `epoch_counts` | Trials per condition, `S 1:59\|S 2:58` |
| `n_epochs_built` | Epochs `pop_epoch` produced |
| `n_epochs_lost` | Events that gave no epoch: too near the end, or across a break in the data |
| `n_epochs_rejected` | Removed by the rejection criteria |
| `n_epochs_rej_thresh`, `n_epochs_rej_prob` | How many each check caught on its own |
| `epoch_rej_frac` | Fraction rejected, to compare against `cfg.epochMaxRejFrac` |
| `n_epochs` | Trials in the saved file |
| `baseline` | `none`, or the window removed |
| `epoch_reject` | `off`, or the criteria applied |

The numbers add up, so you can always see where a trial went:

```
n_epochs_built = n_epochs + n_epochs_rejected
n_epochs_built + n_epochs_lost = events that matched
```

## Output

| File | Contents |
|------|----------|
| `<subject>_clean.set` | Preprocessed data |
| `<subject>_qc.png` | Spectra before/after, per-channel spectra, channel RMS, ICLabel decisions |
| `<subject>_qc_ics.png` | Scalp maps of removed and near-threshold components |
| `<subject>_qc_data.png` | Channel traces, before and after, on a shared scale, with event markers |
| `<subject>_qc_epochs.png` | The average per condition, every single trial, amplitude across the session, and how many trials were kept. Only written if you epoched |
| `<subject>_error.log` | Error report, written only on failure |
| `qc_log.csv` | One row per subject, including failures, with what each step did |
| `qc/<subject>.mat` | The same QC numbers for one subject, kept as a .mat file |
| `config.json`, `config.mat` | Parameters used on the batch run |

`prep_qc_merge(outDir)` rebuilds `qc_log.csv` at any time, including from a
second MATLAB session while a batch is still running.

## Tests

```matlab
run_tests('unit')      % Tests the individual functions in the pipeline
run_tests('pipeline')  % 7 tests, ~9 min
run_tests              % everything
```

`tests/prep_testdata.m` generates synthetic EEG with known ground truth: 1/f
spectrum, controllable alpha and line noise, deliberate rank deficiency, and
optional spatially smooth fields built from real electrode coordinates.

## License

The code is provided free of charge. It is neither exhaustively tested nor
particularly well documented. The author accepts no liability for its use. Use,
modification and redistribution of the code is allowed in any way users see fit.
The author asks only that authorship is acknowledged upon utilization of the
code in integral or partial form.
