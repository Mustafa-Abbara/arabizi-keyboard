"""Paired bootstrap on synthetic data with known answers (roadmap P3 gate)."""

import numpy as np
import pytest

from arabizi_eval import bootstrap as B


def test_ratio_ci_contains_the_true_value_and_is_narrow_for_many_sentences():
    rng = np.random.default_rng(1)
    totals = rng.integers(5, 15, size=400)
    correct = rng.binomial(totals, 0.8)
    estimate, low, high = B.ratio_ci(correct, totals, resamples=4000)
    assert low <= 0.8 <= high and low <= estimate <= high
    assert high - low < 0.04


def test_identical_systems_have_a_difference_ci_around_zero():
    totals = [10] * 200
    correct = [8] * 100 + [6] * 100
    diff, low, high = B.paired_difference_ci((correct, totals), (correct, totals), resamples=2000)
    assert diff == 0 and low == 0 and high == 0


def test_a_clearly_better_system_has_a_ci_above_zero():
    rng = np.random.default_rng(2)
    totals = rng.integers(5, 15, size=300)
    a = rng.binomial(totals, 0.85)
    b = rng.binomial(totals, 0.70)
    diff, low, high = B.paired_difference_ci((a, totals), (b, totals), resamples=4000)
    assert 0 < low <= diff <= high
    assert low <= 0.15 <= high


def test_same_seed_same_interval():
    totals, correct = [10] * 50, [n % 10 for n in range(50)]
    assert B.ratio_ci(correct, totals, seed=3) == B.ratio_ci(correct, totals, seed=3)


def test_mismatched_inputs_are_rejected():
    with pytest.raises(ValueError):
        B.paired_difference_ci(([1, 2], [2, 2]), ([1], [2]))
    with pytest.raises(ValueError):
        B.ratio_ci([], [])
