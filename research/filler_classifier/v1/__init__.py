"""Wren v1 — the original per-chunk filler classifier (chunk model, v0.0.x).

Classifies one 0.25 s log-mel chunk -> P(filler). Shared framing/mel live one level
up (`..config`, `..features`); publishing is the top-level `publish_hf`/`promote_model`.
"""
