# File iteration
Tables.rowaccess(::Type{<:File}) = true
Tables.rows(f::File) = f

struct Row
    file::File
    row::Int
end

getfile(r::Row) = getfield(r, :file)
getrow(r::Row) = getfield(r, :row)

Base.propertynames(r::Row) = getnames(getfile(r))

function Base.show(io::IO, r::Row)
    println(io, "CSV.Row($(getrow(r))) of:")
    show(io, getfile(r))
end

Base.eltype(f::File) = Row
Base.length(f::File) = getrows(f)

@inline function Base.iterate(f::File, st=1)
    st > length(f) && return nothing
    return Row(f, st), st + 1
end

@noinline badcolumnerror(name) = throw(ArgumentError("`$name` is not a valid column name"))

@inline function Base.getproperty(row::Row, name::Symbol)
    f = getfile(row)
    i = findfirst(x->x===name, getnames(f))
    i === nothing && badcolumnerror(name)
    return getcell(f, gettypes(f)[i], i, getrow(row))
end

@inline Base.getproperty(row::Row, ::Type{T}, col::Int, name::Symbol) where {T} =
    getcell(getfile(row), T, col, getrow(row))

# internal method for getting a cell value
@inline function getcell(f::File, ::Type{T}, col::Int, row::Int) where {T}
    indexoffset = ((getcols(f) * (row - 1) * 2) + (col - 1) * 2) + 1
    offlen = gettape(f)[indexoffset]
    missingvalue(offlen) && return missing
    return getvalue(Base.nonmissingtype(T), f, indexoffset, offlen, col)
end

getvalue(::Type{Int64}, f, indexoffset, offlen, col) = int64(gettape(f)[indexoffset + 1])
function getvalue(::Type{Float64}, f, indexoffset, offlen, col)
    @inbounds x = gettape(f)[indexoffset + 1]
    return intvalue(offlen) ? Float64(int64(x)) : float64(x)
end
getvalue(::Type{Date}, f, indexoffset, offlen, col) = date(gettape(f)[indexoffset + 1])
getvalue(::Type{DateTime}, f, indexoffset, offlen, col) = datetime(gettape(f)[indexoffset + 1])
getvalue(::Type{Bool}, f, indexoffset, offlen, col) = bool(gettape(f)[indexoffset + 1])
getvalue(::Type{Missing}, f, indexoffset, offlen, col) = missing

function getvalue(::Type{PooledString}, f, indexoffset, offlen, col)
    @inbounds x = gettape(f)[indexoffset + 1]
    str = getrefs(f)[col][x]
    return str
end

function getvalue(::Type{String}, f, indexoffset, offlen, col)
    s = PointerString(pointer(getbuf(f), getpos(offlen)), getlen(offlen))
    return escapedvalue(offlen) ? unescape(s, gete(f)) : String(s)
end