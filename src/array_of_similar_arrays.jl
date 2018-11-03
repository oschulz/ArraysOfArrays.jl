# This file is a part of ArraysOfArrays.jl, licensed under the MIT License (MIT).

"""
    AbstractArrayOfSimilarArrays{T,M,N} <: AbstractArray{<:AbstractArray{T,M},N}

An array that contains arrays that have the same size/axes. The array is
internally stored in flattened form as some kind of array of dimension
`M + N`. The flattened form can be accessed via `parent(A)`.

Subtypes must implement (in addition to typical array operations):

    parent(A::SomeArrayOfSimilarArrays)::AbstractArray{T,M+N}

The following type aliases are defined:

* `AbstractVectorOfSimilarArrays{T,M} = AbstractArrayOfSimilarArrays{T,M,1}`
* `AbstractArrayOfSimilarVectors{T,N} = AbstractArrayOfSimilarArrays{T,1,N}`
* `AbstractVectorOfSimilarVectors{T} = AbstractArrayOfSimilarArrays{T,1,1}`
"""
abstract type AbstractArrayOfSimilarArrays{T,M,N} <: AbstractArray{Array{T,M},N} end
export AbstractArrayOfSimilarArrays

const AbstractVectorOfSimilarArrays{T,M} = AbstractArrayOfSimilarArrays{T,M,1}
export AbstractVectorOfSimilarArrays

const AbstractArrayOfSimilarVectors{T,N} = AbstractArrayOfSimilarArrays{T,1,N}
export AbstractArrayOfSimilarVectors

const AbstractVectorOfSimilarVectors{T} = AbstractArrayOfSimilarArrays{T,1,1}
export AbstractVectorOfSimilarVectors



"""
    ArrayOfSimilarArrays{T,M,N,L,P} <: AbstractArrayOfSimilarArrays{T,M,N}

Represents a view of an array of dimension `L = M + N` as an array of
dimension M with elements that are arrays with dimension N. All element arrays
implicitly have equal size/axes.

Constructors:

    ArrayOfSimilarArrays{N}(parent::AbstractArray)

The following type aliases are defined:

* `VectorOfSimilarArrays{T,M} = AbstractArrayOfSimilarArrays{T,M,1}`
* `ArrayOfSimilarVectors{T,N} = AbstractArrayOfSimilarArrays{T,1,N}`
* `VectorOfSimilarVectors{T} = AbstractArrayOfSimilarArrays{T,1,1}`

`VectorOfSimilarArrays` supports `push!()`, etc., provided the underlying
array supports resizing of it's last dimension (e.g. an `ElasticArray`).
"""
struct ArrayOfSimilarArrays{
    T, M, N, L,
    P<:AbstractArray{T,L}
} <: AbstractArrayOfSimilarArrays{T,M,N}
    data::P

    function ArrayOfSimilarArrays{T,M,N}(parent::AbstractArray{U,L}) where {T,M,N,L,U}
        size_inner, size_outer = split_tuple(size(parent), Val{M}())
        require_ndims(parent, _add_vals(Val{M}(), Val{N}()))
        conv_parent = _convert_elype(T, parent)
        P = typeof(conv_parent)
        new{T,M,N,L,P}(conv_parent)
    end
end

export ArrayOfSimilarArrays

function ArrayOfSimilarArrays{T,M,N}(A::AbstractArray{<:AbstractArray{U,M},N}) where {T,M,N,U}
    B = ArrayOfSimilarArrays{T,M,N}(Array{T}(undef, _size_inner(A)..., size(A)...))
    copyto!(B, A)
end

ArrayOfSimilarArrays{T}(A::AbstractArray{<:AbstractArray{U,M},N}) where {T,M,N,U} =
    ArrayOfSimilarArrays{T,M,N}(A)

ArrayOfSimilarArrays(A::AbstractArray{<:AbstractArray{T,M},N}) where {T,M,N} =
    ArrayOfSimilarArrays{T,M,N}(A)


@static if VERSION < v"0.7.0-DEV.3138"
    Base.convert(R::Type{ArrayOfSimilarArrays{T,M,N}}, parent::AbstractArray{U,L}) where {T,M,N,L,U} = R(parent)

    Base.convert(R::Type{ArrayOfSimilarArrays{T,M,N}}, A::AbstractArray{<:AbstractArray{U,M},N}) where {T,M,N,U} = R(A)
    Base.convert(R::Type{ArrayOfSimilarArrays{T}}, A::AbstractArray{<:AbstractArray{U,M},N}) where {T,M,N,U} = R(A)
    Base.convert(R::Type{ArrayOfSimilarArrays}, A::AbstractArray{<:AbstractArray{T,M},N}) where {T,M,N} = R(A)
end


function _size_inner(A::AbstractArray{<:AbstractArray{T,M},N}) where {T,M,N}
    s = if !isempty(A)
        sz_A = size(A[1])
        ntuple(i -> Int(sz_A[i]), Val(M))
    else
        ntuple(_ -> zero(Int), Val(M))
    end

    all(X -> size(X) == s, A) || throw(DimensionMismatch("Shape of element arrays of A is not equal, can't determine common shape"))
    s
