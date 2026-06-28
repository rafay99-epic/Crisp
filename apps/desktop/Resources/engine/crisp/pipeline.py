"""The public engine entry point — orchestrates detect → edit into a clean video."""

import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from .config import (
    DEFAULT_AUDIO_BITRATE, DEFAULT_AUDIO_CODEC, DEFAULT_BACKUP, DEFAULT_CONTAINER, DEFAULT_CROSSFADE_MS,
    DEFAULT_EXPORT_TIMELINE, DEFAULT_FADE_MS, DEFAULT_FPS, DEFAULT_FPS_MODE, DEFAULT_HARDWARE,
    DEFAULT_KEEP_PAUSE, DEFAULT_MAX_PAUSE, DEFAULT_MODEL, DEFAULT_NOISE_DB, DEFAULT_QUALITY,
    DEFAULT_REMOVE_RETAKES, DEFAULT_RETAKE_SENSITIVITY, DEFAULT_SNAP_MS, DEFAULT_VIDEO_CODEC,
    MIN_KEEP, RETAKE_ANCHOR_PAUSE, RETAKE_SENSITIVITY,
)
from .detect import detect_silences, extract_audio, filler_words, filter_silences, transcribe
from .edit import (_output_owner, build_keep_segments, gate_fillers_by_silence, make_backup,
                   output_duration, render, snap_keep_to_zero_crossings, tag_output_source,
                   unique_output_path)
from .encode import (
    audio_args, container_args, default_output_path, resolve_codecs, resolve_container, video_args,
)
from .enginelog import EngineLogger
from .errors import CleanError
from .framerate import resolve_target_fps
from .timeline import build_fcpxml, project_paths, timeline_seconds
from .tools import (
    ffmpeg_bin, ffprobe_duration, probe_stream_meta, probe_video_fps, which_filler, which_whisper,
)


def _noop(*_a, **_k):
    pass


