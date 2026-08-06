Base.@kwdef struct ModelSettings
    geometry::YCGeometry
    J1::Float64 = 1.0
    J2::Float64 = 0.12
    Delta1::Float64 = 1.0
    Delta2::Float64 = 1.0
    Bz::Float64 = 0.0
    twist_gauge::Symbol = :uniform
    mps_period::Union{Nothing,Int} = nothing
end

function model_mps_period(model::ModelSettings)
    period = isnothing(model.mps_period) ? minimal_mps_period(model.geometry) : model.mps_period
    validate_mps_period(model.geometry, period)
    return period
end

Base.@kwdef struct OptimizerSettings
    maxdim::Int
    cutoff::Float64 = 1e-10
    residual_tol::Float64 = 1e-8
    max_iterations::Int = 100
    max_growth_steps::Int = 16
    solver_tol_scale::Float64 = 100.0
    solver_tol_floor::Float64 = 1e-10
    multisite_update_alg::String = "sequential"
    require_converged::Bool = true
    divergence_patience::Int = 8
    divergence_factor::Float64 = 4.0
end

Base.@kwdef struct ScanSettings
    branch::String
    fluxes_over_pi::Vector{Float64}
    seed_pattern::String = "alternating"
    random_seed::Int = 1
    adaptive_bisection::Bool = true
    minimum_step_over_pi::Float64 = 1 / 64
    save_rejected::Bool = true
    initial_state_file::Union{Nothing,String} = nothing
end

Base.@kwdef struct SpectrumSettings
    physical_sz_sectors::Vector{Float64} = [0.0, 1.0]
    neigs::Int = 16
    tolerance::Float64 = 1e-10
    krylov_dimension::Int = 40
    random_seed::Int = 1
end

Base.@kwdef struct RuntimeSettings
    output_directory::String
    blas_threads::Int = 1
    strided_threads::Int = 1
    threaded_blocksparse::Bool = false
    output_level::Int = 1
end

Base.@kwdef struct ProjectSettings
    model::ModelSettings
    optimizer::OptimizerSettings
    scan::ScanSettings
    spectrum::SpectrumSettings
    runtime::RuntimeSettings
    config_path::String
    config_text::String
end

function table_value(table, key, default=nothing)
    return haskey(table, key) ? table[key] : default
end

function required_value(table, key, section)
    haskey(table, key) || error("missing required [$section].$key")
    return table[key]
end

function validate_flux_order(fluxes::AbstractVector{<:Real})
    isempty(fluxes) && throw(ArgumentError("flux schedule cannot be empty"))
    all(isfinite, fluxes) || throw(ArgumentError("flux schedule contains non-finite values"))
    length(unique(fluxes)) == length(fluxes) ||
        throw(ArgumentError("flux schedule contains duplicate values"))
    if length(fluxes) > 2
        differences = diff(fluxes)
        (all(>(0), differences) || all(<(0), differences)) ||
            throw(ArgumentError("flux schedule must be strictly monotonic"))
    end
    return true
end

function resolve_config_path(config_path::AbstractString, path_value)
    path_value === nothing && return nothing
    path = String(path_value)
    return isabspath(path) ? normpath(path) : normpath(joinpath(dirname(config_path), path))
end

