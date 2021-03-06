# SCRIPT 2
# Functions for BN2MF project

# Packages ####
# If running on hpc, load libraries from remote path
if (grepl("/Users/lizzy/", getwd())) {
  library(tidyverse)
  library(R.matlab)
  library(psych)
  library(NMF)
  library(LearnBayes)
  library(CVXR)
} else {
  library(tidyverse, lib.loc = "/ifs/home/msph/ehs/eag2186/local/hpc/")
  library(R.matlab, lib.loc = "/ifs/home/msph/ehs/eag2186/local/hpc/")
  library(psych, lib.loc = "/ifs/home/msph/ehs/eag2186/local/hpc/")
  library(rngtools, lib.loc = "/ifs/home/msph/ehs/eag2186/local/hpc/")
  library(registry, lib.loc = "/ifs/home/msph/ehs/eag2186/local/hpc/")
  library(pkgmaker, lib.loc = "/ifs/home/msph/ehs/eag2186/local/hpc/")
  library(NMF, lib.loc = "/ifs/home/msph/ehs/eag2186/local/hpc/")
  library(CVXR, lib.loc = "/ifs/home/msph/ehs/eag2186/local/hpc/")
  library(GPArotation, lib.loc = "/ifs/home/msph/ehs/eag2186/local/hpc/")
  library(ellipsis,lib.loc = "/ifs/home/msph/ehs/eag2186/local/hpc/")
  library(LearnBayes, lib.loc = "/ifs/home/msph/ehs/eag2186/local/hpc/")
}

# Models to compare BN2MF with ####

# PCA
# Function to run PCA,
# determine how many components explain 80% of the variance
# choose that rank and
# output scores, loadings, pred, rank
get_pca <- function (sim.matrix) {
  # Run PCA centered, not scaled
  pca_out <- prcomp(sim.matrix)
  #loadings
  rot <- pca_out$rotation
  # scores
  ex <- pca_out$x
  # singular values
  sv <- pca_out$sdev
  
  # Explain >=80% of var
  pve <- sv^2/sum(sv^2)
  rank <- 0
  for (i in 1:length(sv)) {
    if (sum(pve[1:i]) >= 0.8) {
      rank <- i
      break
    }}
  
  # Cut scores and patterns to rank
  rotations <- as_tibble(rot[, 1:rank])
  scores <- if (rank == 1) {matrix(ex[, 1:rank], nrow = nrow(sim.matrix))} else {ex[, 1:rank]}
  # Predicted values
  pred <- scores %*% t(rotations) + matrix(rep(apply(sim.matrix, 2, mean), each= nrow(scores)), nrow = nrow(scores))
  
  return(list(rotations = rotations, scores = scores, pred = pred, rank = rank))
}

# Factor analysis
# Function to run FA,
# choose rank with lowest BIC
# output scores, loadings, pred, rank
get_fa <- function (sim.matrix, pattern.num) {
  
  set.seed(1988)
  
  # Run model with specified number of factors
  # and for one factor more and one factor less
  patternsm1 = ifelse(pattern.num == 1, 3, pattern.num - 1)
  patternsp1 = pattern.num+1
  
  # This keeps the script from crashing if FA doesn't work
  # Just return NA
  # If there is not enough variability in the sim (e.g., sims with no added noise)
  # the FA solution is singular and doesn't converge
  my_fa <- function(x.matrix, px){
    tryCatch(
      expr = {
        fa_xx <- fa(x.matrix, px, scores = "regression", rotate = "promax", fm = "ml")
        return(fa_xx)
      },
      error = function(e){
        return(NA)
      },
      warning = function(w){
        return(NA)
      })}
  
  fa_3 <- my_fa(sim.matrix, patternsm1)
  fa_4 <- my_fa(sim.matrix, pattern.num)   
  fa_5 <- my_fa(sim.matrix, patternsp1) 
  
  # Choose the model with the LOWEST BIC
  # If the model didn't converge, BIC = NA
  if(any(is.na(fa_3))) {fa_3BIC = NA} else {fa_3BIC = fa_3$BIC}
  if(any(is.na(fa_4))) {fa_4BIC = NA} else {fa_4BIC = fa_4$BIC}
  if(any(is.na(fa_5))) {fa_5BIC = NA} else {fa_5BIC = fa_5$BIC}
  
  # This chooses the lowest BIC
  # Also, ignore NA values, unless they are all NA
  # then, the best model is NA and rank is NA
  if (!any(is.na(fa_3BIC)) | !any(is.na(fa_4BIC)) | !any(is.na(fa_5BIC))) {
      if (min(fa_5BIC, fa_4BIC, fa_3BIC, na.rm = T) == fa_5BIC & !is.na(fa_5BIC)) {
        fa_out <- fa_5
        rank <- patternsm1
      } else if (min(fa_5BIC, fa_4BIC, fa_3BIC, na.rm = T) == fa_4BIC & !is.na(fa_4BIC)) {
        fa_out <- fa_4
        rank <- pattern.num
      } else {
        fa_out <- fa_3
        rank <- patternsp1
      }
    } else {
    fa_out = NA
    rank = NA
  }
  
  # If model isnt NA, save factors, scores, calculate pred
  if (!any(is.na(fa_out))) {
    loadings <- matrix(fa_out$loadings, ncol = ncol(fa_out$scores))
    fa_scores <- fa_out$scores
    # Pred should include mean
    pred <- fa_scores %*% t(loadings) + matrix(rep(apply(sim, 2, mean), each= nrow(fa_scores)), nrow = nrow(fa_scores))
    return(list(loadings = loadings, fa_scores = fa_scores, pred = pred, rank = rank))
  } else {
    return(list(loadings = NA, fa_scores = NA, pred = NA, rank = NA))
  }
}