def _export_editor_project(src, keep, out_dir, project_dir, target_fps,
                           video_codec, hardware, quality, audio_codec, audio_bitrate,
                           on_log, logger):
    """Model-A editor handoff: drop a copy of the ORIGINAL plus a non-destructive
    FCPXML timeline into a project folder, so an editor (DaVinci Resolve) can open the
    already-cut footage and still adjust every cut. Returns (fcpxml_path, project_dir,
    media_copy_path, timeline_seconds) — timeline_seconds is the frame-snapped kept
    length so reported stats match the actual timeline. The original is never touched.

    A CFR source in an editor-friendly container is copied byte-for-byte (zero
    re-encode — the whole point). A source that needs normalization (VFR / an explicit
    constant rate) or sits in a poor editor container (.avi/.flv/no extension) is
    re-encoded once to CFR .mov, because FCPXML can't represent variable timing and
    editors choke on those containers."""
    pdir, media_copy, fcpxml_path = project_paths(src, project_dir or out_dir)

    # An unmuxable / extension-less source becomes a .mov copy (and forces a re-encode);
    # a byte copy keeping e.g. an .avi extension imports poorly into editors.
    EDITOR_CONTAINERS = {"mov", "mp4", "m4v", "mkv", "webm"}
    force_encode = src.suffix.lower().lstrip(".") not in EDITOR_CONTAINERS
    if force_encode:
        media_copy = media_copy.with_suffix(".mov")

    # Don't clobber a DIFFERENT source's project that happens to share a stem (mirrors
    # the render path's unique_output_path + source xattr). Re-exporting the SAME source
    # reuses — and overwrites — its own project folder.
    marker = os.fsencode(str(src))
    base = pdir.name
    i = 0
    while True:
        cand = pdir if i == 0 else pdir.with_name(f"{base} {i}")
        cand_media, cand_fcp = cand / media_copy.name, cand / fcpxml_path.name
        if not cand.exists() or _output_owner(cand_media) == marker:
            pdir, media_copy, fcpxml_path = cand, cand_media, cand_fcp
            break
        i += 1

    # Whether THIS run creates the folder — so cleanup-on-failure never deletes a
    # prior good export when we're re-exporting into (reusing) the same folder.
    created = not pdir.exists()
    try:
        pdir.mkdir(parents=True, exist_ok=True)
    except OSError as e:
        raise CleanError(f"Couldn't create the editor project folder \"{pdir}\".\n{e}") from e

    # Write to temp files and atomically swap them in only once BOTH are ready — so a
    # failed re-export can never corrupt an existing project (the live media/.fcpxml are
    # untouched until the final publish), and a partial run leaves only temp files. The
    # temp marker goes BEFORE the suffix (talk.crisp-tmp.mov) so ffmpeg still infers the
    # output muxer from the real extension on the re-encode path.
    media_tmp = media_copy.with_name(f"{media_copy.stem}.crisp-tmp{media_copy.suffix}")
    fcpxml_tmp = fcpxml_path.with_name(f"{fcpxml_path.stem}.crisp-tmp{fcpxml_path.suffix}")
    try:
        if target_fps or force_encode:
            on_log(f"Making an editor-ready copy at {target_fps} fps…" if target_fps
                   else "Converting your footage to an editor-friendly format…")

            def _normalize(hw):
                fps_args = ["-r", str(target_fps)] if target_fps else []
                cmd = [ffmpeg_bin(), "-y", "-i", str(src),
                       *video_args(video_codec, hw, quality), *fps_args,
                       *audio_args(audio_codec, audio_bitrate), str(media_tmp)]
                logger.command(f"ffmpeg editor-copy ({'hw' if hw else 'sw'})", cmd)
                r = subprocess.run(cmd, capture_output=True, text=True)
                logger.tool_result("ffmpeg editor-copy", r.returncode, r.stderr)
                return r

            res = _normalize(hardware)
            if (res.returncode != 0 or not media_tmp.exists()) and hardware:
                # Hardware encoding can be unavailable (e.g. a VM with no media engine);
                # fall back to software so the handoff still works — mirrors render().
                logger.notice("Hardware encode failed for the editor copy — retrying in software")
                on_log("Hardware encoding failed — falling back to software encoding…")
                res = _normalize(False)
            if res.returncode != 0 or not media_tmp.exists():
                raise CleanError(f"Couldn't prepare the editor copy.\n{res.stderr[-1000:]}")
        else:
            # CFR, editor-friendly container: a plain copy — no re-encode, no loss, fast.
            on_log("Copying your footage for the editor…")
            shutil.copy2(src, media_tmp)

        meta = probe_stream_meta(media_tmp, logger=logger)
        dur = ffprobe_duration(media_tmp, logger=logger)
        if dur <= 0:
            # ffprobe_duration returns 0.0 on failure; build_fcpxml would turn that into
            # a 1-frame asset. Fail loudly instead of emitting a bogus timeline.
            raise CleanError("Couldn't read the editor copy's duration.")
        xml = build_fcpxml(
            media_uri=media_copy.resolve().as_uri(), name=Path(src).stem,
            num=meta["fps_num"], den=meta["fps_den"], width=meta["width"], height=meta["height"],
            audio_rate=meta["audio_rate"], audio_channels=meta["audio_channels"],
            has_audio=meta["audio_channels"] > 0, duration=dur, keep=keep)
        fcpxml_tmp.write_text(xml, encoding="utf-8")
        # Publish both as a unit (stage old aside, replace both, roll back on failure) so
        # a re-export never leaves a mixed media/timeline project.
        _publish_atomic(media_tmp, media_copy, fcpxml_tmp, fcpxml_path)
    except (OSError, CleanError) as e:
        _cleanup_temp_project(media_tmp, fcpxml_tmp, pdir, created)
        if isinstance(e, CleanError):
            raise
        raise CleanError(f"Couldn't write the editor project.\n{e}") from e

    # Tag the media copy with its source so a later re-export reuses this folder and a
    # different same-stem source dedups instead of clobbering it.
    tag_output_source(media_copy, src)
    logger.info(f"editor project: {pdir} (fcpxml={fcpxml_path.name}, media={media_copy.name})")
    snapped = timeline_seconds(keep, meta["fps_num"], meta["fps_den"])
    return fcpxml_path, pdir, media_copy, snapped


