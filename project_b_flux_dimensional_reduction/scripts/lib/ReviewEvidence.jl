module ReviewEvidence
using HDF5, SHA, Statistics, TOML
include("FileIntegrity.jl")
const ROOT = normpath(joinpath(@__DIR__,"../.."))
const PARENT_SHA = "38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803"
const CAMPAIGN = "output/science/yc8_1/primary_forward_chi1024_parallel_bridge_20260831/seed_101/chi1024"
const CANDIDATE_MANIFEST = CAMPAIGN * "/state_manifests/state_0001_theta_p0p15000000_chi1024_rejected_4e3a5f406f61.toml"
const CHECKPOINT_HASHES = ["45e5e6cf308936e35fdcf93f4d4cd909bcea4b8b71e061964b0e119ca1ddbcd7",
    "fa4d7f01dbb7e10deb1c37bab659c07a9dba60fe63ba3e3db34c705c102b3e9b"]
sha(path) = FileIntegrity.file_sha256(path)
geth(f,key,default) = haskey(f,key) ? read(f,key) : default
function u1_support(f,period)
    rows=Dict{String,Any}[]
    for cut in 1:period
        prefix="psi/C[$cut]/inds/index_1/space"
        haskey(f,"$prefix/dims") || continue
        dims=Int.(read(f,"$prefix/dims"))
        for block in eachindex(dims)
            q="$prefix/QN[$block]"
            names=String.(read(f,"$q/names")); values=Int.(read(f,"$q/vals"))
            position=findfirst(==("Sz"),names)
            isnothing(position) && continue
            push!(rows,Dict("cut"=>cut,"raw_qn_sz"=>values[position],"multiplicity"=>dims[block]))
        end
    end
    if isempty(rows) && haskey(f,"sectors/after_multiplicity")
        cuts=read(f,"sectors/cut"); labels=read(f,"sectors/qn_label")
        dims=read(f,"sectors/after_multiplicity"); weights=read(f,"sectors/after_schmidt_weight")
        for i in eachindex(cuts)
            push!(rows,Dict("cut"=>Int(cuts[i]),"qn_label"=>String(labels[i]),
                "multiplicity"=>Int(dims[i]),"schmidt_weight"=>Float64(weights[i])))
        end
    end
    rows
end
function local_project_path(path; root=ROOT)
    parts = split(replace(String(path),'\\'=>'/'), "project_b_flux_dimensional_reduction/"; limit=2)
    length(parts) == 2 || error("path has no Project B root: $path")
    startswith(String(path),"/pscratch/") && error("scratch paths cannot be mapped to the local mirror")
    normpath(joinpath(root,parts[2]))
end
function parent_path()
    m = TOML.parsefile(joinpath(ROOT,CANDIDATE_MANIFEST))
    path = local_project_path(m["parent_state_path"])
    sha(path) == PARENT_SHA || error("accepted parent hash mismatch")
    path
end
function scalars(path; verified_sha256=nothing)
    h5open(path,"r") do f
        energy = geth(f,"observables/energy_density",NaN)
        terms = Float64.(geth(f,"observables/energy_terms",Float64[]))
        entropy = Float64.(geth(f,"observables/von_neumann_entropies",Float64[]))
        theta = geth(f,"theta_over_pi",NaN)
        parent_theta = geth(f,"continuation/parent_theta_over_pi",NaN)
        overlap = geth(f,"continuation/overlap_per_site",NaN)
        checked = geth(f,"continuation/continuity_checked",false)
        delta = pi*(theta-parent_theta)
        fidelity = checked && isfinite(overlap) && 0 < overlap <= 1 && isfinite(delta) && delta != 0 ?
            -2log(overlap)/delta^2 : NaN
        Dict{String,Any}("path"=>path,"sha256"=>isnothing(verified_sha256) ? sha(path) : verified_sha256,
            "artifact_kind"=>geth(f,"artifact_kind","unknown"),
            "parent_sha256"=>geth(f,"continuation/parent_state_sha256",geth(f,"lineage/parent_state_sha256","")),
            "branch"=>geth(f,"branch","unknown"), "theta_over_pi"=>theta,
            "chi"=>geth(f,"observables/maxlinkdim",0),
            "period"=>geth(f,"geometry/mps_period",length(terms)),
            "accepted"=>geth(f,"continuation_accepted",false),
            "energy_density"=>energy,"energy_terms"=>terms,
            "dimerization"=>length(terms)==2 ? abs(terms[1]-terms[2]) : NaN,
            "entropy_by_cut"=>entropy,"mean_entropy"=>isempty(entropy) ? NaN : mean(entropy),
            "maximum_entropy"=>isempty(entropy) ? NaN : maximum(entropy),
            "magnetization_z"=>Float64.(geth(f,"observables/magnetization_z",Float64[])),
            "vumps_projected_residual"=>geth(f,"optimizer/residual",NaN),
            "iteration"=>geth(f,"optimizer/iterations",0),
            "continuity_checked"=>checked,"continuity_passed"=>geth(f,"continuation/continuity_passed",false),
            "overlap_per_site"=>overlap,"finite_step_fidelity_susceptibility_per_radian2"=>fidelity,
            "correlation_lengths_transfer_cells"=>Float64.(geth(f,"continuation/candidate_correlation_lengths",Float64[])),
            "correlation_length_sectors"=>Float64.(geth(f,"continuation/correlation_length_physical_sz_sectors",Float64[])),
            "spectrum_present"=>haskey(f,"observables/schmidt_probabilities"),
            "u1_support"=>u1_support(f,Int(geth(f,"geometry/mps_period",length(terms)))),
            "u1_support_basis"=>"raw virtual QN labels and multiplicities; no tensor payload loaded")
    end
end
function write_toml(path, data)
    ispath(path) && error("refusing to overwrite $path")
    mkpath(dirname(path))
    tmp=path*".tmp"
    ispath(tmp) && error("stale temporary $tmp")
    open(io->TOML.print(io,data;sorted=true),tmp,"w")
    mv(tmp,path)
end
function trend(values)
    length(values)>=2 && all(x->isfinite(x)&&x>0,values) || error("invalid residual series")
    x = collect(1:length(values)); y=log.(values)
    slope = sum((x.-mean(x)).*(y.-mean(y)))/sum(abs2,x.-mean(x))
    fitted=mean(y).+slope.*(x.-mean(x))
    ss=sum(abs2,y.-mean(y))
    (; slope, r_squared=ss==0 ? 1.0 : 1-sum(abs2,y.-fitted)/ss)
end
end
