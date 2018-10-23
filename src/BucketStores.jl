module BucketStores

export BucketStore, AbstractStorageBackend,        # Types
       createbucket!, listcontents, deletebucket!, # Buckets: create/update, read, delete
       setindex!, getindex, delete!,               # Objects: create/update, read, delete
       islocal, isbucket, isobject,                # Conveniences
       Permission,                                 # Re-exported from Authorization
       getpermission, setpermission!, setexpiry!,  # Re-exported from Authorization
       haspermission, permissions_conflict,        # Re-exported from Authorization
       @add_required_fields_backend  # Used when constructing concrete subtypes of AbstractStorageBackend


using Authorization
using Logging


# Methods that are extended in this package
import Base.setindex!, Base.getindex, Base.delete!
import Authorization.setpermission!


################################################################################
# Types 

abstract type AbstractStorageBackend end

macro add_required_fields_backend()
    return esc(:(
                 bucket_type::DataType;
                 object_type::DataType;
                ))
end


struct BucketStore{T <: AbstractStorageBackend} <: AbstractClient
    root::String  # ID of root bucket
    backend::T
    @add_required_fields_client  # From Authorization.jl: id, id2permission, idpattern2permission, type2permission

    function BucketStore(id, root, backend, id2permission, idpattern2permission, type2permission)
        m = parentmodule(typeof(backend))
        m._isobject(root) && error("Root already exists as an object. Cannot use it as a bucket.")
        newstore = new{typeof(backend)}(root, backend, id, id2permission, idpattern2permission, type2permission)
        if !m._isbucket(root)  # Root does not exist...create it
            msg = createbucket!(newstore, "")  # 2nd arg "" implies bucketname is root
            msg != nothing && @warn msg
        end
        newstore
    end
end

function BucketStore(id, root, backend)
    id2permission        = Dict{String, Permission}()
    idpattern2permission = Dict{Regex,  Permission}()
    type2permission      = Dict{DataType, Permission}()
    BucketStore(id, root, backend, id2permission, idpattern2permission, type2permission)
end


################################################################################
# Buckets

"Create bucket. If successful return nothing, else return an error message as a String."
function createbucket!(store::BucketStore, bucketname::String="")
    B = store.backend.bucket_type
    if bucketname == ""
        resourceid = store.root
    else
        resourceid = normpath(joinpath(store.root, bucketname))
        n = length(store.root)
        (length(resourceid) < n || resourceid[1:n] != store.root) && return "Cannot create a bucket outside the root bucket"
    end
    create!(store, B(resourceid))
end


"List the contents of the bucket. If successful return the value, else @warn the error message and return nothing."
function listcontents(store::BucketStore, bucketname::String="")
    B = store.backend.bucket_type
    if bucketname == ""
        resourceid = store.root
    else
        resourceid = normpath(joinpath(store.root, bucketname))
        n = length(store.root)
        if length(resourceid) < n || resourceid[1:n] != store.root
            @warn "Cannot read a bucket outside the root bucket"
            nothing
        end
    end
    ok, val = read(store, B(resourceid))
    if !ok
        @warn val
        return nothing
    end
    val
end


"Delete bucket. If successful return nothing, else return an error message as a String."
function deletebucket!(store::BucketStore, bucketname::String)
    B = store.backend.bucket_type
    if bucketname == ""
        resourceid = store.root
    else
        resourceid = normpath(joinpath(store.root, bucketname))
        n = length(store.root)
        (length(resourceid) < n || resourceid[1:n] != store.root) && return "Cannot delete a bucket outside the root bucket"
    end
    delete!(store, B(resourceid))
end


################################################################################
# Objects

"Create/update object. If successful return nothing, else return an error message as a String."
function setindex!(store::BucketStore, v, i::String)
    resourceid = normpath(joinpath(store.root, i))
    n = length(store.root)
    (length(resourceid) < n || resourceid[1:n] != store.root) && return "Cannot create/update an object outside the root bucket"
    backend = store.backend
    m = parentmodule(typeof(backend))
    m._isbucket(resourceid) && return "$(i) is a bucket, not an object"
    cb, shortname = splitdir(resourceid)
    !m._isbucket(cb) && return "Cannot create object $(i) inside a non-existent bucket."
    O = backend.object_type
    create!(store, O(resourceid), v)
end


"Read object. If successful return the value, else @warn the error message and return nothing."
function getindex(store::BucketStore, i::String)
    resourceid = normpath(joinpath(store.root, i))
    n = length(store.root)
    if length(resourceid) < n || resourceid[1:n] != store.root
        @warn "Cannot read an object outside the root bucket"
        return nothing
    end
    O = store.backend.object_type
    ok, val = read(store, O(resourceid))
    if !ok
        @warn val
        return nothing
    end
    val
end


"Delete object. If successful return nothing, else return an error message as a String."
function delete!(store::BucketStore, i::String)
    resourceid = normpath(joinpath(store.root, i))
    n = length(store.root)
    (length(resourceid) < n || resourceid[1:n] != store.root) && return "Cannot delete an object outside the root bucket"
    O = store.backend.object_type
    delete!(store, O(resourceid))
end


################################################################################
# Conveniences

"Returns true if the storage backend is on the same machine as the store instance."
function islocal(store::BucketStore)
    m = parentmodule(typeof(store.backend))
    m._islocal(store.backend)
end

"Returns true if name refers to a bucket."
function isbucket(store::BucketStore, name::String)
    resourceid = normpath(joinpath(store.root, name))
    n = length(store.root)
    if length(resourceid) < n || resourceid[1:n] != store.root
        @warn "Cannot access buckets or objects outside the root bucket"
        false
    else
        m = parentmodule(typeof(store.backend))
        m._isbucket(resourceid)
    end
end

"Returns true if name refers to an object."
function isobject(store::BucketStore, name::String)
    resourceid = normpath(joinpath(store.root, name))
    n = length(store.root)
    if length(resourceid) < n || resourceid[1:n] != store.root
        @warn "Cannot access buckets or objects outside the root bucket"
        false
    else
        m = parentmodule(typeof(store.backend))
        m._isobject(resourceid)
    end
end

function setpermission!(store::BucketStore, resourcetype::Symbol, p::Permission)
    resourcetype == :bucket && return setpermission!(store, store.backend.bucket_type, p)
    resourcetype == :object && return setpermission!(store, store.backend.object_type, p)
    @warn "Resource type unknown. Permission not set."
end


end
