#=
The implementaiton is intended to be simple and fast. However in order to maintain
 readability, a few small optimizations have not been persued, for example:
* Symmetry is not exploited when solving diagonal entries of Lyapuniv equations
* Could use one more in-place multiplication in the top level functions
* Small savings could be possible when compting U*Q*U' where Q is symmetric, see [1]
* Could make the traiangular solve methods accepts various combinations of upper/lower
  Schur matrices but this seems to add quite a bit of code at quite a bit of code for quite a small gain.

# Some other questions
* What convention for signs and tranposes?
* Should error checking be done after each block solve or at the end of the algorithm?
=#

"""
    sylvc(A, B, C) -> X

Find the solution `X` to the continuous-time Sylvester equation

`AX + XB = C`

A solution exists unless `A` and `B` have eigenvalues `λ` and `μ` such that λ + μ = 0.

[1] **Bartels, R. H., & Stewart, G. W.** (1972). "Solution of the matrix
    equation AX + XB = C" Communications of the ACM, 15(9), 820-826.
"""
function sylvc(A, B, C, ::Val{:bartstew})
    _check_sylv_inputs(A, B, C)

    At2, UA = schur(A')
    B2, UB = schur(B)

    C2 = UA'*C*UB # This should give C2 the right type

    Y = _sylvc_schur!(Matrix(At2'), B2, C2, Val(:sylv))

    X = mul!(Y, UA, Y*UB')
end


"""
    sylvd(A, B, C) -> X

Find the solution `X` to the discrete-time Sylvester equation

`AXB - X = C`

A solution exists unless `A` and `B` have eigenvalues `λ` and `μ` such that λμ = 1.

[1] **Bartels, R. H., & Stewart, G. W.** (1972). "Solution of the matrix
    equation AX + XB = C" Communications of the ACM, 15(9), 820-826.
"""
function sylvd(A, B, C, ::Val{:bartstew})
    _check_sylv_inputs(A, B, C)

    At2, UA = schur(A')
    B2, UB = schur(B)

    C2 = UA'*C*UB

    Y = _sylvd_schur!(Matrix(At2'), B2, C2, Val(:sylv))

    X = mul!(Y, UA, Y*UB')
end


"""
    lyapc(A, Q) -> X

Computes the solution `X` of the continuous-time Lyapunov equation

`AX + XA' + Q = 0`

A solution exists unless `A` has an eigenvalue λ = ±1 or an eigenvalue pair λ₁λ₂ = 1.

[1] **Bartels, R. H., & Stewart, G. W.** (1972). "Solution of the matrix
    equation AX + XB = C" Communications of the ACM, 15(9), 820-826.
"""
function lyapc(A, Q, ::Val{:bartstew})

     _check_lyap_inputs(A, Q)

    At2, U = schur(A')

    Q2 = U'*Q*U

    Y = _sylvc_schur!(Matrix(At2'), At2, lmul!(-1, Q2), Val(:lyap))

    X = mul!(Y, U, Y*U')
end


"""
    X = lyapd(A, Q) -> X

Find the solution `X` to the discrete-time Lyapunov equation

`AXA' - X + Q = 0`

A solution exists unless `A` has an eigenvalue λ = ±1 or an eigenvalue pair λ₁λ₂ = 1 .


[1] **Barraud, A.** (1977) "A numerical algorithm to solve A'XA - X = Q"
    IEEE Transactions on Automatic Control

[2] **Bartels, R. H., & Stewart, G. W.** (1972). "Solution of the matrix
    equation AX + XB = C" Communications of the ACM, 15(9), 820-826.

"""
function lyapd(A, Q, ::Val{:bartstew})

    _check_lyap_inputs(A, Q)

    At2, U = schur(A')

    Q2 = U'*Q*U

    Y = _sylvd_schur!(Matrix(At2'), At2, lmul!(-1, Q2), Val(:lyap))

    X = mul!(Y, U, Y*U')
end


"""
    sylvc_schur!(A::AbstractMatrix, B::AbstractMatrix, C::AbstractMatrix) -> X

Find the solution `X` to the continuous-time Sylvester equation

`AX + XB = C`

where `A` is assumed to have lower Schur form (quasi-triangular, 1x1 & 2x2 blocks on the diagonal)
`B` is assumed to have upper Schur form

See also `sylvc`
"""
function sylvc_schur!(A::AbstractMatrix, B::AbstractMatrix, C::AbstractMatrix)
    _check_sylv_inputs(A, B, C)
    T = sylvcsoltype(A, B, C)
    _sylvc_schur!(convert(Matrix, A), convert(Matrix, B), convert(Matrix{T}, C), Val(:sylv))
end
function lyapc_schur!(A::AbstractMatrix, Q::AbstractMatrix)
    _check_lyap_inputs(A, Q)
    T = sylvcsoltype(A, A, Q)
    _sylvc_schur!(convert(Matrix, A), convert(Matrix, A'), lmul!(-1, Matrix{T}(Q)), Val(:lyap))
end
function _sylvc_schur!(A::Matrix, B::Matrix, C::Matrix, alg::Union{Val{:sylv},Val{:lyap}},
    schurtype::Union{Val{:real},Val{:complex}} = isreal(A) || isreal(B) ? Val(:real) : Val(:complex)) where {T <: Number}
    # The user should preferably use sylvc_schur! and lyapc_schur!
    # I.e., this method does not check whether C is hermitian
    # The matrix C is successively replaced with the solution X

    # get block indices and nbr of blocks
    if schurtype === Val(:real)
        _, ba, nblocksa = _schurstructure(A, Val(:L)) # A is assumed upper triangualar
        _, bb, nblocksb = _schurstructure(B, Val(:U))
    else
        nblocksa = size(A, 1)
        nblocksb = size(B, 1)
    end

    @inbounds for j=1:nblocksb
        i0 = (alg === Val(:lyap) ? j : 1)

        if schurtype === Val(:real) # Only seems to be helpful in the real case
            @views mul!(C[ba[i0][1]:end, bb[j]], C[ba[i0][1]:end, 1:bb[j][1]-1], B[1:bb[j][1]-1, bb[j]], -1, 1)
        else
            @views mul!(C[i0:end,j], C[i0:end, 1:j-1], B[1:j-1, j], -1, 1)
        end

        for i=i0:nblocksa
            if schurtype === Val(:complex)
                if i > 1; C[i,j] -= sum(A[i, k] * C[k, j] for k=1:i-1); end
                #if j > 1; C[i,j] -= sum(C[i, k] * B[k, j] for k=1:j-1); end

                C[i,j] = sylvc(A[i, i], B[j, j], C[i, j]) # C[i,j] now contains  solution Y[i,j]

                if alg === Val(:lyap) && i > j
                    C[j,i] = conj(C[i,j])
                end
            else
                Aii = view(A, ba[i], ba[i])
                Bjj = view(B, bb[j], bb[j])
                Cij = view(C, ba[i], bb[j])

                @views mul!(Cij, A[ba[i], 1:ba[i][1]-1], C[1:ba[i][1]-1, bb[j]], -1, 1) # adds nothigng for i=1

                _sylvc!(Aii, Bjj, Cij) # Cij now contains the solution Yij

                if alg === Val(:lyap) && i > j
                    for l=bb[j], k=ba[i]
                        C[l,k] = conj(C[k,l])
                    end
                end
            end
        end
    end
    return C
end


"""
    sylvd_schur!(A::AbstractMatrix, B::AbstractMatrix, C::AbstractMatrix) -> X

Solve the discrete-time Sylvester equation

`AXB - X = C`

where `A` is assumed to have lower Schur form (quasi-triangular, 1x1 & 2x2 blocks on the diagonal)
`B` is assumed to have upper Schur form

If the matrix `C` has the right type, it is overwritten with the solution `X`.

See also `sylvd`
"""
function sylvd_schur!(A::AbstractMatrix, B::AbstractMatrix, C::AbstractMatrix)
    _check_sylv_inputs(A, B, C)
    T = sylvdsoltype(A, B, C)
    _sylvd_schur!(convert(Matrix, A), convert(Matrix, B), convert(Matrix{T}, C), Val(:sylv))
end
function lyapd_schur!(A::AbstractMatrix, Q::AbstractMatrix)
    _check_lyap_inputs(A, Q)
    T = sylvdsoltype(A, A, Q)
    _sylvd_schur!(convert(Matrix, A), convert(Matrix, A'), lmul!(-1, Matrix{T}(Q)), Val(:lyap))
end
function _sylvd_schur!(A::Matrix, B::Matrix, C::Matrix, alg::Union{Val{:sylv},Val{:lyap}},
    schurtype::Union{Val{:real},Val{:complex}} = isreal(A) || isreal(B) ? Val(:real) : Val(:complex)) where {T <: Number}

    G = zeros(eltype(C), size(A,1), size(B, 1)) # Keep track of A*X for improved performance

    # get block dimensions, block indices, nbr of blocks
    if schurtype === Val(:real)
        _, ba, nblocksa = _schurstructure(A, Val(:L)) # A is assumed upper triangualar
        _, bb, nblocksb = _schurstructure(B, Val(:U))
    else
        nblocksa = size(A, 1)
        nblocksb = size(B, 1)
    end

    @inbounds for j=1:nblocksb
        i0 = (alg === Val(:lyap) ? j : 1)
        for i=i0:nblocksa
            if schurtype === Val(:complex)
                # Compute Gij up to the contribution from Aii*Yij which is added at the end of each iteration
                if i > 1; G[i,j] += sum(A[i,k] * C[k,j] for k=1:i-1); end

                C[i,j] -= sum(G[i,k] * B[k,j] for k=1:j)

                C[i,j] = sylvd(A[i,i], B[j,j], C[i,j]) # C[i,j] now contains  solution Y[i,j]

                if alg === Val(:lyap) && i > j
                    C[j,i] = conj(C[i,j])
                end

                G[i,j] += A[i, i] * C[i, j]
            else
                Aii = view(A, ba[i], ba[i])
                Bjj = view(B, bb[j], bb[j])
                Cij = view(C, ba[i], bb[j])

                Gij = view(G, ba[i], bb[j])

                if i > 1
                    @views mul!(Gij, A[ba[i], 1:ba[i-1][end]], C[1:ba[i-1][end], bb[j]], 1, 1)
                end

                @views mul!(Cij, G[ba[i], 1:bb[j][end]], B[1:bb[j][end], bb[j]], -1, 1)

                _sylvd!(Aii, Bjj, Cij) # Cij now contains the solution Yij

                if alg === Val(:lyap) && i > j
                    for l=bb[j], k=ba[i] # Avoids aliasing of copyto!
                        C[l,k] = conj(C[k,l])
                    end
                end

                mul!(Gij, Aii, Cij, 1, 1)
            end
        end
    end
    return C
end