def _publish_atomic(media_tmp, media_dst, fcpxml_tmp, fcpxml_dst):
    """Swap both temp files into place so the project updates together or not at all.
    Stages any existing live files aside, replaces both, and on failure restores them —
    so a re-export can't leave a half-updated (mixed media + timeline) project. The
    leftover temp files are removed by the caller's cleanup."""
    media_bak = media_dst.with_name(media_dst.name + ".crisp-bak") if media_dst.exists() else None
    fcpxml_bak = fcpxml_dst.with_name(fcpxml_dst.name + ".crisp-bak") if fcpxml_dst.exists() else None
    if media_bak:
        os.replace(media_dst, media_bak)
    if fcpxml_bak:
        os.replace(fcpxml_dst, fcpxml_bak)
    try:
        os.replace(media_tmp, media_dst)
        os.replace(fcpxml_tmp, fcpxml_dst)
    except OSError:
        # Roll back to the previous good versions (or remove a half-published new file).
        if media_bak and media_bak.exists():
            os.replace(media_bak, media_dst)
        elif media_dst.exists():
            media_dst.unlink()
        if fcpxml_bak and fcpxml_bak.exists():
            os.replace(fcpxml_bak, fcpxml_dst)
        raise
    for bak in (media_bak, fcpxml_bak):       # success → drop the staged old copies
        if bak and bak.exists():
            try:
                bak.unlink()
            except OSError:
                pass


def _cleanup_temp_project(media_tmp, fcpxml_tmp, pdir, created):
    """Remove the temp files from a failed export (the live media/.fcpxml were never
    touched). Only removes the project dir if THIS run created it and it's now empty —
    a reused folder (re-export) and its prior good export are always left intact."""
    for p in (media_tmp, fcpxml_tmp):
        try:
            if p.exists():
                p.unlink()
        except OSError:
            pass
    if not created:
        return
    try:
        if pdir.exists() and not any(pdir.iterdir()):
            pdir.rmdir()
    except OSError:
        pass


# Analyze-only captures every candidate gap down to this floor; the app applies the
# real (larger) pause threshold itself, so changing it needs no re-analysis.
ANALYZE_MIN_PAUSE = 0.05


def analyze(src, noise=DEFAULT_NOISE_DB, buckets=240, on_log=None, logger=None):
    """Analyze-only: extract audio, find candidate silences at `noise`, and summarize
    the waveform — no transcription, no render. Returns {duration, peaks, silences}.
    The desktop app drives this for the live cut preview and recomputes the cut
    regions itself as the user drags the knobs."""
    on_log = on_log or _noop
    logger = logger or EngineLogger(None)

    src = Path(src).expanduser().resolve()
    if not src.exists():
        raise CleanError(f"File not found: {src}")

    logger.info(f"analyze src={src} noise={noise} buckets={buckets}")
    duration = ffprobe_duration(src, logger=logger)
    if duration <= 0:
        raise CleanError("Could not read the video's duration — is it a valid video file?")

    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "audio.wav"
        extract_audio(src, wav, on_log, logger=logger)
        silences = detect_silences(wav, noise, ANALYZE_MIN_PAUSE, on_log, logger=logger)
        from .waveform import waveform_summary
        peaks = waveform_summary(wav, duration, [(0.0, duration)], buckets)["peaks"]

    return {"duration": duration, "peaks": peaks,
            "silences": [[s, e] for s, e in silences]}


