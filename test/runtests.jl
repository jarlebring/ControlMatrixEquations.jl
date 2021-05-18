using ControlMatrixEquations
using Test, LinearAlgebra, Random


include("framework.jl")
include("riccati_benchmarks.jl")

my_tests = [
            "test_utilities",
            "test_sylvlyap_schur",
            "test_sylvlyap_naive",
            "test_sylvlyap",
            "test_arec",
            "test_ared"
            ]


# Compute C/Q from X to allow convenient check of solution
sylvc_rhs = (A, B, X) -> (A*X + X*B)
sylvd_rhs = (A, B, X) -> (A*X*B - X)
lyapc_rhs = (A, X) -> -Matrix(Hermitian(A*X + X*A'))
lyapd_rhs = (A, X) -> -Matrix(Hermitian(A*X*A' - X))

@testset "All Tests" begin
    println("Testing code")
    _t0_all = time()
    for test in my_tests
        println(test)
        _t0 = time()
        include("$(test).jl")
        println("Ran $test in $(round(time()-_t0, digits=2)) seconds")
    end
    println("Ran all code tests in $(round(time()-_t0_all, digits=2)) seconds")
end
