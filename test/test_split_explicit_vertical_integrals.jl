include("dependencies_for_runtests.jl")

using Oceananigans.Fields: VelocityFields
using Oceananigans.Models.HydrostaticFreeSurfaceModels
using Oceananigans.Models.HydrostaticFreeSurfaceModels: materialize_free_surface
using Oceananigans.Models.HydrostaticFreeSurfaceModels: SplitExplicitFreeSurface
using Oceananigans.Models.HydrostaticFreeSurfaceModels.SplitExplicitFreeSurfaces: compute_barotropic_mode!,
                                                                                  barotropic_split_explicit_corrector!,
                                                                                  initialize_free_surface_state!

@testset "Barotropic Kernels" begin

    for arch in archs
        FT = Float64
        topology = (Periodic, Periodic, Bounded)
        Nx, Ny, Nz = 128, 64, 32
        Lx = Ly = Lz = 2π

        grid = RectilinearGrid(arch, topology = topology, size = (Nx, Ny, Nz), x = (0, Lx), y = (0, Ly), z = (-Lz, 0))

        velocities = VelocityFields(grid)
        sefs = SplitExplicitFreeSurface(substeps = 200)
        sefs = materialize_free_surface(sefs, velocities, grid)

        state = sefs.filtered_state
        barotropic_velocities = sefs.barotropic_velocities
        η̅, U̅, V̅ = state.η, state.U, state.V
        U, V = barotropic_velocities

        u = Field{Face, Center, Center}(grid)
        v = Field{Center, Face, Center}(grid)

        GU = Field{Face, Center, Nothing}(grid)
        GV = Field{Center, Face, Nothing}(grid)

        @testset "Average to zero" begin
            # set equal to something else
            η̅ .= 1
            U̅ .= 1
            V̅ .= 1

            # now set equal to zero
            initialize_free_surface_state!(sefs, sefs.timestepper, sefs.timestepper, Val(1))

            # don't forget the halo points
            fill_halo_regions!(η̅)
            fill_halo_regions!(U̅)
            fill_halo_regions!(V̅)

            # check
            @test all(Array(η̅.data.parent) .== 0.0)
            @test all(Array(U̅.data.parent) .== 0.0)
            @test all(Array(V̅.data.parent) .== 0.0)
        end

        @testset "Inexact integration" begin
            # Test 2: Check that vertical integrals work on the CPU(). The following should be "inexact"
            Δz = zeros(Nz)
            Δz .= grid.z.Δᵃᵃᶠ

            set_u_check(x, y, z) = cos((π / 2) * z / Lz)
            set_U_check(x, y)    = (sin(0) - (-2 * Lz / (π)))
            set!(u, set_u_check)
            exact_U = similar(U)
            set!(exact_U, set_U_check)
            compute_barotropic_mode!(U, V, grid, u, v, η̅)
            tolerance = 1e-3
            @test all((Array(interior(U) .- interior(exact_U))) .< tolerance)

            set_v_check(x, y, z) = sin(x * y) * cos((π / 2) * z / Lz)
            set_V_check(x, y)    = sin(x * y) * (sin(0) - (-2 * Lz / (π)))
            set!(v, set_v_check)
            exact_V = similar(V)
            set!(exact_V, set_V_check)
            compute_barotropic_mode!(U, V, grid, u, v, η̅)
            @test all((Array(interior(V) .- interior(exact_V))) .< tolerance)
        end

        @testset "Vertical Integral " begin
            Δz = zeros(Nz)
            Δz .= grid.z.Δᵃᵃᶜ

            set!(u, 0)
            set!(U, 1)
            compute_barotropic_mode!(U, V, grid, u, v, η̅)
            @test all(Array(interior(U)) .== 0.0)

            set!(u, 1)
            set!(U, 1)
            compute_barotropic_mode!(U, V, grid, u, v, η̅)
            @test all(Array(interior(U)) .≈ Lz)

            set_u_check(x, y, z) = sin(x)
            set_U_check(x, y)    = sin(x) * Lz
            set!(u, set_u_check)
            exact_U = similar(U)
            set!(exact_U, set_U_check)
            compute_barotropic_mode!(U, V, grid, u, v, η̅)
            @test all(Array(interior(U)) .≈ Array(interior(exact_U)))

            set_v_check(x, y, z) = sin(x) * z * cos(y)
            set_V_check(x, y)    = -sin(x) * Lz^2 / 2.0 * cos(y)
            set!(v, set_v_check)
            exact_V = similar(V)
            set!(exact_V, set_V_check)
            compute_barotropic_mode!(U, V, grid, u, v, η̅)
            @test all(Array(interior(V)) .≈ Array(interior(exact_V)))
        end

        @testset "Barotropic Correction" begin
            # Test 4: Test Barotropic Correction
            FT = Float64
            topology = (Periodic, Periodic, Bounded)
            Nx, Ny, Nz = 128, 64, 32
            Lx = Ly = Lz = 2π

            grid       = RectilinearGrid(arch, topology = topology, size = (Nx, Ny, Nz), x = (0, Lx), y = (0, Ly), z = (-Lz, 0))
            velocities = VelocityFields(grid)

            sefs = SplitExplicitFreeSurface(grid, cfl=0.7)
            sefs = materialize_free_surface(sefs, velocities, grid)

            U, V = sefs.barotropic_velocities
            u = velocities.u
            v = velocities.v
            u_corrected = similar(u)
            v_corrected = similar(v)

            set_u(x, y, z) = z + Lz / 2 + sin(x)
            set_U̅(x, y)    = cos(x) * Lz
            set_u_corrected(x, y, z) = z + Lz / 2 + cos(x)
            set!(u, set_u)
            set!(U, set_U̅)
            set!(u_corrected, set_u_corrected)

            set_v(x, y, z) = (z + Lz / 2) * sin(y) + sin(x)
            set_V̅(x, y)    = (cos(x) + x) * Lz
            set_v_corrected(x, y, z) = (z + Lz / 2) * sin(y) + cos(x) + x
            set!(v, set_v)
            set!(V, set_V̅)
            set!(v_corrected, set_v_corrected)

            barotropic_split_explicit_corrector!(u, v, sefs, grid)
            @test all(Array((interior(u) .- interior(u_corrected))) .< 1e-14)
            @test all(Array((interior(v) .- interior(v_corrected))) .< 1e-14)
        end
    end # end of architecture loop
end # end of testset
