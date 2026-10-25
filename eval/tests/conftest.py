"""Keep tests away from real private data (ADR 0014).

Every test gets an empty, temporary private folder, "others" folder and private results folder, so no test can read
or overwrite data/private, data/pairs/others or eval/results/private. Tests that check the real repository data opt
out with @pytest.mark.real_data.
"""

import pytest

from arabizi_eval import pairs as P
from arabizi_eval import run


def pytest_configure(config):
    config.addinivalue_line("markers", "real_data: test reads the real data folders (public and private)")


@pytest.fixture(autouse=True)
def isolate_private_data(request, monkeypatch, tmp_path_factory):
    if request.node.get_closest_marker("real_data"):
        return
    sandbox = tmp_path_factory.mktemp("private-sandbox")
    monkeypatch.setattr(P, "PRIVATE_DIR", sandbox / "private" / "pairs")
    monkeypatch.setattr(P, "OTHERS_DIR", sandbox / "others")  # the real others set stays out of unit tests
    monkeypatch.setattr(P, "OTHERS_MANIFEST_PATH", sandbox / "others" / "manifest.json")
    monkeypatch.setattr(run, "PRIVATE_RESULTS_DIR", sandbox / "results-private")
