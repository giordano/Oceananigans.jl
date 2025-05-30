using Oceananigans.Grids: AbstractGrid
using Oceananigans.Operators: ∂xᶠᶜᶜ, ∂yᶜᶠᶜ
using Oceananigans.BoundaryConditions: regularize_field_boundary_conditions

using Adapt

"""
    struct ExplicitFreeSurface{E, T}

The explicit free surface solver.

$(TYPEDFIELDS)
"""
struct ExplicitFreeSurface{E, G} <: AbstractFreeSurface{E, G}
    "free surface elevation"
    η :: E
    "gravitational accelerations"
    gravitational_acceleration :: G
end

ExplicitFreeSurface(; gravitational_acceleration=g_Earth) =
    ExplicitFreeSurface(nothing, gravitational_acceleration)

Adapt.adapt_structure(to, free_surface::ExplicitFreeSurface) =
    ExplicitFreeSurface(Adapt.adapt(to, free_surface.η), free_surface.gravitational_acceleration)

on_architecture(to, free_surface::ExplicitFreeSurface) =
    ExplicitFreeSurface(on_architecture(to, free_surface.η),
                        on_architecture(to, free_surface.gravitational_acceleration))

# Internal function for HydrostaticFreeSurfaceModel
function materialize_free_surface(free_surface::ExplicitFreeSurface{Nothing}, velocities, grid)
    η = free_surface_displacement_field(velocities, free_surface, grid)
    g = convert(eltype(grid), free_surface.gravitational_acceleration)
    return ExplicitFreeSurface(η, g)
end

#####
##### Kernel functions for HydrostaticFreeSurfaceModel
#####

@inline explicit_barotropic_pressure_x_gradient(i, j, k, grid, free_surface::ExplicitFreeSurface) =
    free_surface.gravitational_acceleration * ∂xᶠᶜᶜ(i, j, grid.Nz+1, grid, free_surface.η)

@inline explicit_barotropic_pressure_y_gradient(i, j, k, grid, free_surface::ExplicitFreeSurface) =
    free_surface.gravitational_acceleration * ∂yᶜᶠᶜ(i, j, grid.Nz+1, grid, free_surface.η)

#####
##### Time stepping
#####

step_free_surface!(free_surface::ExplicitFreeSurface, model, timestepper::QuasiAdamsBashforth2TimeStepper, Δt) =
    @apply_regionally explicit_ab2_step_free_surface!(free_surface, model, Δt, timestepper.χ)

step_free_surface!(free_surface::ExplicitFreeSurface, model, timestepper::SplitRungeKutta3TimeStepper, Δt) =
    @apply_regionally explicit_rk3_step_free_surface!(free_surface, model, Δt, timestepper)

@inline rk3_coeffs(ts, ::Val{1}) = (1,     0)
@inline rk3_coeffs(ts, ::Val{2}) = (ts.γ², ts.ζ²)
@inline rk3_coeffs(ts, ::Val{3}) = (ts.γ³, ts.ζ³)

function explicit_rk3_step_free_surface!(free_surface, model, Δt, timestepper)

    γⁿ, ζⁿ = rk3_coeffs(timestepper, Val(model.clock.stage))

    launch!(model.architecture, model.grid, :xy,
            _explicit_rk3_step_free_surface!, free_surface.η, Δt, γⁿ, ζⁿ,
            model.timestepper.Gⁿ.η, model.timestepper.Ψ⁻.η, size(model.grid, 3))

    return nothing
end

explicit_ab2_step_free_surface!(free_surface, model, Δt, χ) =
    launch!(model.architecture, model.grid, :xy,
            _explicit_ab2_step_free_surface!, free_surface.η, Δt, χ,
            model.timestepper.Gⁿ.η, model.timestepper.G⁻.η, size(model.grid, 3))

#####
##### Kernels
#####

@kernel function _explicit_rk3_step_free_surface!(η, Δt, γⁿ, ζⁿ, Gⁿ, η⁻, Nz)
    i, j = @index(Global, NTuple)
    @inbounds η[i, j, Nz+1] += ζⁿ * η⁻[i, j, Nz+1] + γⁿ * (η[i, j, Nz+1] + Δt * Gⁿ[i, j, Nz+1])
end

@kernel function _explicit_ab2_step_free_surface!(η, Δt, χ, Gηⁿ, Gη⁻, Nz)
    i, j = @index(Global, NTuple)
    FT0 = typeof(χ)
    one_point_five = convert(FT0, 1.5)
    oh_point_five = convert(FT0, 0.5)
    not_euler = χ != convert(FT0, -0.5)
    @inbounds begin
        Gη = (one_point_five + χ) * Gηⁿ[i, j, Nz+1] - (oh_point_five  + χ) * Gη⁻[i, j, Nz+1] * not_euler
        η[i, j, Nz+1] += Δt * Gη
    end
end

#####
##### Tendency calculators for an explicit free surface
#####

""" Calculate the right-hand-side of the free surface displacement (``η``) equation. """
@kernel function compute_hydrostatic_free_surface_Gη!(Gη, grid, args)
    i, j = @index(Global, NTuple)
    @inbounds Gη[i, j, grid.Nz+1] = free_surface_tendency(i, j, grid, args...)
end

"""
    free_surface_tendency(i, j, grid,
                          velocities,
                          free_surface,
                          tracers,
                          auxiliary_fields,
                          forcings,
                          clock)

Return the tendency for an explicit free surface at horizontal grid point `i, j`.

The tendency is called ``G_η`` and defined via

```math
∂_t η = G_η
```
"""
@inline function free_surface_tendency(i, j, grid,
                                       velocities,
                                       free_surface,
                                       tracers,
                                       auxiliary_fields,
                                       forcings,
                                       clock)

    k_top = grid.Nz + 1
    model_fields = merge(hydrostatic_fields(velocities, free_surface, tracers), auxiliary_fields)

    return @inbounds (  velocities.w[i, j, k_top]
                      + forcings.η(i, j, k_top, grid, clock, model_fields))
end

compute_free_surface_tendency!(grid, model, ::ExplicitFreeSurface) =
    @apply_regionally compute_explicit_free_surface_tendency!(grid, model)

# Compute free surface tendency
function compute_explicit_free_surface_tendency!(grid, model)

    arch = architecture(grid)

    args = tuple(model.velocities,
                 model.free_surface,
                 model.tracers,
                 model.auxiliary_fields,
                 model.forcing,
                 model.clock)

    launch!(arch, grid, :xy,
            compute_hydrostatic_free_surface_Gη!, model.timestepper.Gⁿ.η,
            grid, args)

    args = (model.clock,
            fields(model),
            model.closure,
            model.buoyancy)

    apply_flux_bcs!(model.timestepper.Gⁿ.η, displacement(model.free_surface), arch, args)

    return nothing
end