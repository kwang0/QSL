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
    solver_krylov_dimension::Int = 30
    solver_max_iterations::Int = 100
    record_krylov_diagnostics::Bool = false
    multisite_update_alg::String = "sequential"
    require_converged::Bool = true
    divergence_patience::Int = 8
    divergence_factor::Float64 = 4.0
    plateau_detection::Bool = false
    plateau_warmup_iterations::Int = 30
    plateau_patience::Int = 24
    plateau_min_relative_improvement::Float64 = 5e-3
end

Base.@kwdef struct ScanSettings
    branch::String
    preparation::String = "default"
    direction::Symbol = :forward
    lineage_policy::Symbol = :compatible
    fluxes_over_pi::Vector{Float64}
    seed_pattern::String = "alternating"
    random_seed::Int = 1
    adaptive_bisection::Bool = true
    minimum_step_over_pi::Float64 = 1 / 64
    save_rejected::Bool = true
    require_parent_overlap::Bool = false
    minimum_parent_overlap_per_site::Float64 = 0.99
    parent_overlap_tolerance::Float64 = 1e-8
    parent_overlap_krylov_dimension::Int = 16
    initial_state_file::Union{Nothing,String} = nothing
    initial_state_sha256::Union{Nothing,String} = nothing
end

function inferred_scan_direction(fluxes::AbstractVector{<:Real})
    length(fluxes) == 1 && return :stationary
    return last(fluxes) > first(fluxes) ? :forward : :reverse
end