function load_settings(config_path::AbstractString)
    absolute_config = abspath(config_path)
    isfile(absolute_config) || error("configuration file does not exist: $absolute_config")
    raw = TOML.parsefile(absolute_config)

    model_table = required_value(raw, "model", "root")
    geometry = YCGeometry(
        Int(required_value(model_table, "circumference", "model")),
        Int(table_value(model_table, "shift", 0)),
    )
    model = ModelSettings(
        geometry=geometry,
        J1=Float64(table_value(model_table, "J1", 1.0)),
        J2=Float64(table_value(model_table, "J2", 0.12)),
        Delta1=Float64(table_value(model_table, "Delta1", 1.0)),
        Delta2=Float64(table_value(model_table, "Delta2", 1.0)),
        Bz=Float64(table_value(model_table, "Bz", 0.0)),
        twist_gauge=Symbol(lowercase(String(table_value(model_table, "twist_gauge", "uniform")))),
        mps_period=begin
            value = table_value(model_table, "mps_period", nothing)
            value === nothing ? nothing : Int(value)
        end,
    )

    optimizer_table = required_value(raw, "optimizer", "root")
    optimizer = OptimizerSettings(
        maxdim=Int(required_value(optimizer_table, "maxdim", "optimizer")),
        cutoff=Float64(table_value(optimizer_table, "cutoff", 1e-10)),
        residual_tol=Float64(table_value(optimizer_table, "residual_tol", 1e-8)),
        max_iterations=Int(table_value(optimizer_table, "max_iterations", 100)),
        max_growth_steps=Int(table_value(optimizer_table, "max_growth_steps", 16)),
        solver_tol_scale=Float64(table_value(optimizer_table, "solver_tol_scale", 100.0)),
        solver_tol_floor=Float64(table_value(optimizer_table, "solver_tol_floor", 1e-10)),
        multisite_update_alg=String(table_value(optimizer_table, "multisite_update_alg", "sequential")),
        require_converged=Bool(table_value(optimizer_table, "require_converged", true)),
        divergence_patience=Int(table_value(optimizer_table, "divergence_patience", 8)),
        divergence_factor=Float64(table_value(optimizer_table, "divergence_factor", 4.0)),
    )

    scan_table = required_value(raw, "scan", "root")
    fluxes = Float64.(required_value(scan_table, "fluxes_over_pi", "scan"))
    validate_flux_order(fluxes)
    initial_state_file = resolve_config_path(
        absolute_config,
        table_value(scan_table, "initial_state_file", nothing),
    )
    scan = ScanSettings(
        branch=String(required_value(scan_table, "branch", "scan")),
        fluxes_over_pi=fluxes,
        seed_pattern=String(table_value(scan_table, "seed_pattern", "alternating")),
        random_seed=Int(table_value(scan_table, "random_seed", 1)),
        adaptive_bisection=Bool(table_value(scan_table, "adaptive_bisection", true)),
        minimum_step_over_pi=Float64(table_value(scan_table, "minimum_step_over_pi", 1 / 64)),
        save_rejected=Bool(table_value(scan_table, "save_rejected", true)),
        initial_state_file=initial_state_file,
    )

    spectrum_table = table_value(raw, "spectrum", Dict{String,Any}())
    spectrum = SpectrumSettings(
        physical_sz_sectors=Float64.(table_value(spectrum_table, "physical_sz_sectors", [0.0, 1.0])),
        neigs=Int(table_value(spectrum_table, "neigs", 16)),
        tolerance=Float64(table_value(spectrum_table, "tolerance", 1e-10)),
        krylov_dimension=Int(table_value(spectrum_table, "krylov_dimension", 40)),
        random_seed=Int(table_value(spectrum_table, "random_seed", 1)),
    )

    runtime_table = required_value(raw, "runtime", "root")
    output_directory = resolve_config_path(
        absolute_config,
        required_value(runtime_table, "output_directory", "runtime"),
    )
    runtime = RuntimeSettings(
        output_directory=output_directory,
        blas_threads=Int(table_value(runtime_table, "blas_threads", 1)),
        strided_threads=Int(table_value(runtime_table, "strided_threads", 1)),
        threaded_blocksparse=Bool(table_value(runtime_table, "threaded_blocksparse", false)),
        output_level=Int(table_value(runtime_table, "output_level", 1)),
    )

    optimizer.maxdim >= 2 || throw(ArgumentError("optimizer.maxdim must be at least 2"))
    optimizer.max_iterations >= 1 || throw(ArgumentError("optimizer.max_iterations must be positive"))
    optimizer.max_growth_steps >= 1 ||
        throw(ArgumentError("optimizer.max_growth_steps must be positive"))
    optimizer.cutoff > 0 || throw(ArgumentError("optimizer.cutoff must be positive"))
    optimizer.solver_tol_scale > 0 ||
        throw(ArgumentError("optimizer.solver_tol_scale must be positive"))
    optimizer.solver_tol_floor > 0 ||
        throw(ArgumentError("optimizer.solver_tol_floor must be positive"))
    optimizer.divergence_patience >= 1 || throw(ArgumentError("divergence_patience must be positive"))
    optimizer.divergence_factor > 1 || throw(ArgumentError("divergence_factor must exceed one"))
    optimizer.residual_tol > 0 || throw(ArgumentError("optimizer.residual_tol must be positive"))
    all(isfinite, (model.J1, model.J2, model.Delta1, model.Delta2, model.Bz)) ||
        throw(ArgumentError("model couplings must be finite"))
    model.twist_gauge in (:uniform, :seam) ||
        throw(ArgumentError("model.twist_gauge must be 'uniform' or 'seam'"))
    model_mps_period(model)
    isempty(strip(scan.branch)) && throw(ArgumentError("scan.branch cannot be empty"))
    scan.minimum_step_over_pi > 0 || throw(ArgumentError("minimum_step_over_pi must be positive"))
    isempty(spectrum.physical_sz_sectors) &&
        throw(ArgumentError("at least one physical Sz sector is required"))
    length(unique(spectrum.physical_sz_sectors)) == length(spectrum.physical_sz_sectors) ||
        throw(ArgumentError("physical Sz sectors contain duplicates"))
    all(
        value -> isfinite(value) && isapprox(2 * value, round(2 * value); atol=1e-12, rtol=0),
        spectrum.physical_sz_sectors,
    ) || throw(ArgumentError("each physical Sz sector must be an integer or half-integer"))
    spectrum.neigs >= 1 || throw(ArgumentError("spectrum.neigs must be positive"))
    spectrum.tolerance > 0 || throw(ArgumentError("spectrum.tolerance must be positive"))
    spectrum.krylov_dimension > spectrum.neigs ||
        throw(ArgumentError("spectrum.krylov_dimension must exceed spectrum.neigs"))
    runtime.blas_threads >= 1 || throw(ArgumentError("runtime.blas_threads must be positive"))
    runtime.strided_threads >= 1 ||
        throw(ArgumentError("runtime.strided_threads must be positive"))
    runtime.output_level >= 0 || throw(ArgumentError("runtime.output_level cannot be negative"))

    return ProjectSettings(
        model=model,
        optimizer=optimizer,
        scan=scan,
        spectrum=spectrum,
        runtime=runtime,
        config_path=absolute_config,
        config_text=read(absolute_config, String),
    )
end
