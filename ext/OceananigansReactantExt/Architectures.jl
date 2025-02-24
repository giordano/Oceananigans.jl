module Architectures

using Reactant
using Oceananigans

import Oceananigans.Architectures: device, architecture, array_type, on_architecture, unified_array, ReactantState, device_copy_to!

const ReactantKernelAbstractionsExt = Base.get_extension(
    Reactant, :ReactantKernelAbstractionsExt
)
const ReactantBackend = ReactantKernelAbstractionsExt.ReactantBackend
device(::ReactantState) = ReactantBackend()

architecture(::Reactant.AnyConcretePJRTArray) = ReactantState
architecture(::Reactant.AnyTracedRArray) = ReactantState

array_type(::ReactantState) = ConcreteRArray

on_architecture(::ReactantState, a::Array) = ConcreteRArray(a)
on_architecture(::ReactantState, a::Reactant.AnyConcretePJRTArray) = a
on_architecture(::ReactantState, a::Reactant.AnyTracedRArray) = a
on_architecture(::ReactantState, a::BitArray) = ConcretePJRTArray(a)
on_architecture(::ReactantState, a::SubArray{<:Any, <:Any, <:Array}) = ConcretePJRTArray(a)

unified_array(::ReactantState, a) = a

@inline device_copy_to!(dst::Reactant.AnyConcretePJRTArray, src::Reactant.AnyConcretePJRTArray; kw...) = Base.copyto!(dst, src)

end # module
