# We compute the least angle regression (LAR) path given
# a response vector y and predictor matrix x.  We assume
# that x has columns in general position.

# NOTE: the df estimates at each lambda_k can be thought of as the df
# for all solutions corresponding to lambda in (lambda_k,lambda_{k-1}),
# the open interval to the *right* of the current lambda_k.

# NOTE: x having columns in general position implies that the
# centered x satisfies a modified version of the general position
# condition, where we replace k < min(n,p) by k < min(n-1,p) in
# the definition. This is still sufficient to imply the uniqueness
# of the lasso solution, on the centered x

lar <- function(x, y, maxsteps=2000, minlam=0, verbose=FALSE,
                intercept=TRUE, normalize=TRUE) {

  this.call = match.call()
  checkargs.xy(x=x,y=y)
  
  # Center and scale, etc.
  obj = standardize(x,y,intercept,normalize)
  x = obj$x
  y = obj$y
  bx = obj$bx
  by = obj$by
  sx = obj$sx
  n = nrow(x)
  p = ncol(x)

  #####
  # Find the first variable to enter and its sign
  uhat = t(x)%*%y
  ihit = which.max(abs(uhat))   # Hitting coordinate
  hit = abs(uhat[ihit])         # Critical lambda
  s = Sign(uhat[ihit])          # Sign

  if (verbose) {
    cat(sprintf("1. lambda=%.3f, adding variable %i, |A|=%i...",
                hit,ihit,1))
  }

  # Now iteratively find the new LAR estimate, and
  # the next critical lambda

  # Things to keep track of, and return at the end
  buf = min(maxsteps,500)
  lambda = numeric(buf)      # Critical lambdas
  action = numeric(buf)      # Actions taken
  df = numeric(buf)          # Degrees of freedom
  beta = matrix(0,p,buf)     # LAR estimates
  
  lambda[1] = hit
  action[1] = ihit
  df[1] = 0
  beta[,1] = 0

  # Gamma matrix!
  Gamma = matrix(0,0,n)
  if (p>1) Gamma = rbind(Gamma,t(s*x[,ihit]+x[,-ihit]),t(s*x[,ihit]-x[,-ihit]))
  Gamma = rbind(Gamma,t(s*x[,ihit]))
  nk = nrow(Gamma)

  # M plus
  if (p>1) {
    c = t(as.numeric(Sign(t(x)%*%y)) * t(x))
    ratio = t(c[,-ihit])%*%c[,ihit]/sum(c[,ihit]^2)
    ip = 1-ratio > 0
    crit = (t(c[,-ihit])%*%y - ratio*sum(c[,ihit]*y))/(1-ratio)
    mp = max(max(crit[ip]),0)
  }
  else mp = 0
  
  # Other things to keep track of, but not return
  r = 1                      # Size of active set
  A = ihit                   # Active set
  I = Seq(1,p)[-ihit]        # Inactive set
  X1 = x[,ihit,drop=FALSE]   # Matrix X[,A]
  X2 = x[,-ihit,drop=FALSE]  # Matrix X[,I]
  k = 2                      # What step are we at?

  # Compute a skinny QR decomposition of X1
  obj = qr(X1)
  Q = qr.Q(obj,complete=TRUE)
  Q1 = Q[,1,drop=FALSE];
  Q2 = Q[,-1,drop=FALSE]
  R = qr.R(obj)
  
  # Throughout the algorithm, we will maintain
  # the decomposition X1 = Q1*R. Dimenisons:
  # X1: n x r
  # Q1: n x r
  # Q2: n x (n-r)
  # R:  r x r
    
  while (k<=maxsteps && lambda[k-1]>=minlam) {
    ##########
    # Check if we've reached the end of the buffer
    if (k > length(lambda)) {
      buf = length(lambda)
      lambda = c(lambda,numeric(buf))
      action = c(action,numeric(buf))
      df = c(df,numeric(buf))
      beta = cbind(beta,matrix(0,p,buf))
    }

    # Key quantities for the hitting times
    a = backsolve(R,t(Q1)%*%y)
    b = backsolve(R,backsolve(R,s,transpose=TRUE))
    aa = as.numeric(t(X2) %*% (y - X1 %*% a))
    bb = as.numeric(t(X2) %*% (X1 %*% b))
    
    # If the inactive set is empty, nothing will hit
    if (r==min(n-intercept,p)) hit = 0

    # Otherwise find the next hitting time
    else {
      shits = Sign(aa)
      hits = aa/(shits-bb)

      # Make sure none of the hitting times are larger
      # than the current lambda 
      hits[hits>lambda[k-1]] = 0
        
      ihit = which.max(hits)
      hit = hits[ihit]
      shit = shits[ihit]
    }

    # Stop if the next critical point is negative
    if (hit<=0) break
    
    # Record the critical lambda and solution
    lambda[k] = hit
    action[k] = I[ihit]
    df[k] = r
    beta[A,k] = a-hit*b
        
    # Gamma matrix!
    X2perp = X2 - X1 %*% backsolve(R,t(Q1)%*%X2)
    c = t(t(X2perp)/(shits-bb))
    Gamma = rbind(Gamma,shits*t(X2perp))
    if (ncol(c)>1) Gamma = rbind(Gamma,t(c[,ihit]-c[,-ihit]))
    Gamma = rbind(Gamma,t(c[,ihit]))
    nk = c(nk,nrow(Gamma))

    # M plus
    if (ncol(c)>1) {
      ratio = t(c[,-ihit])%*%c[,ihit]/sum(c[,ihit]^2)
      ip = 1-ratio > 0
      crit = (t(c[,-ihit])%*%y - ratio*sum(c[,ihit]*y))/(1-ratio)
      mp = c(mp,max(max(crit[ip]),0))
    }
    else mp = c(mp,0)
    
    # Update all of the variables
    r = r+1
    A = c(A,I[ihit])
    I = I[-ihit]
    s = c(s,shit)
    X1 = cbind(X1,X2[,ihit])
    X2 = X2[,-ihit,drop=FALSE]

    # Update the QR decomposition
    obj = updateQR(Q1,Q2,R,X1[,r])
    Q1 = obj$Q1
    Q2 = obj$Q2
    R = obj$R
     
    if (verbose) {
      cat(sprintf("\n%i. lambda=%.3f, adding variable %i, |A|=%i...",
                  k,hit,A[r],r))
    }
            
    # Step counter
    k = k+1
  }

  # Trim
  lambda = lambda[Seq(1,k-1)]
  action = action[Seq(1,k-1)]
  df = df[Seq(1,k-1),drop=FALSE]
  beta = beta[,Seq(1,k-1),drop=FALSE]
  
  # If we reached the maximum number of steps
  if (k>maxsteps) {
    if (verbose) {
      cat(sprintf("\nReached the maximum number of steps (%i),",maxsteps))
      cat(" skipping the rest of the path.")
    }
    completepath = FALSE
    bls = NULL
  }

  # If we reached the minimum lambda
  else if (lambda[k-1]<minlam) {
    if (verbose) {
      cat(sprintf("\nReached the minimum lambda (%.3f),",minlam))
      cat(" skipping the rest of the path.")
    }
    completepath = FALSE
    bls = NULL
  }
  
  # Otherwise, note that we completed the path
  else {
    completepath = TRUE
    
    # Record the least squares solution. Note that
    # we have already computed this
    bls = rep(0,p)
    bls[A] = a
  }

  if (verbose) cat("\n")
  
  # Adjust for the effect of centering and scaling
  if (intercept) df = df+1
  if (normalize) beta = beta/sx
  if (normalize && completepath) bls = bls/sx
  
  # Assign column names
  colnames(beta) = as.character(round(lambda,3))

  out = list(lambda=lambda,action=action,sign=s,df=df,beta=beta,
    completepath=completepath,bls=bls,
    Gamma=Gamma,nk=nk,mp=mp,x=x,y=y,bx=bx,by=by,sx=sx,
    intercept=intercept,normalize=normalize,call=this.call) 
  class(out) = "lar"
  return(out)
}

