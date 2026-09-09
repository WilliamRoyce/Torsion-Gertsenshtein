"""Tests for ``tidal/cli/_measure_plot.py`` — ``tidal measure --plot`` panels.

Rescued from ``tests/test_cli_plot.py`` when ``tidal plot`` was retired (#533).
``measure`` is *not* retired here: §5.1's ``drop`` verdict says it is not ported
into the new package, while §7's retire column schedules the code at M5 with
``cli/_simulate.py`` and ``tidal/measurement/``.  This was the only coverage of
``_measure_plot.py`` anywhere, so it had to outlive the file it lived in.
"""

from __future__ import annotations

from typing import Any


class TestMeasurePlotEmptyPanels:
    """Verify that panels with error sentinels are hidden rather than showing
    empty 'No X data' text.
    """

    def _make_ax(self) -> Any:  # noqa: ANN401
        import matplotlib.pyplot as plt

        _, ax = plt.subplots()
        return ax

    def test_spectrum_panel_hidden_on_error(self) -> None:
        from tidal.cli._measure_plot import _plot_spectrum

        ax = self._make_ax()
        results: dict[str, Any] = {
            "spectrum": {"error": "position-dependent term detected"},
        }
        _plot_spectrum(ax, results)
        assert not ax.get_visible()

    def test_spectrum_panel_hidden_when_missing(self) -> None:
        from tidal.cli._measure_plot import _plot_spectrum

        ax = self._make_ax()
        _plot_spectrum(ax, {})
        assert not ax.get_visible()

    def test_dispersion_panel_hidden_on_error(self) -> None:
        from tidal.cli._measure_plot import _plot_dispersion

        ax = self._make_ax()
        results: dict[str, Any] = {
            "dispersion": {"error": "requires spatially uniform system"},
        }
        _plot_dispersion(ax, results)
        assert not ax.get_visible()

    def test_spectrum_panel_visible_with_valid_data(self) -> None:
        """When data is present and correct, the panel should be visible."""
        import numpy as np

        from tidal.cli._measure_plot import _plot_spectrum

        ax = self._make_ax()
        wn = np.linspace(0.0, 1.0, 5)
        power = np.ones(5)
        results: dict[str, Any] = {
            "spectrum": {
                "phi_0": {
                    "initial": {"wavenumbers": wn, "power": power},
                    "final": {"wavenumbers": wn, "power": power},
                },
            },
        }
        _plot_spectrum(ax, results)
        assert ax.get_visible()
