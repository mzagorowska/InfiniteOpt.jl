# Define symbol input
const Parameter = :Parameter

# Extend Base.copy for new variable types
Base.copy(v::ParameterRef, new_model::InfiniteModel) = ParameterRef(new_model, v.index)

mutable struct _ParameterInfoExpr
    has_lb::Bool
    lower_bound::Any
    has_ub::Bool
    upper_bound::Any
    has_dist::Bool
    distribution::Any
    has_set::Bool
    set::Any
end

function _is_param_keyword(kw::Expr)
    return kw.args[1] in [:set, :lower_bound, :upper_bound, :distribution]
end

function _ParameterInfoExpr(; lower_bound=NaN, upper_bound=NaN, distribution=NaN, set=NaN)
    # isnan(::Expr) is not defined so we need to do !== NaN
    _ParameterInfoExpr(lower_bound !== NaN, lower_bound, upper_bound !== NaN, upper_bound, distribution !== NaN, distribution, set !== NaN, set)
end

function JuMP._set_lower_bound_or_error(_error::Function, info::_ParameterInfoExpr, lower)
    info.has_lb && _error("Cannot specify parameter lower_bound twice")
    info.has_dist && _error("Cannot specify parameter lower_bound and distribution")
    info.has_set && _error("Cannot specify parameter lower_bound and set")
    info.has_lb = true
    info.lower_bound = convert(Float64, lower)
end

function JuMP._set_upper_bound_or_error(_error::Function, info::_ParameterInfoExpr, upper)
    info.has_ub && _error("Cannot specify parameter upper_bound twice")
    info.has_dist && _error("Cannot specify parameter upper_bound and distribution")
    info.has_set && _error("Cannot specify parameter upper_bound and set")
    info.has_ub = true
    info.upper_bound = convert(Float64, upper)
end

function _dist_or_error(_error::Function, info::_ParameterInfoExpr, dist)
    info.has_dist && _error("Cannot specify parameter distribution twice")
    (info.has_lb || info.has_ub) && _error("Cannot specify parameter distribution and upper/lower bounds")
    info.has_set && _error("Cannot specify parameter distribution and set")
    info.has_dist = true
    info.distribution = dist
end

function _set_or_error(_error::Function, info::_ParameterInfoExpr, set)
    info.has_set && _error("Cannot specify variable fixed value twice")
    (info.has_lb || info.has_ub) && _error("Cannot specify parameter set and upper/lower bounds")
    info.has_dist && _error("Cannot specify parameter set and distribution")
    info.has_set = true
    info.set = set
end

function _constructor_set(_error::Function, info::_ParameterInfoExpr)
    if (info.has_lb || info.has_ub) && !(info.has_lb && info.has_ub)
        _error("Must specify both an upper bound and a lower bound")
    elseif info.has_lb
        if !(typeof(info.lower_bound) <: Number)
            _error("Bounds must be a number.")
        end
        return :(IntervalSet(convert(Float64, $(info.lower_bound)), convert(Float64, $(info.upper_bound))))
    elseif info.has_dist
        check = :(typeof($(info.distribution)) <: Distributions.NonMatrixDistribution)
        return :($(check) ? DistributionSet($(info.distribution)) : error("Distribution must be a subtype of Distributions.NonMatrixDistribution."))
    elseif info.has_set
        check = :(typeof($(info.set)) <: AbstractInfiniteSet)
        return :($(check) ? $(info.set) : error("Set must be a subtype of AbstractInfiniteSet."))
    else
        _error("Must specify upper/lower bounds, a distribution, or a set")
    end
end

"""
    build_parameter(_error::Function, set::AbstractInfiniteSet, extra_kw_args...)
Build an infinite parameter to the model in a manner similar to `JuMP.build_variable`.
"""
function build_parameter(_error::Function, set::AbstractInfiniteSet, extra_kw_args...)
    for (kwarg, _) in extra_kw_args
        _error("Unrecognized keyword argument $kwarg")
    end
    return InfOptParameter(set)
end

"""
    add_parameter(model::InfiniteModel, v::InfOptParameter, name::String="")
Add an infinite parameter to the model in a manner similar to `JuMP.add_variable`.
"""
function add_parameter(model::InfiniteModel, v::InfOptParameter, name::String="")
    model.next_param_index += 1
    pref = ParameterRef(model, model.next_param_index)
    model.params[pref.index] = v
    JuMP.set_name(pref, name)
    return pref
end