# Calculate BIC
# NMF doesn't have a built in BIC
get_bic <- function(sim.matrix, pattern.num, scores, loadings){
  bic = sum((sim.matrix - (scores%*%loadings))^2) + 
    (1/2)*(nrow(sim.matrix) + ncol(sim.matrix)) * pattern.num * log(nrow(sim.matrix) * ncol(sim.matrix))
  return(bic)
}

# NMF L2
# Function to run NMF with L2 penalty
# choose rank with lowest BIC
# output scores, loadings, pred, rank
get_nmfl2 <- function (sim.matrix, pattern.num) {
  
  patternsm1 = ifelse(pattern.num == 1, 3, pattern.num - 1)
  patternsp1 = pattern.num+1
  
  set.seed(1988)
  nmf_3 <- nmf(sim.matrix, patternsm1, nrun = 100, method = "lee")
  nmf_4 <- nmf(sim.matrix, pattern.num,   nrun = 100, method = "lee")
  nmf_5 <- nmf(sim.matrix, patternsp1, nrun = 100, method = "lee")
  
  # Calculate BIC for each
  bic_3 <- get_bic(sim.matrix, patternsm1, basis(nmf_3), coef(nmf_3))
  bic_4 <- get_bic(sim.matrix, pattern.num,   basis(nmf_4), coef(nmf_4))
  bic_5 <- get_bic(sim.matrix, patternsp1, basis(nmf_5), coef(nmf_5))
  
  # Choose model with lowest BIC
  if (min(bic_3, bic_4, bic_5) == bic_3) {
    nmf_out <- nmf_3
    rank <- patternsm1
  } else if (min(bic_3, bic_4, bic_5) == bic_4) {
    nmf_out <- nmf_4
    rank <- pattern.num
  } else {
    nmf_out <- nmf_5
    rank <- patternsp1
  }
  
  basis <- basis(nmf_out)
  coef <- coef(nmf_out)
  pred <- basis %*% coef
  return(list(coef = coef, basis = basis, pred = pred, rank = rank))
}

# NMF Poisson
# Function to run NMF with divergence penalty
# choose rank with lowest BIC
# output scores, loadings, pred, rank
get_nmfp <- function (sim.matrix, pattern.num) {
  
  patternsm1 = ifelse(pattern.num == 1, 3, pattern.num - 1)
  patternsp1 = pattern.num+1
  
  set.seed(1988)
  nmf_3 <- nmf(sim.matrix, patternsm1, nrun = 100, method = "brunet")
  nmf_4 <- nmf(sim.matrix, pattern.num,   nrun = 100, method = "brunet")
  nmf_5 <- nmf(sim.matrix, patternsp1, nrun = 100, method = "brunet")
  
  # Calculate BIC for each
  bic_3 <- get_bic(sim, patternsm1, basis(nmf_3), coef(nmf_3))
  bic_4 <- get_bic(sim, pattern.num,   basis(nmf_4), coef(nmf_4))
  bic_5 <- get_bic(sim, patternsp1, basis(nmf_5), coef(nmf_5))
  
  if (min(bic_3, bic_4, bic_5) == bic_3) {
    nmf_out <- nmf_3
    rank <- patternsm1
  } else if (min(bic_3, bic_4, bic_5) == bic_4) {
    nmf_out <- nmf_4
    rank <- pattern.num
  } else {
    nmf_out <- nmf_5
    rank <- patternsp1
  }
  
  basis <- basis(nmf_out)
  coef <- coef(nmf_out)
  pred <- basis %*% coef
  return(list(coef = coef, basis = basis, pred = pred, rank = rank))
}

