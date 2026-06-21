# FillerBench

A small, native macOS dashboard for evaluating the filler classifier — a **dev
tool**, not part of the shipped Crisp app. It drives `filler_classifier.report`
(Python) and renders the scores in Crisp's design language, so you can judge the
model without running CLI commands.

```sh
cd research/FillerBench
swift run FillerBench
```

In the window:
- pick a **split** (`test` is the honest held-out set; `validation` is smaller/faster),
- tick **Quick** for a capped run while iterating, then hit **Run**,
- drag the **decision threshold** to watch precision/recall trade off live.

It shows precision · recall · F1 at the chosen threshold, inference speed
(×real-time), what the model wrongly cuts (false positives by sound), and
per-filler recall.

The **Research dir** field must point at the `research/` folder that contains the
`.venv/` (training env) and `data/PodcastFillers/`. It defaults to
`$CRISP_RESEARCH_DIR`, else `<cwd>/research` if present, else the working
directory — edit the field if your checkout is elsewhere.

> Scoring on the full `test` split runs the model over ~9.5k clips (a minute or
> two). Use **Quick** for fast feedback.

## Next

- **Run on my own data** mode: drop in a video → predictions + a label-a-window
  flow that computes precision/recall on your footage (graphical `validate`).
