"""Crisp video-cleaning engine.

Removes silent pauses and filler words from a video, re-rendering a tight cut.
The desktop app drives this through `clean_video.py` (the CLI wrapper next to
this package); library users can import directly:

    from crisp import clean_video, CleanError
"""

from .errors import CleanError
from .pipeline import clean_video

__all__ = ["clean_video", "CleanError"]