# Metric Functions ####
# to compare performance

# Symmetric Subspace Distance 
symsub_dist <- function(Umatrix, Vmatrix) {
  
  # there is some hacky error-handling in here
  # to return `NA' instead of crashing
  if(any(is.na(U)) | any(is.na(V))) {return(NA)} else {
    
    U = as.matrix(Umatrix)
    V = as.matrix(Vmatrix)
    
    # patterns should be columns
    if (nrow(U) < ncol(U)) {U <- t(U)}
    if (nrow(V) < ncol(V)) {V <- t(V)}
    
    # this gets an orthonormal basis
    # Both provide orthonormal bases, but svd does not give NaNs for lots of zeros
    # the distance is invariant to choice of orthonormal basis
    qrU <- qr.Q(qr(U))
    qrV <- qr.Q(qr(V))
    
    if (any(is.nan(qrU)) | any(is.nan(qrV))) {
      qrU <- svd(U)$u
      qrV <- svd(V)$u
    }
    
    m <- ncol(U)
    n <- ncol(V)
    
    # this is the formula
    # don't want the script to crash
    tryCatch(
      {dUV <- sqrt( max(m,n) - sum((t(qrU) %*% qrV)^2) )
      },
      error = function(er){
        dUV = NA
      },
      warning = function(cond){
        dUV = NA
      })
    
    # it happened somewhere that round((max(m,n) - sum((t(qrU) %*% qrV)^2)),10) was so close to 0
    # that the sqrt function gave NaN
    if(round((max(m,n) - sum((t(qrU) %*% qrV)^2)),10) == 0) {dUV = 0} # if sqrt(0), make zero
    
    if (!is.na(dUV)) {ratio <- dUV/sqrt( max(m,n))} else {ratio = NA}
    return(ratio)
  }
}

# Check orthonormal bases
# x = matrix(rnorm(30), ncol = 10)
# 
# qrx = qr.Q(qr(x))
# svdx = svd(x)$u
# 
# # orthogonal
# round(t(qrx) %*% qrx, 10)
# round(t(svdx) %*% svdx, 10)
# 
# # unitary
# apply(qrx, 2, function(x) (sum(x^2)))
# apply(svdx, 2, function(x) (sum(x^2)))

# Cosine distance (matrix version)
# WITH error handling
# if the matrices are not the same size, NA
cos_dist <- function(a, b){

  if(any(is.na(a)) | any(is.na(b))) {return(NA)} else{
    
    a = as.matrix(a)
    b = as.matrix(b)
    
    # patterns should be columns
    if (nrow(a) < ncol(a)) {a <- t(a)}
    if (nrow(b) < ncol(b)) {b <- t(b)}
  
    if(ncol(a) != ncol(b)) { return(NA) } else{
        a = as.vector(a)
        b = as.vector(b)
        cos_sim = (a %*% b) / (norm(a, "2")*norm(b, "2"))
        return(as.numeric(1-cos_sim)) 
    }
  }
}

# L2 relative error
# WITH error handling
# if the matrices are not the same size, NA
get_relerror <- function(Xmatrix,Ymatrix) {

  if(any(is.na(Xmatrix)) | any(is.na(Ymatrix))) {return(NA)} else{
    
        x = as.matrix(Xmatrix)
        y = as.matrix(Ymatrix)
        
        # patterns should be columns
        if (nrow(x) < ncol(x)) {x <- t(x)}
        if (nrow(y) < ncol(y)) {y <- t(y)}  
    
        if(ncol(x) != ncol(y)) { return(NA) } else{
                return(norm(x-y, "F")/norm(x, "F"))
              }
  }
}

# L1 relative error
# WITH error handling
# if the matrices are not the same size, NA
get_l1_error <- function(Xmatrix,Ymatrix) {
  
  if(any(is.na(Xmatrix)) | any(is.na(Ymatrix))) {return(NA)} else{
    
    x = as.matrix(Xmatrix)
    y = as.matrix(Ymatrix)
    
    # patterns should be columns
    if (nrow(x) < ncol(x)) {x <- t(x)}
    if (nrow(y) < ncol(y)) {y <- t(y)}  
    
    if(ncol(x) != ncol(y)) { return(NA) } else{
      return( sum(abs(x-y))/sum(abs(x)) )
    }
  }
}

