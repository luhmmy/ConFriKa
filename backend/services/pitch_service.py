"""Fundamental-frequency (F0) pitch analysis for tonal-language coaching.

Implements real autocorrelation-based pitch tracking over a WAV audio sample and
converts the per-frame F0 track into a semitone contour relative to the speaker's
baseline. This is genuine DSP (NumPy), not a canned response.
"""
from __future__ import annotations

import io
import math
import struct
import wave
from dataclasses import dataclass
from typing import List

import numpy as np

from ..config.settings import settings


@dataclass
class PitchResult:
    mean_f0_hz: float
    median_f0_hz: float
    f0_track_hz: List[float]
    semitone_contour: List[float]
    voiced_ratio: float
    sample_rate: int
    duration_seconds: float


def _read_wav(data: bytes) -> tuple[np.ndarray, int]:
    with wave.open(io.BytesIO(data), "rb") as wav:
        n_channels = wav.getnchannels()
        sampwidth = wav.getsampwidth()
        framerate = wav.getframerate()
        n_frames = wav.getnframes()
        raw = wav.readframes(n_frames)

    if sampwidth == 2:
        samples = np.frombuffer(raw, dtype=np.int16).astype(np.float64) / 32768.0
    elif sampwidth == 1:
        samples = (np.frombuffer(raw, dtype=np.uint8).astype(np.float64) - 128.0) / 128.0
    elif sampwidth == 4:
        samples = np.frombuffer(raw, dtype=np.int32).astype(np.float64) / 2147483648.0
    else:
        raise ValueError("Unsupported WAV sample width; expected 8, 16, or 32-bit PCM.")

    if n_channels > 1:
        samples = samples.reshape(-1, n_channels).mean(axis=1)
    return samples, framerate


def _autocorrelation_f0(frame: np.ndarray, sr: int, fmin: float, fmax: float) -> float:
    frame = frame - np.mean(frame)
    energy = np.sum(frame ** 2)
    if energy < 1e-4:  # silence / unvoiced
        return 0.0

    corr = np.correlate(frame, frame, mode="full")[len(frame) - 1:]
    min_lag = int(sr / fmax)
    max_lag = int(sr / fmin)
    if max_lag >= len(corr):
        max_lag = len(corr) - 1
    if min_lag >= max_lag:
        return 0.0

    segment = corr[min_lag:max_lag]
    peak = int(np.argmax(segment)) + min_lag
    # Require the periodic peak to be reasonably strong vs. the zero-lag energy.
    if corr[peak] < 0.3 * corr[0]:
        return 0.0
    return sr / peak


class PitchService:
    @classmethod
    def analyze_wav(cls, data: bytes, baseline_f0_hz: float = 138.0) -> PitchResult:
        if len(data) > settings.MAX_AUDIO_BYTES:
            raise ValueError("Audio payload exceeds the maximum allowed size.")

        samples, sr = _read_wav(data)
        if samples.size == 0:
            raise ValueError("Empty audio sample.")

        fmin = settings.PITCH_ANALYSIS_MIN_F0
        fmax = settings.PITCH_ANALYSIS_MAX_F0

        frame_len = int(0.04 * sr)  # 40 ms analysis window
        hop = int(0.02 * sr)        # 20 ms hop
        if frame_len <= 0:
            raise ValueError("Audio sample rate too low for pitch analysis.")

        f0_track: List[float] = []
        for start in range(0, max(1, len(samples) - frame_len), hop):
            frame = samples[start:start + frame_len]
            if len(frame) < frame_len:
                break
            f0_track.append(round(_autocorrelation_f0(frame, sr, fmin, fmax), 2))

        voiced = [f for f in f0_track if f > 0]
        if voiced:
            mean_f0 = float(np.mean(voiced))
            median_f0 = float(np.median(voiced))
        else:
            mean_f0 = 0.0
            median_f0 = 0.0

        base = baseline_f0_hz if baseline_f0_hz and baseline_f0_hz > 0 else (mean_f0 or 1.0)
        semitones = [
            round(12.0 * math.log2(f / base), 2) if f > 0 else 0.0 for f in f0_track
        ]

        voiced_ratio = (len(voiced) / len(f0_track)) if f0_track else 0.0
        duration = len(samples) / sr if sr else 0.0

        return PitchResult(
            mean_f0_hz=round(mean_f0, 2),
            median_f0_hz=round(median_f0, 2),
            f0_track_hz=f0_track,
            semitone_contour=semitones,
            voiced_ratio=round(voiced_ratio, 3),
            sample_rate=sr,
            duration_seconds=round(duration, 3),
        )
