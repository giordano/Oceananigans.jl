using Oceananigans.Utils: prettytime, ordered_dict_show, prettykeys
using Oceananigans.TurbulenceClosures: closure_summary

function Base.summary(model::HydrostaticFreeSurfaceModel)
    A = nameof(typeof(architecture(model.grid)))
    G = nameof(typeof(model.grid))
    return string("HydrostaticFreeSurfaceModel{$A, $G}",
                  "(time = ", prettytime(model.clock.time),
                  ", iteration = ", prettysummary(model.clock.iteration), ")")
end

function Base.show(io::IO, model::HydrostaticFreeSurfaceModel)
    TS = nameof(typeof(model.timestepper))
    tracernames = prettykeys(model.tracers)

    print(io, summary(model), "\n",
        "├── grid: ", summary(model.grid), "\n",
        "├── timestepper: ", TS, "\n",
        "├── tracers: ", tracernames, "\n",
        "├── closure: ", closure_summary(model.closure), "\n",
        "├── buoyancy: ", summary(model.buoyancy), "\n")

    if model.free_surface !== nothing
        print(io, "├── free surface: ", typeof(model.free_surface).name.wrapper, " with gravitational acceleration $(model.free_surface.gravitational_acceleration) m s⁻²", "\n")

        if typeof(model.free_surface).name.wrapper == ImplicitFreeSurface
            print(io, "│   └── solver: ", string(model.free_surface.solver_method), "\n")
        end

        if typeof(model.free_surface).name.wrapper == SplitExplicitFreeSurface
            print(io, "│   └── substepping: $(summary(model.free_surface.substepping))", "\n")
        end
    end

    if model.advection !== nothing
        print(io, "├── advection scheme: ", "\n")
        names = keys(model.advection)
        for name in names[1:end-1]
            print(io, "│   ├── " * string(name) * ": " * summary(model.advection[name]), "\n")
        end
        name = names[end]
        print(io, "│   └── " * string(name) * ": " * summary(model.advection[name]), "\n")
    end

    if isnothing(model.particles)
        print(io, "└── coriolis: $(typeof(model.coriolis))")
    else
        particles = model.particles.properties
        properties = propertynames(particles)
        print(io, "├── coriolis: $(typeof(model.coriolis))\n")
        print(io, "└── particles: $(length(particles)) Lagrangian particles with $(length(properties)) properties: $properties")
    end
end