##############################

# Downdate the QR factorization, after a column has
# been deleted. Here Q1 is m x n, Q2 is m x k, and
# R is n x n.

downdateQR <- function(Q1,Q2,R,col) {
  m = nrow(Q1)
  n = ncol(Q1)
  
  a = .C("downdate1",
    Q1=as.double(Q1),
    R=as.double(R),
    col=as.integer(col-1),
    m=as.integer(m),
    n=as.integer(n),
    dup=FALSE,
    package="selectiveInference")

  Q1 = matrix(a$Q1,nrow=m)
  R = matrix(a$R,nrow=n)

  # Re-structure: add a column to Q2, delete one from
  # Q1, and trim R
  Q2 = cbind(Q2,Q1[,n])
  Q1 = Q1[,-n,drop=FALSE]
  R = R[-n,-col,drop=FALSE]

  return(list(Q1=Q1,Q2=Q2,R=R))
}

# Update the QR factorization, after a column has been
# added. Here Q1 is m x n, Q2 is m x k, and R is n x n.

updateQR <- function(Q1,Q2,R,col) {
  m = nrow(Q1)
  n = ncol(Q1)
  k = ncol(Q2)
  
  a = .C("update1",
    Q2=as.double(Q2),
    w=as.double(t(Q2)%*%col),
    m=as.integer(m),
    k=as.integer(k),
    dup=FALSE,
    package="selectiveInference")

  Q2 = matrix(a$Q2,nrow=m)
  w = c(t(Q1)%*%col,a$w)

  # Re-structure: delete a column from Q2, add one to
  # Q1, and expand R
  Q1 = cbind(Q1,Q2[,1])
  Q2 = Q2[,-1,drop=FALSE]
  R = rbind(R,rep(0,n))
  R = cbind(R,w[Seq(1,n+1)])

  return(list(Q1=Q1,Q2=Q2,R=R))
}