"""
    JuMP.delete(model::InfiniteModel, pref::ParameterRef)
Extend the `JuMP.delete` function to accomodate infinite parameters
"""
function JuMP.delete(model::InfiniteModel, pref::ParameterRef)
    @assert JuMP.is_valid(model, pref)
    delete!(model.params, JuMP.index(pref))
    delete!(model.param_to_name, JuMP.index(pref))
    return
end

"""
    JuMP.is_valid(model::InfiniteModel, pref::ParameterRef)
Extend the `JuMP.is_valid` function to accomodate infinite parameters.
"""
function JuMP.is_valid(model::InfiniteModel, pref::ParameterRef)
        return (model === JuMP.owner_model(pref) && JuMP.index(pref) in keys(model.params))
end

"""
    JuMP.name(pref::ParameterRef)
Extend the `JuMP.name` function to accomodate infinite parameters
"""
JuMP.name(pref::ParameterRef) = JuMP.owner_model(pref).param_to_name[JuMP.index(pref)]

"""
    JuMP.set_name(pref::ParameterRef, name::String)
Extend the `JuMP.set_name` function to accomodate infinite parameters.
"""
function JuMP.set_name(pref::ParameterRef, name::String)
    JuMP.owner_model(pref).param_to_name[JuMP.index(pref)] = name
    JuMP.owner_model(pref).name_to_param = nothing
    return
end

"""
    num_parameters(model::InfiniteModel)
Return the number of infinite parameters.
"""
num_parameters(model::InfiniteModel) = length(model.params)

# Internal functions
_parameter_set(pref::ParameterRef) = JuMP.owner_model(pref).params[JuMP.index(pref)].set
function _update_parameter_set(pref::ParameterRef, set::AbstractInfiniteSet)
    JuMP.owner_model(pref).params[JuMP.index(pref)] = InfOptParameter(set)
    return
end

"""
    infinite_set(pref::ParameterRef)::AbstractInfiniteSet
Return the infinite set of `pref`.
"""
function infinite_set(pref::ParameterRef)::AbstractInfiniteSet
    return _parameter_set(pref)
end

"""
    set_infinite_set(pref::ParameterRef, set::AbstractInfiniteSet)
Specify the infinite set of `pref`.
"""
function set_infinite_set(pref::ParameterRef, set::AbstractInfiniteSet)
    _update_parameter_set(pref, set)
    return
end

"""
    JuMP.has_lower_bound(pref::ParameterRef)
Extend the `JuMP.has_lower_bound` function to accomodate infinite parameters.
"""
function JuMP.has_lower_bound(pref::ParameterRef)
    set = _parameter_set(pref)
    if isa(set, IntervalSet)
        return true
    elseif isa(set, DistributionSet)
        if typeof(set.distribution) <: Distributions.UnivariateDistribution
            return true
        else
            error("Only parameters with univariate distributions have well-defined lower bounds.")
        end
    else
        type = typeof(set)
        error("Undefined infinite set type $type for lower bound checking.")
    end
end

"""
    JuMP.lower_bound(pref::ParameterRef)::Number
Extend the `JuMP.lower_bound` function to accomodate infinite parameters.
"""
function JuMP.lower_bound(pref::ParameterRef)::Number
    set = _parameter_set(pref)
    if !JuMP.has_lower_bound(pref)
        error("Parameter $(pref) does not have a lower bound.")
    end
    if isa(set, IntervalSet)
        return set.lower_bound
    else isa(set, DistributionSet)
        if typeof(set.distribution) <: Distributions.UnivariateDistribution
            return Distributions.minimum(set.distribution)
        end
    end
end

"""
    JuMP.set_lower_bound(pref::ParameterRef, lower::Number)
Extend the `JuMP.set_lower_bound` function to accomodate infinite parameters.
"""
function JuMP.set_lower_bound(pref::ParameterRef, lower::Number)
    set = _parameter_set(pref)
    if isa(set, DistributionSet)
        error("Cannot set the lower bound of a distribution, try using `Distributions.Truncated` instead.")
    elseif !isa(set, IntervalSet)
        error("Parameter $(pref) is not an interval set.")
    end
    _update_parameter_set(pref, IntervalSet(Float64(lower), set.upper_bound))
    return
end

"""
    JuMP.has_upper_bound(pref::ParameterRef)
Extend the `JuMP.has_upper_bound` function to accomodate infinite parameters.
"""
function JuMP.has_upper_bound(pref::ParameterRef)
    set = _parameter_set(pref)
    if isa(set, IntervalSet)
        return true
    elseif isa(set, DistributionSet)
        if typeof(set.distribution) <: Distributions.UnivariateDistribution
            return true
        else
            error("Only parameters with univariate distributions have well-defined upper bounds.")
        end
    else
        type = typeof(set)
        error("Undefined infinite set type $type for lower upper checking.")
    end
