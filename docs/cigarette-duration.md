# Cigarette duration and successive counting

Ciggy uses **300 seconds (five minutes)** as its default minimum duration of qualifying smoking-like activity per estimated cigarette. This is a rounded engineering default informed by measured smoking durations. It is **not an established global average**, a physical minimum, or a guarantee that a physical cigarette has finished.

## Research basis

Research reviewed on October 24, 2026 did not establish a representative, population-weighted worldwide mean. The following primary studies measured the time spent smoking a cigarette, rather than the length of an individual puff or the number of years a person had smoked:

| Study | Observed duration | Scope |
| --- | --- | --- |
| [Gass et al., *Nicotine & Tobacco Research*, 2016, Table 2](https://academic.oup.com/ntr/article/18/4/484/2583992) | Mean **5.6 minutes**, SD **1.6 minutes** | 107 non-daily smokers from Western New York, assessed over six laboratory visits using CReSS. Duration runs from the first puff's start to the last puff's end. |
| [Yang et al., 2022, Table 2](https://pmc.ncbi.nlm.nih.gov/articles/PMC9582419/) | Mean **179.4 seconds** (about **3 minutes**), SD **69.6 seconds**; reported range **30–385 seconds** | 100 Korean smokers monitored during 24 hours of ad-libitum smoking. Time per cigarette was estimated from measured puff counts, puff durations and intervals. |
| [Chen et al., 2018, Table 2](https://www.tobaccopreventioncessation.com/Video-assisted-topographical-measurement-of-cigarette-nsmoking-Exploration-of-an,90821,0,2.html) | Individual cigarette durations **2.48–8.56 minutes** | Ten Detroit-area participants videotaped smoking their first cigarette of the day normally after abstinence. Small purposive sample. |

These studies support a multi-minute estimate and demonstrate substantial variation. They do not justify combining their means into a global average: recruitment, setting, smoking frequency and measurement differ. The five-minute default is a product choice within this observed scale, not the output of a meta-analysis. The timing rule has not been validated against representative Apple Watch recordings.

## Implemented rule

`DetectionFusionEngine.Configuration.minimumSmokingDurationSeconds` defaults to `300` in both live and historical analysis.

1. Begin accumulating duration at the first recognized complete hand-to-mouth gesture.
2. Require both the duration and fresh gesture evidence: at least five accepted gestures at normal sensitivity, four at high sensitivity or seven at low sensitivity. The retained gesture window is eight minutes; accepted gestures must be at least six seconds apart.
3. Emit one estimated cigarette on a qualifying gesture when both requirements are met. A timer firing, a heart-rate update or the passage of time alone cannot emit a count.
4. Keep observing immediately. The previous emission starts the next duration segment, which requires another 300 seconds and a fresh set of qualifying gestures. A quiet interval is not needed to permit the next count.
5. Break incomplete evidence if accepted gestures are more than 150 seconds apart. Missing sensor data cannot establish continuous smoking or be converted into counts. Historical analysis persists duration progress with classifier state across batch boundaries and relaunches. Live monitoring clears incomplete duration when sampling stops or restarts, or when reported sample timestamps have a gap exceeding one second; checkpoint persistence cannot bridge those interruptions.

For a continuous stream with sufficient accepted gestures, the first estimate can occur at five minutes after the first recognized gesture, then further estimates at roughly ten and fifteen minutes. Actual emission occurs on a qualifying gesture, so those times are examples, not exact wall-clock deadlines. If the evidence stops, counting stops.

## Limits and verification

Shorter cigarettes may never reach the duration requirement. A long single cigarette can span multiple segments and be overcounted. Two quick cigarettes can occupy one segment and be undercounted. Eating or drinking can still resemble smoking, and the opposite hand may provide no useful motion. Duration does not resolve an ambiguous wrist trace; estimates remain reviewable and correctable.

The duration rule also does not change watchOS execution limits. The first estimate needs five minutes of qualifying evidence, plus any additional delay before background recordings become available, watchOS gives Ciggy runtime to analyze them, and the event reaches iPhone. Continuous saved history can be analyzed later even when the live detector reset after a sampling interruption. A five-minute evidence threshold does not promise a five-minute end-to-end update.

Regression coverage should verify no early count, successive counts with fresh evidence, no count from elapsed time alone, interrupted coverage, replay identity, checkpoint restoration and separation of adjacent duration events in the repository. The [physical test guide](motion-testing.md) uses empty-hand gesture exercises. Existing measured replay and synthetic results that predate this rule are historical baselines, not validation of the new estimate's real-world accuracy.