##############################

# Coefficient function for lar

coef.lar <- function(obj, s, mode=c("step","lambda")) {
  mode = match.arg(mode)

  if (obj$completepath) {
    k = length(obj$action)+1
    lambda = c(obj$lambda,0)
    beta = cbind(obj$beta,obj$bls)
  } else {
    k = length(obj$action)
    lambda = obj$lambda
    beta = obj$beta
  }
  
  if (mode=="step") {
    if (min(s)<0 || max(s)>k) stop(sprintf("s must be between 0 and %i",k))
    knots = 1:k
    dec = FALSE
  } else {
    if (min(s)<min(lambda)) stop(sprintf("s must be >= %0.3f",min(lambda)))
    knots = lambda
    dec = TRUE
  }
  
  return(coef.interpolate(beta,s,knots,dec))
}

# Prediction function for lar

predict.lar <- function(obj, newx, s, mode=c("step","lambda")) {
  beta = coef.lar(obj,s,mode)
  if (missing(newx)) newx = scale(obj$x,FALSE,1/obj$sx)
  else newx = scale(newx,obj$bx,FALSE)
  return(newx %*% beta + obj$by)
}

coef.lasso <- coef.lar
predict.lasso <- predict.lar

##############################

# Lar inference function

larInf <- function(obj, sigma=NULL, alpha=0.1, k=NULL, type=c("active","all","aic"), 
                   gridfac=25, gridpts=1000, mult=2, ntimes=2) {
  
  this.call = match.call()
  type = match.arg(type)
  checkargs.misc(sigma=sigma,alpha=alpha,k=k)
  if (class(obj) != "lar") stop("obj must be an object of class lar")
  if (is.null(k) && type=="active") k = length(obj$action)
  if (is.null(k) && type=="all") stop("k must be specified when type = all")
  
  k = min(k,length(obj$action)) # Round to last step
  x = obj$x
  y = obj$y
  p = ncol(x)
  n = nrow(x)
  G = obj$Gamma
  nk = obj$nk

  if (is.null(sigma)) {
    if (n < 2*p) sigma = sd(y)
    else sigma = sqrt(sum(lsfit(x,y,intercept=F)$res^2)/(n-p))
  }

  pv.spacing = pv.asymp = pv.covtest = khat = NULL
  
  if (type == "active") {
    pv = vlo = vup = numeric(k) 
    vmat = matrix(0,k,n)
    ci = tailarea = matrix(0,k,2)
    pv.spacing = pv.asymp = pv.covtest = numeric(k)
    sign = obj$sign[1:k]
    vars = obj$action[1:k]

    for (j in 1:k) {
      Gj = G[1:nk[j],]
      uj = rep(0,nk[j])
      vj = G[nk[j],]
      vj = vj / sqrt(sum(vj^2))
      a = poly.pval(y,Gj,uj,vj,sigma)
      pv[j] = a$pv
      vlo[j] = a$vlo
      vup[j] = a$vup
      vmat[j,] = vj
    
      a = poly.int(y,Gj,uj,vj,sigma,alpha,gridfac=gridfac,gridpts=gridpts,
        flip=(sign[j]==-1))
      ci[j,] = a$int
      tailarea[j,] = a$tailarea
      
      pv.spacing[j] = spacing.pval(obj,sigma,j)
      pv.asymp[j] = asymp.pval(obj,sigma,j)
      pv.covtest[j] = covtest.pval(obj,sigma,j)
    }

    khat = forwardStop(pv,alpha)
  }
  
  else {
    if (type == "aic") {
      out = aicStop(x,y,obj$action[1:k],obj$df[1:k],sigma,mult,ntimes)
      khat = out$khat
      GG = out$G
      uu = out$u
      kk = khat
    }
    else {
      GG = matrix(0,0,n)
      uu = c()
      kk = k
    }
    
    pv = vlo = vup = numeric(kk) 
    vmat = matrix(0,kk,n)
    ci = tailarea = matrix(0,kk,2)
    sign = numeric(kk)
    vars = obj$action[1:kk]

    G = rbind(GG,G[1:nk[kk],])
    u = c(uu,rep(0,nk[kk]))
    xa = x[,vars]
    M = solve(crossprod(xa),t(xa))
    
    for (j in 1:kk) {
      vj = M[j,]
      sign[j] = sign(sum(vj*y))
      
      vj = vj / sqrt(sum(vj^2))
      vj = sign[j] * vj
      Gj = rbind(G,vj)
      uj = c(u,0)

      a = poly.pval(y,Gj,uj,vj,sigma)
      pv[j] = a$pv
      vlo[j] = a$vlo
      vup[j] = a$vup
      vmat[j,] = vj

      a = poly.int(y,Gj,uj,vj,sigma,alpha,gridfac=gridfac,gridpts=gridpts,
        flip=(sign[j]==-1))
      ci[j,] = a$int
      tailarea[j,] = a$tailarea
    }
  }
  
  out = list(type=type,k=k,khat=khat,pv=pv,ci=ci,
    tailarea=tailarea,vlo=vlo,vup=vup,vmat=vmat,y=y,
    pv.spacing=pv.spacing,pv.asymp=pv.asymp,pv.covtest=pv.covtest,
    vars=vars,sign=sign,sigma=sigma,alpha=alpha,
    call=this.call)
  class(out) = "larInf"
  return(out)
}

