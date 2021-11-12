from veros.core.operators import update, update_add, at, numpy as npx
from veros.variables import allocate
import numpy as onp


def assemble_poisson_matrix(state, solver_type=None):
    if state.settings.enable_streamfunction:
        return assemble_streamfunction_matrix(state, solver_type=solver_type)
    else:
        return assemble_pressure_matrix(state, solver_type=solver_type)


def assemble_pressure_matrix(state, solver_type):
    main_diag = allocate(state.dimensions, ("xu", "yu"), local=False)
    east_diag, west_diag, north_diag, south_diag = (
        allocate(state.dimensions, ("xu", "yu"), local=False) for _ in range(4)
    )

    vs = state.variables
    settings = state.settings

    maskM = allocate(state.dimensions, ("xu", "yu"), local=False)
    mp_i, mm_i, mp_j, mm_j = (
        allocate(state.dimensions, ("xu", "yu"), local=False, include_ghosts=False) for _ in range(4)
    )

    maskM = update(maskM, at[:, :], vs.maskT[:, :, -1])

    mp_i = update(mp_i, at[:, :], maskM[2:-2, 2:-2] * maskM[3:-1, 2:-2])
    mm_i = update(mm_i, at[:, :], maskM[2:-2, 2:-2] * maskM[1:-3, 2:-2])

    mp_j = update(mp_j, at[:, :], maskM[2:-2, 2:-2] * maskM[2:-2, 3:-1])
    mm_j = update(mm_j, at[:, :], maskM[2:-2, 2:-2] * maskM[2:-2, 1:-3])

    main_diag = update(
        main_diag,
        at[2:-2, 2:-2],
        -mp_i
        * vs.hu[2:-2, 2:-2]
        / vs.dxu[2:-2, npx.newaxis]
        / vs.dxt[2:-2, npx.newaxis]
        / vs.cost[npx.newaxis, 2:-2] ** 2
        - mm_i
        * vs.hu[1:-3, 2:-2]
        / vs.dxu[1:-3, npx.newaxis]
        / vs.dxt[2:-2, npx.newaxis]
        / vs.cost[npx.newaxis, 2:-2] ** 2
        - mp_j
        * vs.hv[2:-2, 2:-2]
        / vs.dyu[npx.newaxis, 2:-2]
        / vs.dyt[npx.newaxis, 2:-2]
        * vs.cosu[npx.newaxis, 2:-2]
        / vs.cost[npx.newaxis, 2:-2]
        - mm_j
        * vs.hv[2:-2, 1:-3]
        / vs.dyu[npx.newaxis, 1:-3]
        / vs.dyt[npx.newaxis, 2:-2]
        * vs.cosu[npx.newaxis, 1:-3]
        / vs.cost[npx.newaxis, 2:-2],
    )

    if settings.enable_free_surface:
        main_diag = update_add(
            main_diag,
            at[2:-2, 2:-2],
            -1.0 / (settings.grav * settings.dt_mom * settings.dt_tracer) * maskM[2:-2, 2:-2],
        )
    # TODO: Compatibility with pyom , use dt_mom squared

    east_diag = update(
        east_diag,
        at[2:-2, 2:-2],
        mp_i
        * vs.hu[2:-2, 2:-2]
        / vs.dxu[2:-2, npx.newaxis]
        / vs.dxt[2:-2, npx.newaxis]
        / vs.cost[npx.newaxis, 2:-2] ** 2,
    )

    west_diag = update(
        west_diag,
        at[2:-2, 2:-2],
        mm_i
        * vs.hu[1:-3, 2:-2]
        / vs.dxu[1:-3, npx.newaxis]
        / vs.dxt[2:-2, npx.newaxis]
        / vs.cost[npx.newaxis, 2:-2] ** 2,
    )

    north_diag = update(
        north_diag,
        at[2:-2, 2:-2],
        mp_j
        * vs.hv[2:-2, 2:-2]
        / vs.dyu[npx.newaxis, 2:-2]
        / vs.dyt[npx.newaxis, 2:-2]
        * vs.cosu[npx.newaxis, 2:-2]
        / vs.cost[npx.newaxis, 2:-2],
    )

    south_diag = update(
        south_diag,
        at[2:-2, 2:-2],
        mm_j
        * vs.hv[2:-2, 1:-3]
        / vs.dyu[npx.newaxis, 1:-3]
        / vs.dyt[npx.newaxis, 2:-2]
        * vs.cosu[npx.newaxis, 1:-3]
        / vs.cost[npx.newaxis, 2:-2],
    )
    main_diag = main_diag * maskM
    main_diag = npx.where(main_diag == 0.0, 1, main_diag)
    if solver_type == "scipy":
        offsets = (0, -main_diag.shape[1], main_diag.shape[1], -1, 1)

        if settings.enable_cyclic_x:
            wrap_diag_east, wrap_diag_west = (allocate(state.dimensions, ("xu", "yu"), local=False) for _ in range(2))
            wrap_diag_east = update(wrap_diag_east, at[2, 2:-2], west_diag[2, 2:-2] * maskM[2, 2:-2])
            wrap_diag_west = update(wrap_diag_west, at[-3, 2:-2], east_diag[-3, 2:-2] * maskM[-3, 2:-2])
            west_diag = update(west_diag, at[2, 2:-2], 0.0)
            east_diag = update(east_diag, at[-3, 2:-2], 0.0)
    else:
        offsets = [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)]

    cf = tuple(
        diag.reshape(-1)
        for diag in (
            main_diag,
            east_diag,
            west_diag,
            north_diag,
            south_diag,
        )
    )
    if solver_type == "scipy":
        if settings.enable_cyclic_x:
            offsets += (-main_diag.shape[1] * (settings.nx - 1), main_diag.shape[1] * (settings.nx - 1))
            cf += (wrap_diag_east.reshape(-1), wrap_diag_west.reshape(-1))

    print(len(npx.argwhere(vs.maskT[:, :, -1] == 0)))
    cf = onp.asarray(cf, dtype="float64")

    return cf, offsets


