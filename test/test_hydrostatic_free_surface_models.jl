include("dependencies_for_runtests.jl")

using Oceananigans.Models.HydrostaticFreeSurfaceModels: VectorInvariant, PrescribedVelocityFields
using Oceananigans.Models.HydrostaticFreeSurfaceModels: ExplicitFreeSurface, ImplicitFreeSurface
using Oceananigans.Models.HydrostaticFreeSurfaceModels: SingleColumnGrid
using Oceananigans.Advection: EnergyConserving, EnstrophyConserving, FluxFormAdvection
using Oceananigans.TurbulenceClosures
using Oceananigans.TurbulenceClosures: CATKEVerticalDiffusivity

function time_step_hydrostatic_model_works(grid;
                                           coriolis = nothing,
                                           free_surface = ExplicitFreeSurface(),
                                           momentum_advection = nothing,
                                           tracers = [:b],
                                           tracer_advection = nothing,
                                           closure = nothing,
                                           velocities = nothing)

    buoyancy = BuoyancyTracer()
    closure isa CATKEVerticalDiffusivity && push!(tracers, :e)

    model = HydrostaticFreeSurfaceModel(; grid, coriolis, tracers, velocities, buoyancy,
                                        momentum_advection, tracer_advection, free_surface, closure)

    simulation = Simulation(model, Δt=1.0, stop_iteration=1)

    run!(simulation)

    return model.clock.iteration == 1
end

function hydrostatic_free_surface_model_tracers_and_forcings_work(arch)
    grid = RectilinearGrid(arch, size=(1, 1, 1), extent=(2π, 2π, 2π))
    model = HydrostaticFreeSurfaceModel(grid=grid, tracers=(:T, :S, :c, :d))

    @test model.tracers.T isa Field
    @test model.tracers.S isa Field
    @test model.tracers.c isa Field
    @test model.tracers.d isa Field

    @test haskey(model.forcing, :u)
    @test haskey(model.forcing, :v)
    @test haskey(model.forcing, :η)
    @test haskey(model.forcing, :T)
    @test haskey(model.forcing, :S)
    @test haskey(model.forcing, :c)
    @test haskey(model.forcing, :d)

    simulation = Simulation(model, Δt=1.0, stop_iteration=1)
    run!(simulation)

    @test model.clock.iteration == 1

    return nothing
end

function time_step_hydrostatic_model_with_catke_works(arch, FT)
    grid = LatitudeLongitudeGrid(
        arch,
        FT,
        topology = (Bounded, Bounded, Bounded),
        size = (8, 8, 8),
        longitude = (0, 1),
        latitude = (0, 1),
        z = (-100, 0)
    )

    model = HydrostaticFreeSurfaceModel(;
        grid,
        buoyancy = BuoyancyTracer(),
        tracers = (:b, :e),
        closure = CATKEVerticalDiffusivity(FT)
    )

    simulation = Simulation(model, Δt=1.0, stop_iteration=1)

    run!(simulation)

    return model.clock.iteration == 1
end

topo_1d = (Flat, Flat, Bounded)

topos_2d = ((Periodic, Flat, Bounded),
            (Flat, Bounded,  Bounded),
            (Bounded, Flat,  Bounded))

topos_3d = ((Periodic, Periodic, Bounded),
            (Periodic, Bounded,  Bounded),
            (Bounded,  Bounded,  Bounded))