##############################

spacing.pval <- function(obj, sigma, k) {
  v = obj$Gamma[obj$nk[k],]
  sd = sigma*sqrt(sum(v^2))
  a = obj$mp[k]
  
  if (k==1) b = Inf
  else b = obj$lambda[k-1]
  
  return(tnorm.surv(obj$lambda[k],0,sd,a,b))
}

asymp.pval <- function(obj, sigma, k) {
  v = obj$Gamma[obj$nk[k],]
  sd = sigma*sqrt(sum(v^2))

  if (k < length(obj$action)) a = obj$lambda[k+1]
  else if (obj$completepath) a = 0
  else {
    stop(sprintf("Asymptotic p-values at step %i require %i steps of the lar path",k,k+1))
  }
      
  if (k==1) b = Inf
  else b = obj$lambda[k-1]

  return(tnorm.surv(obj$lambda[k],0,sd,a,b))
}

covtest.pval <- function(obj, sigma, k) {
  A = which(obj$beta[,k]!=0)
  sA = sign(obj$beta[A,k])
  lam1 = obj$lambda[k]
  j = obj$action[k]

  if (k < length(obj$action)) {
    lam2 = obj$lambda[k+1]
    sj = sign(obj$beta[j,k+1])
  } else if (obj$completepath) {
    lam2 = 0
    sj = sign(obj$bls[j])
  } else {
    stop(sprintf("Cov test p-values at step %i require %i steps of the lar path",k,k+1))
  }

  x = obj$x
  if (length(A)==0) term1 = 0
  else term1 = x[,A,drop=F] %*% solve(crossprod(x[,A,drop=F]),sA)
  term2 = x[,c(A,j),drop=F] %*% solve(crossprod(x[,c(A,j),drop=F]),c(sA,sj))
  c = sum((term2 - term1)^2)
  t = c * lam1 * (lam1-lam2) / sigma^2
  return(1-pexp(t))
}

