"""Wren v2 — the context-aware temporal model (sequence TCN).

Reads a log-mel SEQUENCE -> per-frame P(removable filler). Shared framing/mel live one
level up (`..config`, `..features`); publishing is the top-level `publish_hf`.
"""
