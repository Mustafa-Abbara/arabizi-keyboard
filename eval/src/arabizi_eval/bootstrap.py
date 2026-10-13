"""Paired bootstrap confidence intervals over sentences (roadmap P3).

Word accuracy is a ratio of sums (correct words / total words), so each resample recomputes that ratio
on the resampled sentences rather than averaging per-sentence accuracies.
"""

from __future__ import annotations

import numpy as np

DEFAULT_RESAMPLES = 10_000


def _resample_ratios(correct: np.ndarray, total: np.ndarray, index: np.ndarray) -> np.ndarray:
    return correct[index].sum(axis=1) / np.maximum(total[index].sum(axis=1), 1)


def ratio_ci(correct: list[float], total: list[float], resamples: int = DEFAULT_RESAMPLES,
             seed: int = 0, level: float = 0.95) -> tuple[float, float, float]:
    """(estimate, low, high) for sum(correct) / sum(total)."""
    c, t = np.asarray(correct, dtype=float), np.asarray(total, dtype=float)
    if len(c) == 0:
        raise ValueError("no sentences to resample")
    index = np.random.default_rng(seed).integers(0, len(c), size=(resamples, len(c)))
    ratios = _resample_ratios(c, t, index)
    tail = (1 - level) / 2 * 100
    low, high = np.percentile(ratios, [tail, 100 - tail])
    return float(c.sum() / max(t.sum(), 1)), float(low), float(high)


def paired_difference_ci(a: tuple[list[float], list[float]], b: tuple[list[float], list[float]],
                         resamples: int = DEFAULT_RESAMPLES, seed: int = 0,
                         level: float = 0.95) -> tuple[float, float, float]:
    """(A - B, low, high): both systems are scored on the same resampled sentences."""
    (ca, ta), (cb, tb) = (np.asarray(x, dtype=float) for x in a), (np.asarray(x, dtype=float) for x in b)
    if not len(ca) == len(ta) == len(cb) == len(tb) or len(ca) == 0:
        raise ValueError("both systems need scores for the same, non-empty list of sentences")
    index = np.random.default_rng(seed).integers(0, len(ca), size=(resamples, len(ca)))
    diffs = _resample_ratios(ca, ta, index) - _resample_ratios(cb, tb, index)
    tail = (1 - level) / 2 * 100
    low, high = np.percentile(diffs, [tail, 100 - tail])
    estimate = ca.sum() / max(ta.sum(), 1) - cb.sum() / max(tb.sum(), 1)
    return float(estimate), float(low), float(high)