##############################

print.lar <- function(obj, ...) {
  cat("\nCall:\n")
  dput(obj$call)
  
  cat("\nSequence of LAR moves:\n")
  nsteps = length(obj$action)
  tab = cbind(1:nsteps,obj$action,obj$sign)
  colnames(tab) = c("Step","Var","Sign")
  rownames(tab) = rep("",nrow(tab))
  print(tab)
  invisible()
}

print.larInf <- function(obj) {
  cat("\nCall:\n")
  dput(obj$call)

  cat(sprintf("\nStandard deviation of noise (specified or estimated) sigma = %0.3f\n",
              obj$sigma))

  if (obj$type == "active") {
    cat(sprintf("\nSequential testing results with alpha = %0.3f\n",obj$alpha))
    tab = cbind(1:length(obj$pv),obj$vars,
      round(obj$sign*obj$vmat%*%obj$y,3),round(obj$pv,3),round(obj$ci,3),
      round(obj$tailarea,3),round(obj$pv.spacing,3),round(obj$pv.cov,3)) 
    colnames(tab) = c("Step", "Var", "Stdz Coef", "P-value", "Lo Conf Pt",
              "Up Conf Pt", "Lo Area", "Up Area", "Spacing", "Cov Test")
    rownames(tab) = rep("",nrow(tab))
    print(tab)

    cat(sprintf("\nEstimated stopping point from ForwardStop rule = %i\n",obj$khat))
  }

  else if (obj$type == "all") {
    cat(sprintf("\nTesting results at step = %i, with alpha = %0.3f\n",obj$k,obj$alpha))
    tab = cbind(obj$vars,round(obj$sign*obj$vmat%*%obj$y,3),
      round(obj$pv,3),round(obj$ci,3),round(obj$tailarea,3))
    colnames(tab) = c("Var", "Stdz Coef", "P-value", "Lo Conf Pt", "Up Conf Pt",
              "Lo Area", "Up Area")
    rownames(tab) = rep("",nrow(tab))
    print(tab)
  }

  else if (obj$type == "aic") {
    cat(sprintf("\nTesting results at step = %i, with alpha = %0.3f\n",obj$k,obj$alpha))
    tab = cbind(obj$vars,round(obj$sign*obj$vmat%*%obj$y,3),
      round(obj$pv,3),round(obj$ci,3),round(obj$tailarea,3))
    colnames(tab) = c("Var", "Stdz Coef", "P-value", "Lo Conf Pt", "Up Conf Pt",
              "Lo Area", "Up Area")
    rownames(tab) = rep("",nrow(tab))
    print(tab)
    
    cat(sprintf("\nEstimated stopping point from AIC rule = %i\n",obj$khat))
  }

  invisible()
}

plot.lar <- function(obj, xvar=c("norm","step","lambda"), breaks=TRUE,
                     omit.zeros=TRUE) {
  
  if (obj$completepath) {
    k = length(obj$action)+1
    lambda = c(obj$lambda,0)
    beta = cbind(obj$beta,obj$bls)
  } else {
    k = length(obj$action)
    lambda = obj$lambda
    beta = obj$beta
  }
  
  xvar = match.arg(xvar)
  if (xvar=="norm") {
    x = colSums(abs(beta))
    xlab = "L1 norm"
  } else if (xvar=="step") {
    x = 1:k
    xlab = "Step"
  } else {
    x = lambda
    xlab = "Lambda"
  }

  if (omit.zeros) {
    jj = which(rowSums(abs(beta))==0)
    if (length(jj)>0) beta = beta[jj,]
    else beta = rep(0,k)
  }

  matplot(x,t(beta),xlab=xlab,ylab="Coefficients",type="l",lty=1)
  if (breaks) abline(v=x,lty=2)
  invisible()
}