# Get the proportion of true values within confidence interval
# WITH error handling
# if the matrices are not the same size, NA
get_prop <- function(true.matrix,lower.matrix,upper.matrix) {
  # true value, lower CI, upper CI
  
  # this function takes the true simulated value (x) and the upper (z) and lower (y) bounds
  # for the estimated confidence interval, and for each entry in the matrix, it gives a 1 if 
  # the truth is within the CI, and a zero if it isn't
  # then it takes the proportion of 1's over all entries as the coverage proportion.
  
  if(any(is.na(true.matrix)) | any(is.na(lower.matrix))) {return(NA)} else{
    
    x = as.matrix(true.matrix)
    y = as.matrix(lower.matrix)
    z = as.matrix(upper.matrix)
    
    # patterns should be columns
    if (nrow(x) < ncol(x)) {x <- t(x)}
    if (nrow(y) < ncol(y)) {y <- t(y)}  
    if (nrow(z) < ncol(z)) {z <- t(z)}  
    
    if(ncol(x) != ncol(y)) { return(NA) } else{
      return( sum(x >= y & x <= z)/(nrow(x)*ncol(x)) )
    }
  }
}
  
# Factor correspondence
# WITH error handling
# if matrices are not same size, NA
# If nn is false, we allow *signed permutations*
factor_correspondence <- function (A, B, nn = TRUE) {
  # This is all from the CVXR package, which is kind of its own language
  # for convex optimization
  
  # A and B are both matrices
  #  B is the one that gets rearranged relative to A.
  G <- t(B) %*% A
  n <- nrow(G)
  
  # Step 1. Define the variable to be estimated
  # Pi -- the permutation or signed permutation matrix
  Pi <- Variable(n,n)
  
  # Step 2. Define the objective to be optimized
  objective <- Maximize(base::sum(Pi * G))
  
  if (nn) {
    # Step 2.5. Subject to these constraints
    constX = list()
    for (i in 1:nrow(G)) {
      constX <-  c(constX, list(base::sum(Pi[,i]) == 1))
      constX <-  c(constX, list(base::sum(Pi[i,]) == 1))
    }
    constX <- c(constX, Pi >= 0)
  } else {
    # % allow sign flips 
    # Step 3. vector l1 norms along rows and columns
    constX = list()
    for (i in 1:nrow(G)) {
      constX <-  c(constX, list(base::sum(abs(Pi[,i])) <= 1))
      constX <-  c(constX, list(base::sum(abs(Pi[i,])) <= 1))
    }
  }  
  # Step 3. Create a problem to solve
  problem <- Problem(objective, constraints = constX)
  
  # Step 4. Solve it!
  result <- solve(problem)
  
  # Step 5. Extract solution and objective value
  perm <- round(result$getValue(Pi), 0)
  
  e <- norm(B,'f')^2 + norm(A,'f')^2 - 2 * base::sum(perm * G)
  # e -- the sum of squared errors under the best calibration \Pi
  
  # New matrix with best order
  newB <- B %*% perm
  
  return(list(rearranged = newB, permutation_matrix = perm))
}

# Just a wrapper around factor_correspondence
# with error handling
get_perm <- function(x,y, nn = TRUE) {
  # x and y are both matrices
  # y is rearranged relative to x
  
  if(any(is.na(x)) | any(is.na(y))) {return(NA)} else{
    
      x = as.matrix(x)
      y = as.matrix(y)
      
      # patterns should be columns
      if (nrow(x) < ncol(x)) {x <- t(x)}
      if (nrow(y) < ncol(y)) {y <- t(y)}  
      
      if(ncol(x) != ncol(y)) { return(NA) } else{
        return(factor_correspondence(x, y, nn)$permutation_matrix) } 
      }
}

# Multiply loadings and scores by perm matrix
# with error handling
get_perm_product <- function(x,y) {
  if(any(is.na(x)) | any(is.na(y))) {return(x)} else{ # if permutation matrix is NA, return X
    # x and y must both be matrices
    x = as.matrix(x)
    y = as.matrix(y)
    
    # patterns should be columns
    if (nrow(x) < ncol(x)) {x <- t(x)}
    
    if(ncol(x) != ncol(y)) { return(x) } else{ return(x %*% y) }
  }
}