end

function _size_inner(A::ArrayOfSimilarArrays{T,M,N}) where {T,M,N}
    sz_inner, sz_outer = split_tuple(size(A.data), Val{M}())
    sz_inner
end


import Base.==
(==)(A::ArrayOfSimilarArrays{T,M,N}, B::ArrayOfSimilarArrays{T,M,N}) where {T,M,N} =
    (A.data == B.data)


Base.parent(A::ArrayOfSimilarArrays) = A.data


Base.size(A::ArrayOfSimilarArrays{T,M,N}) where {T,M,N} = split_tuple(size(A.data), Val{M}())[2]


Base.IndexStyle(A::ArrayOfSimilarArrays) = IndexLinear()


Base.@propagate_inbounds function Base.getindex(A::ArrayOfSimilarArrays{T,M,N}, idxs::Vararg{Integer,N}) where {T,M,N}
    @boundscheck checkbounds(A, idxs...)
    J = Base.to_indices(A.data, (_ncolons(Val{M}())..., idxs...))
    @boundscheck checkbounds(A.data, J...)
    Base.unsafe_view(A.data, J...)
end

Base.@propagate_inbounds Base.setindex!(A::ArrayOfSimilarArrays{T,M,N}, x::AbstractArray{U,M}, idxs::Vararg{Integer,N}) where {T,M,N,U} =
    setindex!(A.data, x, _ncolons(Val{M}())..., idxs...)


@static if VERSION < v"0.7.0-DEV.2791"
    Base.repremptyarray(io::IO, X::ArrayOfSimilarArrays{T,M,N,L,P}) where {T,M,N,L,P} = print(io, "ArrayOfSimilarArrays{$T,$M,$N,$L,$P}(", join(size(X),','), ')')
end


@inline function Base.resize!(A::ArrayOfSimilarArrays{T,M,N}, dims::Vararg{Integer,N}) where {T,M,N}
    resize!(A.data, _size_inner(A)..., dims...)
    A
end


function Base.similar(A::ArrayOfSimilarArrays{T,M,N}, ::Type{<:AbstractArray{U}}, dims::Dims) where {T,M,N,U}
    data = A.data
    size_inner, size_outer = split_tuple(size(data), Val{M}())
    ArrayOfSimilarArrays{T,M,N}(similar(data, U, size_inner..., dims...))
end


function Base.resize!(dest::ArrayOfSimilarArrays{T,M,N}, src::ArrayOfSimilarArrays{U,M,N}) where {T,M,N,U}
    _size_inner(dest) != _size_inner(src) && throw(DimensionMismatch("Can't append, shape of element arrays of source and dest are not equal"))
    append!(dest.data, src.data)
    dest
end


function Base.append!(dest::ArrayOfSimilarArrays{T,M,N}, src::ArrayOfSimilarArrays{U,M,N}) where {T,M,N,U}
    _size_inner(dest) != _size_inner(src) && throw(DimensionMismatch("Can't append, shape of element arrays of source and dest are not equal"))
    append!(dest.data, src.data)
    dest
end

Base.append!(dest::ArrayOfSimilarArrays{T,M,N}, src::AbstractArray{<:AbstractArray{U,M},N}) where {T,M,N,U} =
    append!(dest, ArrayOfSimilarArrays(src))


function Base.prepend!(dest::ArrayOfSimilarArrays{T,M,N}, src::ArrayOfSimilarArrays{U,M,N}) where {T,M,N,U}
    _size_inner(dest) != _size_inner(src) && throw(DimensionMismatch("Can't prepend, shape of element arrays of source and dest are not equal"))
    prepend!(dest.data, src.data)
    dest
end

Base.prepend!(dest::ArrayOfSimilarArrays{T,M,N}, src::AbstractArray{<:AbstractArray{U,M},N}) where {T,M,N,U} =
    prepend!(dest, ArrayOfSimilarArrays(src))


UnsafeArrays.unsafe_uview(A::ArrayOfSimilarArrays{T,M,N}) where {T,M,N} =
    ArrayOfSimilarArrays{T,M,N}(uview(A.data))


function nestedmap2(f::Base.Callable, A::ArrayOfSimilarArrays{T,M,N}) where {T,M,N}
    new_data = map(f, A.data)
    U = eltype(new_data)
    ArrayOfSimilarArrays{U,M,N}(new_data)
end


function deepmap(f::Base.Callable, A::ArrayOfSimilarArrays{T,M,N}) where {T,M,N}
    new_data = deepmap(f, A.data)
    U = eltype(new_data)
    ArrayOfSimilarArrays{U,M,N}(new_data)
end



const VectorOfSimilarArrays{
    T, M, L,
    P<:AbstractArray{T,L}
} = ArrayOfSimilarArrays{T,M,1,L,P}