end

"""
    JuMP.upper_bound(pref::ParameterRef)::Number
Extend the `JuMP.upper_bound` function to accomodate infinite parameters.
"""
function JuMP.upper_bound(pref::ParameterRef)::Number
    set = _parameter_set(pref)
    if !JuMP.has_upper_bound(pref)
        error("Parameter $(pref) does not have a upper bound.")
    end
    if isa(set, IntervalSet)
        return set.upper_bound
    else isa(set, DistributionSet)
        if typeof(set.distribution) <: Distributions.UnivariateDistribution
            return Distributions.maximum(set.distribution)
        end
    end
end

"""
    JuMP.set_upper_bound(pref::ParameterRef, lower::Number)
Extend the `JuMP.set_upper_bound` function to accomodate infinite parameters.
"""
function JuMP.set_upper_bound(pref::ParameterRef, upper::Number)
    set = _parameter_set(pref)
    if isa(set, DistributionSet)
        error("Cannot set the upper bound of a distribution, try using `Distributions.Truncated` instead.")
    elseif !isa(set, IntervalSet)
        error("Parameter $(pref) is not an interval set.")
    end
    _update_parameter_set(pref, IntervalSet(set.lower_bound, Float64(upper)))
    return
end

"""
    parameter_by_name(model::InfiniteModel, name::String)
Return the parameter reference assoociated with a parameter.
"""
function parameter_by_name(model::InfiniteModel, name::String)
    if model.name_to_param === nothing
        # Inspired from MOI/src/Utilities/model.jl
        model.name_to_param = Dict{String, Int}()
        for (param, param_name) in model.param_to_name
            if haskey(model.name_to_param, param_name)
                # -1 is a special value that means this string does not map to
                # a unique variable name.
                model.name_to_param[param_name] = -1
            else
                model.name_to_param[param_name] = param
            end
        end
    end
    index = get(model.name_to_param, name, nothing)
    if index isa Nothing
        return nothing
    elseif index == -1
        error("Multiple parameters have the name $name.")
    else
        return ParameterRef(model, index)
    end
    return
end

"""
    all_parameters(model::InfiniteModel)
Return all of the infinite parameters as a vector of type `ParameterRef`.
"""
function all_parameters(model::InfiniteModel)
    param_list = Vector{ParameterRef}(undef, num_parameters(model))
    indexes = sort([index for index in keys(model.params)])
    counter = 1
    for index in indexes
        param_list[counter] = ParameterRef(model, index)
        counter += 1
    end
    return param_list
end

# Define functions to extract the names of parameters
function _get_names(arr::AbstractArray{<:ParameterRef})
    if isa(arr, JuMP.Containers.SparseAxisArray)
        return [JuMP.name(arr[k]) for k in keys(arr.data)]
    else
        return [JuMP.name(arr[k]) for k in CartesianIndices(arr)]
    end
end

function _get_root_names(param_refs::Tuple)
    root_names = Vector{String}(undef, length(param_refs))
    for i = 1:length(root_names)
        if isa(param_refs[i], ParameterRef)
            root_names[i] = JuMP.name(param_refs[i])
        else
            names = _get_names(param_refs[i])
            first_bracket = findfirst(isequal('['), names[1])
            root_names[i] = names[1][1:first_bracket-1]
        end
    end
    return root_names
end

function _only_one_name(arr::AbstractArray{<:ParameterRef})
    names = _get_names(arr)
    root_names = Vector{String}(undef, length(names))
    for i = 1:length(root_names)
        first_bracket = findfirst(isequal('['), names[i])
        root_names[i] = names[i][1:first_bracket-1]
    end
    return length(unique(root_names)) == 1
end

_only_one_name(pref::ParameterRef) = true

# Make check tuple check functions
function _check_parameter_tuple(param_refs::Tuple)
    types = [typeof(param) for param in param_refs]
    num_params = length(types)
    valid_types = zeros(Bool, num_params)
    for i = 1:num_params
        if types[i] == ParameterRef || types[i] <: AbstractArray{<:ParameterRef}
            valid_types[i] = true
        end
    end
    if sum(valid_types) != num_params
        error("Invalid parameter type(s) given.")
    end
    return
end

function _check_tuple_names(param_refs::Tuple)
    valid_elements = [_only_one_name(param_refs[i]) for i = 1:length(param_refs)]
    if sum(valid_elements) != length(param_refs)
        error("Each paramter tuple element must have contain only one infinite parameter name.")
    end
    return
end