def clean_video(src, out_path=None, model=None, pause=DEFAULT_MAX_PAUSE,
                noise=DEFAULT_NOISE_DB, keep_pause=DEFAULT_KEEP_PAUSE, min_keep=MIN_KEEP,
                video_codec=DEFAULT_VIDEO_CODEC, hardware=DEFAULT_HARDWARE, quality=DEFAULT_QUALITY,
                audio_codec=DEFAULT_AUDIO_CODEC, audio_bitrate=DEFAULT_AUDIO_BITRATE,
                container=DEFAULT_CONTAINER, remove_fillers=True,
                remove_retakes=DEFAULT_REMOVE_RETAKES, backup=DEFAULT_BACKUP,
                backup_dir=None, out_dir=None, split_tracks=False, split_audio="match",
                waveform_buckets=0, keep_file=None, captions="none",
                filler_backend="whisper", filler_model=None,
                fade_ms=DEFAULT_FADE_MS, crossfade_ms=DEFAULT_CROSSFADE_MS, snap_ms=DEFAULT_SNAP_MS,
                retake_sensitivity=DEFAULT_RETAKE_SENSITIVITY,
                fps_mode=DEFAULT_FPS_MODE, fps=DEFAULT_FPS,
                export_timeline=DEFAULT_EXPORT_TIMELINE, project_dir=None,
                on_log=None, on_progress=None, logger=None):
    """
    Clean one video. Returns a dict with results.
      on_log(str)            — called with human-readable status lines.
      on_progress(frac, str) — called with 0.0..1.0 overall progress + label.
      logger                 — optional EngineLogger for detailed file logging
                               (commands, tool stderr); defaults to a no-op.
    """
    on_log = on_log or _noop
    on_progress = on_progress or _noop
    logger = logger or EngineLogger(None)

    src = Path(src).expanduser().resolve()
    if not src.exists():
        raise CleanError(f"File not found: {src}")

    model = Path(model).expanduser().resolve() if model else DEFAULT_MODEL
    # An explicit --out path is the caller's exact choice (overwrite it). A derived
    # path (the default <name>_cleaned.<ext>) is de-duped + tagged below so we never
    # clobber a *different* video's cleaned file.
    explicit_out = bool(out_path)
    if out_path:
        # An explicit output path wins; its extension picks the container.
        out_path = Path(out_path).expanduser().resolve()
        container = out_path.suffix.lower().lstrip(".") or "mp4"
    else:
        # Otherwise: the chosen container, or "auto" = match the input's. The
        # cleaned file lands in out_dir if one was chosen (e.g. a NAS), else beside
        # the source.
        container = resolve_container(container, src.suffix)
        out_path = default_output_path(src, container, out_dir).resolve()
        if out_dir:
            try:
                out_path.parent.mkdir(parents=True, exist_ok=True)
            except OSError as e:
                raise CleanError(f"Couldn't use the output folder \"{out_path.parent}\". "
                                 f"Is the drive connected and writable?\n{e}")
        # Don't clobber a DIFFERENT source's cleaned file (same name, different video).
        # Re-cleaning the SAME source overwrites its own output (matched by the source
        # xattr); a different source — or a pre-existing file we didn't make — gets
        # _1, _2…; where xattrs aren't supported we fall back to plain dedup. Applies
        # whether the file lands beside the source or in a chosen folder.
        out_path = unique_output_path(out_path, src)

    # The container dictates which codecs are legal (e.g. WebM forces VP9 + Opus);
    # coerce now and tell the user about any swap rather than letting ffmpeg fail.
    video_codec, audio_codec, hardware, codec_notes = resolve_codecs(
        container, video_codec, audio_codec, hardware)

    logger.info(f"src={src}")
    logger.info(f"out={out_path} container={container} video={video_codec} "
                f"audio={audio_codec} hw={hardware} quality={quality} "
                f"remove_fillers={remove_fillers} remove_retakes={remove_retakes} "
                f"retake_sensitivity={retake_sensitivity} "
                f"captions={captions} keep_file={bool(keep_file)} backup={backup}")

    # Captions also need the transcript (and the speech model), so we transcribe
    # whenever fillers are removed OR captions are requested. But an explicit reviewed
    # keep-list (the app's edit-timeline output) bypasses detection entirely — no audio
    # analysis, transcription, or model — so we render exactly the approved segments.
    # An editor handoff writes no captions (there's no rendered deliverable to attach
    # them to), so drop a caption request up front — before it would pull transcription
    # work that produces nothing. Fillers/retakes still transcribe as needed.
    if export_timeline == "fcpxml" and captions != "none":
        on_log("Captions aren't written for an editor handoff — add them in your editor.")
        captions = "none"
    want_captions = captions != "none"
    # Retake detection needs a real transcript, which the Core ML classifier can't
    # produce. Rather than silently switch a classifier run onto whisper, the engine
    # owns the invariant: retakes are skipped whenever the classifier is the backend.
    # (The app disables the toggle in that case; the CLI just gets pauses+fillers.)
    do_retakes = remove_retakes and filler_backend != "coreml"
    need_transcript = (remove_fillers or want_captions or do_retakes) and not keep_file
    # Captions still need whisper to transcribe, so the classifier only applies when
    # captions are off (retakes no longer force whisper — they're skipped above).
    use_classifier = need_transcript and filler_backend == "coreml" and not want_captions
    whisper_bin = None
    if need_transcript and not use_classifier:
        if not model.exists():
            raise CleanError(f"Speech model not found: {model}\nRun setup.sh to download it.")
        whisper_bin = which_whisper()
        logger.info(f"model={model} whisper={whisper_bin}")

    # Overall progress is split across stages so the bar moves sensibly.
    def stage(lo, hi):
        return lambda f, label="": on_progress(lo + (hi - lo) * f, label)

    on_log(f"=== Cleaning: {src.name} ===")
    for note in codec_notes:
        on_log(note)
    on_progress(0.0, "Starting…")

    # Editor-handoff copies the original into the project folder, so a separate backup
    # would duplicate a (possibly large) file twice — skip it in that mode.
    do_backup = backup and export_timeline != "fcpxml"
    backup_path = make_backup(src, on_log, backup_dir, logger=logger) if do_backup else None
    if backup_path:
        on_progress(0.03, "Backed up original")

    duration = ffprobe_duration(src, logger=logger)
    if duration <= 0:
        raise CleanError("Could not read the video's duration — is it a valid video file?")
    logger.info(f"duration={duration:.2f}s")

    # Frame-rate normalization. Screen recorders emit variable-frame-rate video,
    # which the trim→concat render can drift A/V on; force the render to a constant
    # rate when needed. Probed once here so it covers both the detection and the
    # reviewed keep-file render paths below. Falls through to "no change" on any
    # probe failure (unknown rates are never normalized), so a clean is never broken.
    target_fps = None
    if fps_mode != "passthrough":
        r_text, avg_text = probe_video_fps(src, logger=logger)
        target_fps = resolve_target_fps(fps_mode, fps, r_text, avg_text)
        # Constant mode must honor its contract: if no usable rate resolved (e.g. a
        # zero/invalid --fps), fail loudly instead of silently rendering source timing.
        if fps_mode == "constant" and target_fps is None:
            raise CleanError("Constant frame rate mode needs a valid --fps value (e.g. 30 or 60).")
        logger.info(f"fps mode={fps_mode} requested={fps} r={r_text!r} avg={avg_text!r} "
                    f"-> target={target_fps!r}")
        if target_fps:
            on_log(f"Constant frame rate: normalizing to {target_fps} fps."
                   if fps_mode == "constant"
                   else f"Variable frame rate detected — normalizing to {target_fps} fps "
                        f"so audio and video stay in sync.")

    # The waveform (peaks + cut mask) is built from the analysis WAV; the reviewed
    # keep-list path skips analysis, so it has no waveform (the done row falls back to
    # the simpler reduction bar).
    wave_summary = {"peaks": [], "removed": []}
    # Spoken words for caption re-timing — stays empty in keep-file mode (no transcript).
    words = []

    if keep_file:
        from .edit import load_keep_segments
        keep = load_keep_segments(keep_file, duration)
        # The user decided the cuts; report how many removed gaps the keep-list implies
        # (a leading/trailing trim and each interior gap), so the summary still reads.
        cuts = sum(1 for i in range(len(keep) - 1) if keep[i + 1][0] - keep[i][1] > 0.01)
        if keep[0][0] > 0.01:
            cuts += 1
        if keep[-1][1] < duration - 0.01:
            cuts += 1
        stats = {"fillers": 0, "pauses": cuts, "retakes": 0}
        on_log(f"Using {len(keep)} reviewed segment(s).")
        on_progress(0.58, "Rendering reviewed cuts…")
    else:
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            wav = tmp / "audio.wav"

            # Labels describe the CURRENT step (emitted before it) so the UI says what's
            # happening now, not what just finished.
            on_progress(0.05, "Reading audio…")
            extract_audio(src, wav, on_log, logger=logger)

            on_progress(0.10, "Detecting pauses…")
            # One silencedetect pass. Retake anchoring needs a shorter pause than the
            # cut threshold (a redo pause is brief), so when retakes are on we scan at
            # the lower of the two and derive the cut set by filtering on duration:
            # silencedetect's `d=` only gates which silences are *reported*, not their
            # boundaries, so the filtered set is identical to a direct scan at `pause`
            # (verified on real audio). Avoids a second full ffmpeg pass on long videos.
            anchor_silences = []
            if do_retakes:
                # One scan at the shorter threshold serves both sets (see filter_silences).
                found = detect_silences(wav, noise, min(pause, RETAKE_ANCHOR_PAUSE),
                                        on_log, logger=logger)
                silences = filter_silences(found, pause)
                anchor_silences = filter_silences(found, RETAKE_ANCHOR_PAUSE)
                logger.debug(f"from {len(found)} pauses: {len(silences)} cut "
                             f"(≥{pause}s) + {len(anchor_silences)} retake-anchor "
                             f"(≥{RETAKE_ANCHOR_PAUSE}s)")
            else:
                silences = detect_silences(wav, noise, pause, on_log, logger=logger)

            if need_transcript:
                if use_classifier:
                    # The fast model reports only when done, so name the step up front.
                    on_progress(0.16, "Finding filler words…")
                    words = filler_words(which_filler(), filler_model, wav,
                                         on_log, stage(0.16, 0.58), logger=logger)
                    # Keep only fillers at a pause or clearly long — don't cut
                    # brief hesitations embedded mid-sentence (rough, removes flow).
                    before = len(words)
                    words = gate_fillers_by_silence(words, silences)
                    logger.debug(f"silence-gate: kept {len(words)}/{before} fillers")
                else:
                    words = transcribe(whisper_bin, model, wav, tmp / "transcript",
                                       on_log, stage(0.15, 0.58), logger=logger)
                on_log(f"Found {len(words)} spoken words.")

            # Only cut filler words when the user asked to; if we transcribed purely
            # for captions, every word stays in the cut plan (fillers are still
            # excluded from the caption text below).
            cut_words = words if remove_fillers else []
            # Retakes need the real transcript; `do_retakes` is already false for the
            # classifier backend (which produces no transcript), so this only runs when
            # whisper supplied `words`.
            retakes = []
            if do_retakes and words:
                # Its own visible step (after "Detecting pauses" / "Transcribing"), so
                # the UI shows that repeated-take detection is happening. Held at the
                # transcription ceiling (0.58) so the bar never moves backward.
                on_log("Finding repeated takes...")
                on_progress(0.58, "Finding repeated takes…")
                from .retake import detect_retakes
                from .semantic import make_judge
                # Each sensitivity is a full policy: how many matched words count as a
                # redo (`min_run`), whether the corrected take must follow a pause
                # (`require_pause` — aggressive drops it to catch mid-sentence
                # restarts), and the semantic-similarity bar (`sem_min`). The semantic
                # judge (crisp-embed) is what lets aggressive safely skip the pause
                # anchor; it's None when the helper is unavailable, in which case
                # detect_retakes keeps the anchor on regardless.
                policy = RETAKE_SENSITIVITY.get(retake_sensitivity,
                                                RETAKE_SENSITIVITY[DEFAULT_RETAKE_SENSITIVITY])
                # Retake removal must never break a clean: any unexpected failure here
                # degrades to "no retakes" (the rest of the clean — pauses, render —
                # proceeds) rather than aborting and losing the user's run.
                try:
                    # Only presets with a pause-less path (balanced/aggressive) can use
                    # the semantic gate; gentle is pause-required, so skip the helper
                    # there entirely — no wasted probe, and the gate can never relax
                    # gentle's pause rule (defense-in-depth on top of detect_retakes).
                    judge = (make_judge(logger)
                             if policy["min_run_no_pause"] is not None else None)
                    logger.debug(f"retake detection: sensitivity={retake_sensitivity} "
                                 f"min_run={policy['min_run']} require_pause={policy['require_pause']} "
                                 f"min_run_no_pause={policy['min_run_no_pause']} "
                                 f"sem_min={policy['sem_min']} "
                                 f"semantic_gate={'on' if judge else 'off'} "
                                 f"anchor_pauses={len(anchor_silences)}")
                    retakes = detect_retakes(
                        words, min_run=policy["min_run"],
                        require_pause=policy["require_pause"],
                        min_run_no_pause=policy["min_run_no_pause"], sem_min=policy["sem_min"],
                        silences=anchor_silences, judge=judge, logger=logger)
                    logger.debug(f"retake detection found {len(retakes)} repeated take(s)")
                except Exception:                              # noqa: BLE001 — degrade, never abort
                    # Full traceback (not just repr) so the exact failing call is
                    # debuggable; retakes degrade to none, the clean still completes.
                    logger.exception("retake detection failed — skipping retakes for this clean")
                    retakes = []
            on_progress(0.59, "Planning cuts…")
            keep, stats = build_keep_segments(cut_words, silences, duration, keep_pause,
                                              min_keep, retakes=retakes)
            if not keep:
                raise CleanError("Everything looked like silence — nothing to keep. "
                                 "Try a larger pause value.")

            # Phase 3: nudge cut boundaries onto zero-crossings while the analysis WAV
            # still exists, so the splices land where the waveform is already ~0.
            if snap_ms > 0:
                keep = snap_keep_to_zero_crossings(keep, wav, snap_ms / 1000.0, logger=logger)

            # Build the UI waveform now, while the analysis WAV still exists (it's
            # deleted when this temp dir closes). Opt-in via waveform_buckets so the
            # bare CLI / watcher don't pay for data nothing renders.
            if waveform_buckets > 0:
                from .waveform import waveform_summary
                wave_summary = waveform_summary(wav, duration, keep, waveform_buckets)

    # Effective output length: a crossfade overlaps each join, so the reported
    # new/saved seconds match the file render() actually writes (not the raw sum).
    kept_dur = output_duration(keep, crossfade_ms / 1000.0)
    logger.info(f"keep {len(keep)} segments, kept {kept_dur:.2f}s, "
                f"fillers={stats['fillers']} pauses={stats['pauses']} retakes={stats['retakes']}")
    retake_note = f", {stats['retakes']} repeated takes" if stats["retakes"] else ""
    on_log(f"Removing {stats['fillers']} filler words and {stats['pauses']} pauses{retake_note}.")

    # Editor handoff (Model A): write a non-destructive editor project and STOP — no
    # render, no encode (that's the whole point: the editor finishes the cut). Branches
    # out here before the render, so backup/captions/split don't run either.
    if export_timeline == "fcpxml":
        on_progress(0.62, "Saving your timeline…")
        # The editor copy keeps the SOURCE's container (and name), not the chosen output
        # container — so re-resolve codecs against the source. Otherwise a WebM output
        # setting (which forces VP9) would try to write VP9 into an .mp4/.mov copy.
        src_container = resolve_container("auto", src.suffix)
        ev_codec, ea_codec, ev_hw, _ = resolve_codecs(src_container, video_codec, audio_codec, hardware)
        fcpxml_path, pdir, media_copy, kept_secs = _export_editor_project(
            src, keep, out_dir, project_dir, target_fps,
            ev_codec, ev_hw, quality, ea_codec, audio_bitrate, on_log, logger)
        # kept_secs is frame-snapped (matches the actual timeline), so the status line
        # and the returned stats agree.
        on_log(f"{duration:.0f}s  →  {kept_secs:.0f}s  (saved {duration - kept_secs:.0f}s)")
        on_progress(1.0, "Done")
        on_log(f"✅ Your cuts are ready to open in a video editor — {pdir.name}")
        return {
            "input": str(src),
            "output": str(fcpxml_path),
            "project_dir": str(pdir),
            "media_output": str(media_copy),
            "export_timeline": "fcpxml",
            "backup": str(backup_path) if backup_path else "",
            "orig_seconds": duration,
            "new_seconds": kept_secs,
            "saved_seconds": duration - kept_secs,
            "fillers": stats["fillers"],
            "pauses": stats["pauses"],
            "retakes": stats["retakes"],
            "peaks": wave_summary["peaks"],
            "removed": wave_summary["removed"],
            "video_output": "",
            "audio_output": "",
            "srt_output": "",
            "vtt_output": "",
        }

    on_log(f"{duration:.0f}s  →  {kept_dur:.0f}s  (saved {duration - kept_dur:.0f}s)")
    audio = audio_args(audio_codec, audio_bitrate)
    mux = container_args(container)
    fade_s, crossfade_s = fade_ms / 1000.0, crossfade_ms / 1000.0
    try:
        render(src, keep, out_path, on_log, stage(0.60, 1.0),
               video_args(video_codec, hardware, quality), audio, mux,
               fade=fade_s, crossfade=crossfade_s, fps=target_fps, logger=logger)
    except CleanError:
        if not hardware:
            raise
        # Hardware encoding can be unavailable in odd setups (e.g. a macOS VM
        # with no media engine). Fall back to software so a clean never fails.
        logger.notice("Hardware encoding failed — retrying in software")
        on_log("Hardware encoding failed — falling back to software encoding…")
        render(src, keep, out_path, on_log, stage(0.60, 1.0),
               video_args(video_codec, False, quality), audio, mux,
               fade=fade_s, crossfade=crossfade_s, fps=target_fps, logger=logger)

    if not explicit_out:
        # Tag the derived output so a later re-clean of this same source overwrites it,
        # while a different same-named source (or a file we didn't make) gets its own
        # _N copy. Applies beside the source and in a chosen folder alike.
        tag_output_source(out_path, src)

    # Optionally demux the cleaned file into separate video-only / audio-only stems
    # (stream copy, fast) for editors that animate the picture over the voiceover.
    video_out, audio_out = "", ""
    if split_tracks:
        from .split import split_av
        video_out, audio_out = split_av(out_path, audio_codec, on_log,
                                        audio_format=split_audio, logger=logger)

    # Subtitle sidecars (SRT/VTT), re-timed onto the cleaned timeline. Best-effort —
    # a caption write never fails the clean (the video is the deliverable).
    srt_out, vtt_out = "", ""
    if want_captions:
        # Best-effort: the cleaned video is the deliverable and is already written by
        # now, so a caption failure (re-timing edge case, encoding, disk) must never
        # turn a successful clean into a failed one — log it and move on.
        try:
            from .captions import write_captions
            srt_out, vtt_out = write_captions(out_path, words, keep, captions)
            for path in (srt_out, vtt_out):
                if path:
                    on_log(f"Wrote captions: {Path(path).name}")
        except Exception:
            logger.exception("Caption export failed (continuing without captions)")

    on_progress(1.0, "Done")
    on_log(f"✅ Done! Cleaned video: {out_path}")
    return {
        "input": str(src),
        "output": str(out_path),
        "backup": str(backup_path) if backup_path else "",
        "orig_seconds": duration,
        "new_seconds": kept_dur,
        "saved_seconds": duration - kept_dur,
        "fillers": stats["fillers"],
        "pauses": stats["pauses"],
        "retakes": stats["retakes"],
        "peaks": wave_summary["peaks"],
        "removed": wave_summary["removed"],
        "video_output": video_out,
        "audio_output": audio_out,
        "srt_output": srt_out,
        "vtt_output": vtt_out,
        "export_timeline": "none",
        "project_dir": "",
        "media_output": "",
    }