function validate_scan_direction(direction::Symbol, fluxes::AbstractVector{<:Real})
    direction in (:forward, :reverse, :stationary) || throw(
        ArgumentError("scan.direction must be 'forward', 'reverse', or 'stationary'"),
    )
    if direction === :stationary
        length(fluxes) == 1 || throw(
            ArgumentError("a stationary scan must contain exactly one flux"),
        )
    elseif length(fluxes) > 1
        differences = diff(fluxes)
        expected = direction === :forward ? all(>(0), differences) : all(<(0), differences)
        expected || throw(
            ArgumentError("scan.direction='$direction' disagrees with the flux ordering"),
        )
    end
    return true
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
        solver_krylov_dimension=Int(table_value(
            optimizer_table,
            "solver_krylov_dimension",
            30,
        )),
        solver_max_iterations=Int(table_value(
            optimizer_table,
            "solver_max_iterations",
            100,
        )),
        record_krylov_diagnostics=Bool(table_value(
            optimizer_table,
            "record_krylov_diagnostics",
            false,
        )),
        multisite_update_alg=String(table_value(optimizer_table, "multisite_update_alg", "sequential")),
        require_converged=Bool(table_value(optimizer_table, "require_converged", true)),
        divergence_patience=Int(table_value(optimizer_table, "divergence_patience", 8)),
        divergence_factor=Float64(table_value(optimizer_table, "divergence_factor", 4.0)),
        plateau_detection=Bool(table_value(optimizer_table, "plateau_detection", false)),
        plateau_warmup_iterations=Int(table_value(
            optimizer_table,
            "plateau_warmup_iterations",
            30,
        )),
        plateau_patience=Int(table_value(optimizer_table, "plateau_patience", 24)),
        plateau_min_relative_improvement=Float64(table_value(
            optimizer_table,
            "plateau_min_relative_improvement",
            5e-3,
        )),
    )

    scan_table = required_value(raw, "scan", "root")
    fluxes = Float64.(required_value(scan_table, "fluxes_over_pi", "scan"))
    validate_flux_order(fluxes)
    direction = Symbol(lowercase(String(table_value(
        scan_table,
        "direction",
        string(inferred_scan_direction(fluxes)),
    ))))
    validate_scan_direction(direction, fluxes)
    initial_state_file = resolve_config_path(
        absolute_config,
        table_value(scan_table, "initial_state_file", nothing),
    )
    initial_state_sha256 = begin
        value = table_value(scan_table, "initial_state_sha256", nothing)
        value === nothing ? nothing : lowercase(String(value))
    end
    scan = ScanSettings(
        branch=String(required_value(scan_table, "branch", "scan")),
        preparation=String(table_value(scan_table, "preparation", "default")),
        direction=direction,
        lineage_policy=Symbol(lowercase(String(table_value(
            scan_table,
            "lineage_policy",
            "compatible",
        )))),
        fluxes_over_pi=fluxes,
        seed_pattern=String(table_value(scan_table, "seed_pattern", "alternating")),
        random_seed=Int(table_value(scan_table, "random_seed", 1)),
        adaptive_bisection=Bool(table_value(scan_table, "adaptive_bisection", true)),
        minimum_step_over_pi=Float64(table_value(scan_table, "minimum_step_over_pi", 1 / 64)),
        save_rejected=Bool(table_value(scan_table, "save_rejected", true)),
        require_parent_overlap=Bool(table_value(scan_table, "require_parent_overlap", false)),
        minimum_parent_overlap_per_site=Float64(table_value(
            scan_table,
            "minimum_parent_overlap_per_site",
            0.99,
        )),
        parent_overlap_tolerance=Float64(table_value(
            scan_table,
            "parent_overlap_tolerance",
            1e-8,
        )),
        parent_overlap_krylov_dimension=Int(table_value(
            scan_table,
            "parent_overlap_krylov_dimension",
            16,
        )),
        initial_state_file=initial_state_file,
        initial_state_sha256=initial_state_sha256,
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
    optimizer.solver_krylov_dimension >= 4 || throw(ArgumentError(
        "optimizer.solver_krylov_dimension must be at least 4",
    ))
    optimizer.solver_max_iterations >= 1 || throw(ArgumentError(
        "optimizer.solver_max_iterations must be positive",
    ))
    optimizer.divergence_patience >= 1 || throw(ArgumentError("divergence_patience must be positive"))
    optimizer.divergence_factor > 1 || throw(ArgumentError("divergence_factor must exceed one"))
    optimizer.plateau_warmup_iterations >= 2 || throw(ArgumentError(
        "optimizer.plateau_warmup_iterations must be at least 2",
    ))
    optimizer.plateau_patience >= 2 || throw(ArgumentError(
        "optimizer.plateau_patience must be at least 2",
    ))
    0 < optimizer.plateau_min_relative_improvement < 1 || throw(ArgumentError(
        "optimizer.plateau_min_relative_improvement must lie in (0, 1)",
    ))
    optimizer.residual_tol > 0 || throw(ArgumentError("optimizer.residual_tol must be positive"))
    all(isfinite, (model.J1, model.J2, model.Delta1, model.Delta2, model.Bz)) ||
        throw(ArgumentError("model couplings must be finite"))
    model.twist_gauge in (:uniform, :seam) ||
        throw(ArgumentError("model.twist_gauge must be 'uniform' or 'seam'"))
    model_mps_period(model)
    isempty(strip(scan.branch)) && throw(ArgumentError("scan.branch cannot be empty"))
    isempty(strip(scan.preparation)) && throw(ArgumentError("scan.preparation cannot be empty"))
    scan.lineage_policy in (:compatible, :strict) || throw(
        ArgumentError("scan.lineage_policy must be 'compatible' or 'strict'"),
    )
    validate_scan_direction(scan.direction, scan.fluxes_over_pi)
    scan.minimum_step_over_pi > 0 || throw(ArgumentError("minimum_step_over_pi must be positive"))
    0 < scan.minimum_parent_overlap_per_site <= 1 || throw(ArgumentError(
        "minimum_parent_overlap_per_site must lie in (0, 1]",
    ))
    scan.parent_overlap_tolerance > 0 || throw(ArgumentError(
        "parent_overlap_tolerance must be positive",
    ))
    scan.parent_overlap_krylov_dimension >= 4 || throw(ArgumentError(
        "parent_overlap_krylov_dimension must be at least 4",
    ))
    if scan.initial_state_file === nothing
        scan.initial_state_sha256 === nothing || throw(ArgumentError(
            "initial_state_sha256 requires initial_state_file",
        ))
    else
        scan.initial_state_sha256 === nothing || occursin(
            r"^[0-9a-f]{64}$",
            scan.initial_state_sha256,
        ) || throw(ArgumentError("initial_state_sha256 must contain 64 hexadecimal digits"))
        if scan.lineage_policy === :strict
            scan.initial_state_sha256 === nothing && throw(ArgumentError(
                "strict restart lineage requires initial_state_sha256",
            ))
        end
    end
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
