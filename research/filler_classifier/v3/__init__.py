"""Wren v3 — scaling the 'don't cut' (negative) class.

v3 is the same WrenSeq architecture as v2; what changes is the DATA. The A/B in
NOTES §6d confirmed 'data over architecture' — training-recipe tweaks were a wash
because the negative class (music/noise/non-speech) was too thin. v3 fixes that:

  • synth_negatives.py — download-free synthetic non-speech negatives (this file's
    sibling), to broaden noise + tonal coverage immediately.
  • (planned) teacher_labels.py — a big pretrained audio tagger auto-labels oceans
    of unlabeled audio → unlimited real negatives, distilled into tiny Wren.

The resulting model ships as the next Wren version (v0.0.11), trained via
`filler_classifier.v2.train --hard-neg <dirs> --spec-augment --focal --cosine`.
"""
