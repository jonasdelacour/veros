import pytest

from veros.core import external, utilities
from veros.pyom_compat import get_random_state

from test_base import compare_state


@pytest.fixture
def random_state(pyom2_lib):
    return get_random_state(
        pyom2_lib,
        extra_settings=dict(
            nx=60,
            ny=40,
            nz=30,
            dt_tracer=12000,
            dt_mom=3600,
            enable_cyclic_x=True,
            enable_free_surface=True,
            enable_streamfunction=False,
        ),
    )


def test_solve_pressure(random_state):
    vs_state, pyom_obj = random_state

    vs = vs_state.variables
    settings = vs_state.settings

    # results are only identical if initial guess is already cyclic
    m = pyom_obj.main_module
    m.psi[...] = utilities.enforce_boundaries(m.psi, settings.enable_cyclic_x)
    vs.psi = utilities.enforce_boundaries(vs.psi, settings.enable_cyclic_x)

    vs.update(external.solve_pressure.solve_pressure(vs_state))
    pyom_obj.solve_pressure()

    compare_state(vs_state, pyom_obj)