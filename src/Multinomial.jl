import Distributions.Multinomial

Multinomial() = Multinomial(1, 1.)

immutable GLMNetPathMultinomial{F<:Distribution}
    family::F
    a0::Array{Float64}              # intercept values for each solution
    #betas::Vector{CompressedPredictorMatrix}
    betas::Array{Float64}
    null_dev::Float64                # Null deviance of the model
    dev_ratio::Vector{Float64}       # R^2 values for each solution
    lambda::Vector{Float64}          # lamda values corresponding to each solution
    npasses::Int                     # actual number of passes over the
                                     # data for all lamda values
end

macro validate_and_init_multi()
    esc(quote
        validate_x_y_weights(X, y, weights)
        length(penalty_factor) == size(X, 2) ||
            error(Base.LinAlg.DimensionMismatch("length of penalty_factor must match rows in X"))
        (size(constraints, 1) == 2 && size(constraints, 2) == size(X, 2)) ||
            error(Base.LinAlg.DimensionMismatch("contraints must be a 2 x n matrix"))
        0 <= lambda_min_ratio <= 1 || error("lambda_min_ratio must be in range [0.0, 1.0]")
        #
        if !isempty(lambda)
            # user-specified lambda values
            nlambda == 100 || error("cannot specify both lambda and nlambda")
            lambda_min_ratio == (length(y) < size(X, 2) ? 1e-2 : 1e-4) ||
                error("cannot specify both lambda and lambda_min_ratio")
            nlambda = length(lambda)
            lambda_min_ratio = 2.0
        end
        #
        alpha = float(alpha)
        nobs = int32(size(X, 1))
        nvars = int32(size(X, 2))
        nresp = int32(size(y, 2))
        dfmax = int32(dfmax)
        pmax = int32(pmax)
        nlambda = int32(nlambda);
        lambda_min_ratio = float(lambda_min_ratio)
        lambda = convert(Vector{Float64}, lambda)
        tol = float(tol)
        standardize = int32(standardize)
        intercept = int32(intercept)
        maxit = int32(maxit)
        null_dev = 0.0
        jd = int32(0)
        #
        lmu = Int32[0]
        a0 = zeros(Float64, nresp, nlambda)
        ca = zeros(Float64, pmax, nresp, nlambda)
        ia = zeros(Int32, pmax)
        nin = zeros(Int32, nlambda)
        fdev = zeros(Float64, nlambda)
        alm = zeros(Float64, nlambda)
        nlp = Int32[0]
        jerr = Int32[0]
    end)
end


macro check_and_return_multi()
    esc(quote
        check_jerr(jerr[1], maxit)
        lmu = lmu[1]
        # first lambda is infinity; changed to entry point
        if isempty(lambda) && length(alm) > 2
            alm[1] = exp(2*log(alm[2])-log(alm[3]))
        end
#        xx = [CompressedPredictorMatrix(
#            size(X, 2), reshape(ca[:, _, 1:lmu], (size(ca, 1), lmu)), ia, nin[1:lmu]
#            ) for _ in 1:size(ca, 2)]
        GLMNetPathMultinomial(family, a0[:, 1:lmu], ca[sortperm(ia), :, 1:lmu], 
            null_dev, fdev[1:lmu], alm[1:lmu], int(nlp[1]))
    end)
end


function glmnet!(X::Matrix{Float64}, y::Matrix{Float64},
             family::Multinomial;
             offsets::Matrix{Float64}=y*0.,
             weights::Vector{Float64}=ones(size(y, 1)),
             alpha::Real=1.0,
             penalty_factor::Vector{Float64}=ones(size(X, 2)),
             constraints::Array{Float64, 2}=[_ for _ in (-Inf, Inf), y in 1:size(X, 2)],
             dfmax::Int=size(X, 2)+1, pmax::Int=min(dfmax*2+20, size(X, 2)), nlambda::Int=100,
             lambda_min_ratio::Real=(length(y) < size(X, 2) ? 1e-2 : 1e-4),
             lambda::Vector{Float64}=Float64[], tol::Real=1e-7, standardize::Bool=true,
             intercept::Bool=true, maxit::Int=1000000, grouped_multinomial::Bool=false,  
             algorithm::Symbol=:newtonraphson)
    println("1")
    @validate_and_init_multi
    kopt = grouped_multinomial? int32(2) : 
        algorithm == :newtonraphson ? int32(0) :
        algorithm == :modifiednewtonraphson ? int32(1) : 
        algorithm == :nzsame ? int32(2) : 
        error("unknown algorithm ")
    # check offsets
    println("2")
    assert(size(y) == size(offsets))
    y = y .* repmat(weights, 1, size(y, 2))
    # call lognet
    println("3")
    ccall(
        (:lognet_, "glmnet.so"), Void, (
            Ptr{Float64}   , Ptr{Int32}        , Ptr{Int32}   , Ptr{Int32}   , # 1
            Ptr{Float64}   , Ptr{Float64}      , Ptr{Float64} , Ptr{Int32}   , # 2
            Ptr{Float64}   , Ptr{Float64}      , Ptr{Int32}   , Ptr{Int32}   , # 3
            Ptr{Int32}     , Ptr{Float64}      , Ptr{Float64} , Ptr{Float64} , # 4
            Ptr{Int32}     , Ptr{Int32}        , Ptr{Int32}   , Ptr{Int32}   , # 5
            Ptr{Int32}     , Ptr{Float64}      , Ptr{Float64} , Ptr{Int32}   , # 6
            Ptr{Int32}     , Ptr{Float64}      , Ptr{Float64} , Ptr{Float64} , # 7
            Ptr{Int32}     , Ptr{Int32}                                        # 8
            ),
            &alpha         , &nobs             , &nvars       , &nresp       , # 1
            X              , y                 , offsets      , &jd          , # 2
            penalty_factor , constraints       , &dfmax       , &pmax        , # 3
            &nlambda       , &lambda_min_ratio , lambda       , &tol         , # 4
            &standardize   , &intercept        , &maxit       , &kopt        , # 5
            lmu            , a0                , ca           , ia           , # 6
            nin            , &null_dev         , fdev         , alm          , # 7
            nlp            , jerr                                              # 8
        )
    @check_and_return_multi
end

glmnet(X::Matrix{Float64}, y::Matrix{Float64}, family::Multinomial; kw...) =
    glmnet!(copy(X), copy(y), family; kw...)