def assemble_streamfunction_matrix(state, solver_type):
    vs = state.variables
    settings = state.settings

    boundary_mask = ~npx.any(vs.boundary_mask, axis=2)

    # assemble diagonals
    main_diag = allocate(state.dimensions, ("xu", "yu"), fill=1, local=False)
    east_diag, west_diag, north_diag, south_diag = (
        allocate(state.dimensions, ("xu", "yu"), local=False) for _ in range(4)
    )
    main_diag = update(
        main_diag,
        at[2:-2, 2:-2],
        -vs.hvr[3:-1, 2:-2] / vs.dxu[2:-2, npx.newaxis] / vs.dxt[3:-1, npx.newaxis] / vs.cosu[npx.newaxis, 2:-2] ** 2
        - vs.hvr[2:-2, 2:-2] / vs.dxu[2:-2, npx.newaxis] / vs.dxt[2:-2, npx.newaxis] / vs.cosu[npx.newaxis, 2:-2] ** 2
        - vs.hur[2:-2, 2:-2]
        / vs.dyu[npx.newaxis, 2:-2]
        / vs.dyt[npx.newaxis, 2:-2]
        * vs.cost[npx.newaxis, 2:-2]
        / vs.cosu[npx.newaxis, 2:-2]
        - vs.hur[2:-2, 3:-1]
        / vs.dyu[npx.newaxis, 2:-2]
        / vs.dyt[npx.newaxis, 3:-1]
        * vs.cost[npx.newaxis, 3:-1]
        / vs.cosu[npx.newaxis, 2:-2],
    )
    east_diag = update(
        east_diag,
        at[2:-2, 2:-2],
        vs.hvr[3:-1, 2:-2] / vs.dxu[2:-2, npx.newaxis] / vs.dxt[3:-1, npx.newaxis] / vs.cosu[npx.newaxis, 2:-2] ** 2,
    )
    west_diag = update(
        west_diag,
        at[2:-2, 2:-2],
        vs.hvr[2:-2, 2:-2] / vs.dxu[2:-2, npx.newaxis] / vs.dxt[2:-2, npx.newaxis] / vs.cosu[npx.newaxis, 2:-2] ** 2,
    )
    north_diag = update(
        north_diag,
        at[2:-2, 2:-2],
        vs.hur[2:-2, 3:-1]
        / vs.dyu[npx.newaxis, 2:-2]
        / vs.dyt[npx.newaxis, 3:-1]
        * vs.cost[npx.newaxis, 3:-1]
        / vs.cosu[npx.newaxis, 2:-2],
    )
    south_diag = update(
        south_diag,
        at[2:-2, 2:-2],
        vs.hur[2:-2, 2:-2]
        / vs.dyu[npx.newaxis, 2:-2]
        / vs.dyt[npx.newaxis, 2:-2]
        * vs.cost[npx.newaxis, 2:-2]
        / vs.cosu[npx.newaxis, 2:-2],
    )

    main_diag = main_diag * boundary_mask
    main_diag = npx.where(main_diag == 0.0, 1.0, main_diag)

    if solver_type == "scipy":
        if settings.enable_cyclic_x:
            # couple edges of the domain
            wrap_diag_east, wrap_diag_west = (allocate(state.dimensions, ("xu", "yu"), local=False) for _ in range(2))
            wrap_diag_east = update(wrap_diag_east, at[2, 2:-2], west_diag[2, 2:-2] * boundary_mask[2, 2:-2])
            wrap_diag_west = update(wrap_diag_west, at[-3, 2:-2], east_diag[-3, 2:-2] * boundary_mask[-3, 2:-2])
            west_diag = update(west_diag, at[2, 2:-2], 0.0)
            east_diag = update(east_diag, at[-3, 2:-2], 0.0)

        offsets = (0, -main_diag.shape[1], main_diag.shape[1], -1, 1)
    else:
        offsets = [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)]

    # construct sparse matrix
    cf = tuple(
        diag.reshape(-1)
        for diag in (
            main_diag,
            boundary_mask * east_diag,
            boundary_mask * west_diag,
            boundary_mask * north_diag,
            boundary_mask * south_diag,
        )
    )

    if solver_type == "scipy":
        if settings.enable_cyclic_x:
            offsets += (-main_diag.shape[1] * (settings.nx - 1), main_diag.shape[1] * (settings.nx - 1))
            cf += (wrap_diag_east.reshape(-1), wrap_diag_west.reshape(-1))

    cf = onp.asarray(cf, dtype="float64")
    return cf, offsets