export VectorOfSimilarArrays

VectorOfSimilarArrays{T}(parent::AbstractArray{U,L}) where {T,U,L} =
    ArrayOfSimilarArrays{T,length(Base.front(size(parent))),1}(parent)

VectorOfSimilarArrays{T}(A::AbstractVector{<:AbstractArray{U,M}}) where {T,M,U} =
    VectorOfSimilarArrays{T,M}(A)

VectorOfSimilarArrays(A::AbstractVector{<:AbstractArray{T,M}}) where {T,M} =
    VectorOfSimilarArrays{T,M}(A)


@static if VERSION < v"0.7.0-DEV.3138"
    Base.convert(R::Type{VectorOfSimilarArrays{T}}, parent::AbstractArray{U,L}) where {T,U,L} = R(parent)
    Base.convert(R::Type{VectorOfSimilarArrays{T}}, A::AbstractVector{<:AbstractArray{U,M}}) where {T,M,U} = R(A)
    Base.convert(R::Type{VectorOfSimilarArrays}, A::AbstractVector{<:AbstractArray{T,M}}) where {T,M} = R(A)
end


@inline Base.IndexStyle(V::VectorOfSimilarArrays) = IndexLinear()


function Base.push!(V::VectorOfSimilarArrays{T,M}, x::AbstractArray{U,M}) where {T,M,U}
    size(x) != Base.front(size(V.data)) && throw(DimensionMismatch("Can't push, shape of source and elements of target is incompatible"))
    append!(V.data, x)
    V
end

function Base.pop!(V::VectorOfSimilarArrays)
    isempty(V) && throw(ArgumentError("array must be non-empty"))
    x = V[end]
    resize!(V, size(V, 1) - 1)
    x
end

function Base.pushfirst!(V::VectorOfSimilarArrays{T,M}, x::AbstractArray{U,M}) where {T,M,U}
    size(x) != Base.front(size(V.data)) && throw(DimensionMismatch("Can't push, shape of source and elements of target is incompatible"))
    prepend!(V.data, x)
    V
end

# Will need equivalent of resize! that resizes in front of data instead of in back:
# popfirst!(V::ArrayOfSimilarArrays) = ...



const ArrayOfSimilarVectors{
    T, N, L,
    P<:AbstractArray{T,L}
} = ArrayOfSimilarArrays{T,1,N,L,P}

export ArrayOfSimilarVectors

ArrayOfSimilarVectors{T}(parent::AbstractArray{U,L}) where {T,U,L} =
    ArrayOfSimilarArrays{T,1,length(Base.front(size(parent)))}(parent)

ArrayOfSimilarVectors{T}(A::AbstractArray{<:AbstractVector{U},N}) where {T,N,U} =
    ArrayOfSimilarVectors{T,N}(A)

ArrayOfSimilarVectors(A::AbstractArray{<:AbstractVector{T},N}) where {T,N} =
    ArrayOfSimilarVectors{T,N}(A)


@static if VERSION < v"0.7.0-DEV.3138"
    Base.convert(R::Type{ArrayOfSimilarVectors{T}}, parent::AbstractArray{U,L}) where {T,U,L} = R(parent)
    Base.convert(R::Type{ArrayOfSimilarVectors{T}}, A::AbstractArray{<:AbstractVector{U},N}) where {T,N,U} = R(A)
    Base.convert(R::Type{ArrayOfSimilarVectors}, A::AbstractArray{<:AbstractVector{T},N}) where {T,N} = R(A)
end


const VectorOfSimilarVectors{
    T,
    P<:AbstractArray{T,2}
} = ArrayOfSimilarArrays{T,1,1,2,P}

export VectorOfSimilarVectors

VectorOfSimilarVectors{T}(parent::AbstractArray{U,2}) where {T,U} =
    ArrayOfSimilarArrays{T,1,1}(parent)

VectorOfSimilarVectors(parent::AbstractArray{T,2}) where {T} =
    VectorOfSimilarVectors{T}(parent)

VectorOfSimilarVectors{T}(A::AbstractVector{<:AbstractVector{U}}) where {T,U} =
    ArrayOfSimilarArrays{T,1}(A)

VectorOfSimilarVectors(A::AbstractVector{<:AbstractVector{T}}) where {T} =
    VectorOfSimilarVectors{T}(A)

@static if VERSION < v"0.7.0-DEV.3138"
    Base.convert(R::Type{VectorOfSimilarVectors{T}}, parent::AbstractArray{U,2}) where {T,U} = R(parent)
    Base.convert(R::Type{VectorOfSimilarVectors}, parent::AbstractArray{T,2}) where {T} = R(parent)
    Base.convert(R::Type{VectorOfSimilarVectors{T}}, A::AbstractVector{<:AbstractVector{U}}) where {T,U} = R(A)
    Base.convert(R::Type{VectorOfSimilarVectors}, A::AbstractVector{<:AbstractVector{T}}) where {T} = R(A)
end