@testset "Hydrostatic free surface Models" begin
    @info "Testing hydrostatic free surface models..."

    @testset "$topo_1d model construction" begin
        @info "  Testing $topo_1d model construction..."
        for arch in archs, FT in [Float64] #float_types
            grid = RectilinearGrid(arch, FT, topology=topo_1d, size=1, extent=1)
            model = HydrostaticFreeSurfaceModel(; grid)
            @test model isa HydrostaticFreeSurfaceModel

            # SingleColumnGrid tests
            @test grid isa SingleColumnGrid
            @test isnothing(model.free_surface)
        end
    end

    for topo in topos_2d
        @testset "$topo model construction" begin
            @info "  Testing $topo model construction..."
            for arch in archs, FT in float_types
                grid = RectilinearGrid(arch, FT, topology=topo, size=(1, 1), extent=(1, 2))
                model = HydrostaticFreeSurfaceModel(; grid)
                @test model isa HydrostaticFreeSurfaceModel
            end
        end
    end

    for topo in topos_3d
        @testset "$topo model construction" begin
            @info "  Testing $topo model construction..."
            for arch in archs, FT in float_types
                grid = RectilinearGrid(arch, FT, topology=topo, size=(1, 1, 1), extent=(1, 2, 3))
                model = HydrostaticFreeSurfaceModel(; grid)
                @test model isa HydrostaticFreeSurfaceModel
            end
        end
    end

    for FreeSurface in (ExplicitFreeSurface, ImplicitFreeSurface, SplitExplicitFreeSurface, Nothing)
        @testset "$FreeSurface model construction" begin
            @info "  Testing $FreeSurface model construction..."
            for arch in archs, FT in float_types
                grid = RectilinearGrid(arch, FT, size=(1, 1, 1), extent=(1, 2, 3))
                model = HydrostaticFreeSurfaceModel(; grid, free_surface=FreeSurface())
                @test model isa HydrostaticFreeSurfaceModel
            end
        end
    end

    @testset "Halo size check in model constructor" begin
        for topo in topos_3d
            grid = RectilinearGrid(topology=topo, size=(1, 1, 1), extent=(1, 2, 3), halo=(1, 1, 1))
            hcabd_closure = ScalarBiharmonicDiffusivity()

            @test_throws ArgumentError HydrostaticFreeSurfaceModel(grid=grid, tracer_advection=Centered(order=4))
            @test_throws ArgumentError HydrostaticFreeSurfaceModel(grid=grid, tracer_advection=UpwindBiased(order=3))
            @test_throws ArgumentError HydrostaticFreeSurfaceModel(grid=grid, tracer_advection=UpwindBiased(order=5))
            @test_throws ArgumentError HydrostaticFreeSurfaceModel(grid=grid, momentum_advection=UpwindBiased(order=5))
            @test_throws ArgumentError HydrostaticFreeSurfaceModel(grid=grid, closure=hcabd_closure)

            # Big enough
            bigger_grid = RectilinearGrid(topology=topo, size=(3, 3, 1), extent=(1, 2, 3), halo=(3, 3, 3))

            model = HydrostaticFreeSurfaceModel(grid=bigger_grid, closure=hcabd_closure)
            @test model isa HydrostaticFreeSurfaceModel

            model = HydrostaticFreeSurfaceModel(grid=bigger_grid, momentum_advection=UpwindBiased(order=5))
            @test model isa HydrostaticFreeSurfaceModel

            model = HydrostaticFreeSurfaceModel(grid=bigger_grid, closure=hcabd_closure)
            @test model isa HydrostaticFreeSurfaceModel

            model = HydrostaticFreeSurfaceModel(grid=bigger_grid, tracer_advection=UpwindBiased(order=5))
            @test model isa HydrostaticFreeSurfaceModel
        end
    end

    @testset "Setting HydrostaticFreeSurfaceModel fields" begin
        @info "  Testing setting hydrostatic free surface model fields..."
        for arch in archs, FT in float_types
            N = (4, 4, 1)
            L = (2π, 3π, 5π)

            grid = RectilinearGrid(arch, FT, size=N, extent=L)
            model = HydrostaticFreeSurfaceModel(grid=grid)

            x, y, z = nodes(model.grid, (Face(), Center(), Center()), reshape=true)

            u₀(x, y, z) = x * y^2
            u_answer = @. x * y^2

            η₀ = rand(size(grid)...)
            η_answer = deepcopy(η₀)

            set!(model, u=u₀, η=η₀)

            u, v, w = model.velocities
            η = model.free_surface.η

            @test all(Array(interior(u)) .≈ u_answer)
            @test all(Array(interior(η)) .≈ η_answer)
        end
    end

    for arch in archs

        for topo in topos_3d
            grid = RectilinearGrid(arch, size=(1, 1, 1), extent=(1, 1, 1), topology=topo)

            @testset "Time-stepping Rectilinear HydrostaticFreeSurfaceModels [$arch, $topo]" begin
                @info "  Testing time-stepping Rectilinear HydrostaticFreeSurfaceModels [$arch, $topo]..."
                @test time_step_hydrostatic_model_works(grid)
            end
        end

        z_face_generator(; Nz=1, p=1, H=1) = k -> -H + (k / (Nz+1))^p # returns a generating function

        H = 7
        halo = (7, 7, 7)
        rectilinear_grid = RectilinearGrid(arch; size=(H, H, 1), extent=(1, 1, 1), halo)
        vertically_stretched_grid = RectilinearGrid(arch; size=(H, H, 1), x=(0, 1), y=(0, 1), z=z_face_generator(), halo=(H, H, H))

        precompute_metrics = true
        lat_lon_sector_grid = LatitudeLongitudeGrid(arch; size=(H, H, H), longitude=(0, 60), latitude=(15, 75), z=(-1, 0), precompute_metrics, halo)
        lat_lon_strip_grid  = LatitudeLongitudeGrid(arch; size=(H, H, H), longitude=(-180, 180), latitude=(15, 75), z=(-1, 0), precompute_metrics, halo)

        z = z_face_generator()
        lat_lon_sector_grid_stretched = LatitudeLongitudeGrid(arch; size=(H, H, H), longitude=(0, 60), latitude=(15, 75), z, precompute_metrics, halo)
        lat_lon_strip_grid_stretched  = LatitudeLongitudeGrid(arch; size=(H, H, H), longitude=(-180, 180), latitude=(15, 75), z, precompute_metrics, halo)

        grids = (rectilinear_grid, vertically_stretched_grid,
                 lat_lon_sector_grid, lat_lon_strip_grid,
                 lat_lon_sector_grid_stretched, lat_lon_strip_grid_stretched)

        free_surfaces = (ExplicitFreeSurface(), ImplicitFreeSurface(), ImplicitFreeSurface(solver_method=:HeptadiagonalIterativeSolver))

        for grid in grids
            for free_surface in free_surfaces
                topo = topology(grid)
                grid_type = typeof(grid).name.wrapper
                free_surface_type = typeof(free_surface).name.wrapper
                test_label = "[$arch, $grid_type, $topo, $free_surface_type]"
                @testset "Time-stepping HydrostaticFreeSurfaceModels with various grids $test_label" begin
                    @info "  Testing time-stepping HydrostaticFreeSurfaceModels with various grids $test_label..."
                    @test time_step_hydrostatic_model_works(grid; free_surface)
                end
            end
        end

        @info " Time-stepping HydrostaticFreeSurfaceModels with y-Flat grid"
        lat_lon_flat_grid = LatitudeLongitudeGrid(arch; size=(H, H), longitude=(-180, 180), z=(-1, 0), precompute_metrics,
                                                  halo=(7, 7), topology=(Periodic, Flat, Bounded))
        @test_broken time_step_hydrostatic_model_works(lat_lon_flat_grid)
        c = CenterField(lat_lon_flat_grid) # just test we can build a field
        @test c.boundary_conditions.north isa Nothing
        @test c.boundary_conditions.south isa Nothing

        for topo in [topos_3d..., topos_2d...]
            size = Flat in topo ? (10, 10) : (10, 10, 10)
            halo = Flat in topo ? (7,  7)  : (7, 7, 7)
            x    = topo[1] == Flat ? nothing : (0, 1)
            y    = topo[2] == Flat ? nothing : (0, 1)

            grid = RectilinearGrid(arch; size, halo, x, y, z=(-1, 0), topology=topo)

            for advection in [WENOVectorInvariant(), VectorInvariant(), WENO()]
                @testset "Time-stepping HydrostaticFreeSurfaceModels with $advection [$arch, $topo]" begin
                    @info "  Testing time-stepping HydrostaticFreeSurfaceModels with $advection [$arch, $topo]..."
                    @test time_step_hydrostatic_model_works(grid; momentum_advection=advection)
                end
            end
        end

        for coriolis in (nothing, FPlane(f=1), BetaPlane(f₀=1, β=0.1))
            @testset "Time-stepping HydrostaticFreeSurfaceModels [$arch, $(typeof(coriolis))]" begin
                @info "  Testing time-stepping HydrostaticFreeSurfaceModels [$arch, $(typeof(coriolis))]..."
                @test time_step_hydrostatic_model_works(rectilinear_grid, coriolis=coriolis)
            end
        end

        for coriolis in (nothing,
                         HydrostaticSphericalCoriolis(scheme=EnergyConserving()),
                         HydrostaticSphericalCoriolis(scheme=EnstrophyConserving()))

            @testset "Time-stepping HydrostaticFreeSurfaceModels [$arch, $(typeof(coriolis))]" begin
                @test time_step_hydrostatic_model_works(lat_lon_sector_grid; coriolis)
                @test time_step_hydrostatic_model_works(lat_lon_strip_grid; coriolis)
            end
        end

        for momentum_advection in (VectorInvariant(), WENOVectorInvariant(), Centered(), WENO())
            @testset "Time-stepping HydrostaticFreeSurfaceModels [$arch, $(typeof(momentum_advection))]" begin
                @info "  Testing time-stepping HydrostaticFreeSurfaceModels [$arch, $(typeof(momentum_advection))]..."
                @test time_step_hydrostatic_model_works(rectilinear_grid; momentum_advection)
            end
        end

        for momentum_advection in (VectorInvariant(), WENOVectorInvariant())
            @testset "Time-stepping HydrostaticFreeSurfaceModels [$arch, $(typeof(momentum_advection))]" begin
                @info "  Testing time-stepping HydrostaticFreeSurfaceModels [$arch, $(typeof(momentum_advection))]..."
                @test time_step_hydrostatic_model_works(lat_lon_sector_grid; momentum_advection)
            end
        end

        for tracer_advection in [WENO(),
                                 FluxFormAdvection(WENO(), WENO(), Centered()),
                                 (b=WENO(), c=nothing)]

            T = typeof(tracer_advection)
            @testset "Time-stepping HydrostaticFreeSurfaceModels with tracer advection [$arch, $T]" begin
                @info "  Testing time-stepping HydrostaticFreeSurfaceModels with tracer advection [$arch, $T]..."
                @test time_step_hydrostatic_model_works(rectilinear_grid; tracer_advection, tracers=[:b, :c])
            end
        end

        for closure in (ScalarDiffusivity(),
                        HorizontalScalarDiffusivity(),
                        VerticalScalarDiffusivity(),
                        VerticalScalarDiffusivity(VerticallyImplicitTimeDiscretization()),
                        CATKEVerticalDiffusivity(),
                        CATKEVerticalDiffusivity(ExplicitTimeDiscretization()))

            @testset "Time-stepping Curvilinear HydrostaticFreeSurfaceModels [$arch, $(typeof(closure).name.wrapper)]" begin
                @info "  Testing time-stepping Curvilinear HydrostaticFreeSurfaceModels [$arch, $(typeof(closure).name.wrapper)]..."
                @test_skip time_step_hydrostatic_model_works(arch, vertically_stretched_grid, closure=closure)
                @test time_step_hydrostatic_model_works(lat_lon_sector_grid; closure)
                @test time_step_hydrostatic_model_works(lat_lon_strip_grid; closure)
            end
        end

        closure = ScalarDiffusivity()
        @testset "Time-stepping Rectilinear HydrostaticFreeSurfaceModels [$arch, $(typeof(closure).name.wrapper)]" begin
            @info "  Testing time-stepping Rectilinear HydrostaticFreeSurfaceModels [$arch, $(typeof(closure).name.wrapper)]..."
            @test time_step_hydrostatic_model_works(rectilinear_grid, closure=closure)
        end

        @testset "Time-stepping HydrostaticFreeSurfaceModels with PrescribedVelocityFields [$arch]" begin
            @info "  Testing time-stepping HydrostaticFreeSurfaceModels with PrescribedVelocityFields [$arch]..."

            # Non-parameterized functions
            u(x, y, z, t) = 1
            v(x, y, z, t) = exp(z)
            w(x, y, z, t) = sin(z)
            velocities = PrescribedVelocityFields(u=u, v=v, w=w)

            @test time_step_hydrostatic_model_works(rectilinear_grid, momentum_advection  = nothing, velocities = velocities)
            @test time_step_hydrostatic_model_works(lat_lon_sector_grid, momentum_advection = nothing, velocities = velocities)

            parameters = (U=1, m=0.1, W=0.001)
            u(x, y, z, t, p) = p.U
            v(x, y, z, t, p) = exp(p.m * z)
            w(x, y, z, t, p) = p.W * sin(z)

            velocities = PrescribedVelocityFields(u=u, v=v, w=w, parameters=parameters)

            @test time_step_hydrostatic_model_works(rectilinear_grid, momentum_advection  = nothing, velocities = velocities)
            @test time_step_hydrostatic_model_works(lat_lon_sector_grid, momentum_advection = nothing, velocities = velocities)
        end

        @testset "HydrostaticFreeSurfaceModel with tracers and forcings [$arch]" begin
            @info "  Testing HydrostaticFreeSurfaceModel with tracers and forcings [$arch]..."
            hydrostatic_free_surface_model_tracers_and_forcings_work(arch)
        end

        # See: https://github.com/CliMA/Oceananigans.jl/issues/3870
        @testset "HydrostaticFreeSurfaceModel with Float32 CATKE [$arch]" begin
            @info "  Testing HydrostaticFreeSurfaceModel with Float32 CATKE [$arch]..."
            @test time_step_hydrostatic_model_with_catke_works(arch, Float32)
        end
    end
end
