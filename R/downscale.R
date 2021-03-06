#     downscale.R Perfect-prog downscaling methods
#
#     Copyright (C) 2017 Santander Meteorology Group (http://www.meteo.unican.es)
#
#     This program is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 3 of the License, or
#     (at your option) any later version.
# 
#     This program is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
# 
#     You should have received a copy of the GNU General Public License
#     along with this program.  If not, see <http://www.gnu.org/licenses/>.

#' @title Perfect-prog downscaling
#' 
#' @description Workhorse function to call the different perfect-prog downscaling methods
#' @param y The observations dataset. It should be an object as returned by \pkg{loadeR}.
#' @param x The input grid. It should be an object as returned by \pkg{loadeR}.
#' @param newdata It should be an object as returned by \pkg{loadeR} and consistent with x. Default is newdata = x.
#' @param method Downscaling method. Options are c = ("analogs","glm","lm"). Glm can only be set when downscaling precipitation. 
#' @param simulate A logic value indicating whether we want to simulate or not based on the GLM distributional parameters. Only relevant when perdicting with a GLM. Default to FALSE. 
#' @param n.analogs Applies only when \code{method="analogs"} (otherwise ignored). Integer indicating the number of closest neigbours to retain for analog construction. Default to 1.
#' @param sel.fun Applies only when \code{method="analogs"} (otherwise ignored). Criterion for the construction of analogs when several neigbours are chosen. Ignored when \code{n = 1}.
#' Current values are \code{"mean"} (the default), \code{"wmean"},  \code{"max"},  \code{"min"} and  \code{"median"}.
#' @param wet.threshold Value below which precipitation amount is considered zero 
#' @param n.pcs Integer indicating the number of EOFs to be used as predictors
#' @param cross.val Should cross-validation be performed? methods available are leave-one-out (\code{"loocv"})
#'  and k-fold (\code{"kfold"}). Default to \code{"none"}, which does not perform cross-validation.
#' @param folds This arguments controls the number of folds, or how these folds are created (ignored if \code{cross.val = "loocv"}). Folds are always splitted chronologically. If it is given as a fraction in the range (0-1), 
#' it splits the data in two subsets, one for training and one for testing, being the given value the fraction of the data used for training (i.e., 0.75 will split the data so that 75\% of the instances are used for training, and the remaining 25\% for testing). 
#' In case it is an integer value, it sets the number of folds in which the data will be split (e.g., \code{folds = 10} for the classical 10-fold cross validation). 
#' Alternatively, this argument can be passed as a list, each element of the list being a vector of years to be included in each fold (See examples). 
#' 
#' @details
#' \strong{Scaling and centering}
#' When the climate variables are used as predictors instead of the PCs, these are previously centered and scaled
#' using the mean and sigma parameters globally computed for the whole spatial domain.
#' @return The prediction structure.
#' @seealso 
#' downscaleTrain for training a downscaling model
#' downscalePredict for prediction for a a test dataset with a trained model for 
#' downscaleCV for automatic cross-validation 
#' \href{https://github.com/SantanderMetGroup/downscaleR/wiki/training-downscaling-models}{downscaleR Wiki} for downscaling seasonal forecasting and climate projections.
#' @export 
#' @family downscaling.functions
#' @importFrom transformeR scaleGrid
#' @examples \donttest{
#' require(transformeR)
#' require(climate4R.datasets)
#' data("NCEP_Iberia_hus850")
#' data("NCEP_Iberia_ta850")
#' x <- makeMultiGrid(NCEP_Iberia_hus850, NCEP_Iberia_ta850)
#' newdata <- subsetGrid(x, years = 1994:1995)
#' x <- subsetGrid(x, years = 1985:1993)
#' # Loading predictands
#' data("VALUE_Iberia_pr")
#' y <- VALUE_Iberia_pr
#' y <- getTemporalIntersection(obs = y,prd = x, "obs" )
#' x <- getTemporalIntersection(obs = y,prd = x, "prd" )
#' ### Analogs ###
#' # None
#' yp <- downscale(y, x, method = "analogs")
#' yp <- downscale(y, x, newdata, method = "analogs")
#' # kfold
#' yp <- downscale(y, x, method = "analogs", n.pcs = 15,
#'                 cross.val = "kfold", folds = list(c(1985, 1986, 1987),
#'                                                   c(1988, 1989, 1990),
#'                                                   c(1991, 1992, 1993)))
#' # Leave-one-year-out
#' yp <- downscale(y, x, method = "analogs", n.pcs = 15,
#'                 cross.val = "loocv")
#' 
#' ### GLM ###
#' # None
#' yp <- downscale(y, x, method = "glm", simulate = FALSE, n.pcs = 10,
#'                 wet.threshold = 1)
#' yp <- downscale(y, x, method = "glm", simulate = TRUE, n.pcs = 10,
#'                 wet.threshold = 1)
#' # kfold
#' yp <- downscale(y, x, method = "glm", simulate = FALSE, n.pcs = 10,
#'                 cross.val = "kfold", folds = list(c(1985, 1986, 1987),
#'                                                   c(1988, 1989, 1990),
#'                                                   c(1991, 1992, 1993)))
#' }

downscale <- function(y,
                       x,
                       newdata = x,
                       method = c("analogs", "glm","lm"),
                       simulate = c(FALSE, TRUE),
                       n.analogs = 1,
                       sel.fun = c("mean","wmean","max","min","median"),
                       wet.threshold = .1,
                       n.pcs = NULL,
                       cross.val = c("none", "loocv", "kfold"),
                       folds = NULL) {
  
  method <- match.arg(NULL,method)
  simulate <- match.arg(NULL,simulate)
  sel.fun <- match.arg(NULL,sel.fun)
  cross.val <- match.arg(NULL,cross.val)
  
  if (!identical(as.Date(getRefDates(x)),as.Date(getRefDates(y)))) {stop("Dates of x and y do not mach, please try using getTemporalIntersection function from package transformeR")}
  if (cross.val == "kfold" && is.null(folds)) message("Please, specify the number of folds with the parameter: folds")
  if (cross.val == "loocv") {
    sampling.strategy <- "leave-one-year-out"
  }
  if (cross.val == "kfold") {
    sampling.strategy <- "kfold.chronological"
  }
  
  if (!is.null(n.pcs)) {spatial.predictors <- list(n = c(rep(1,length(getVarNames(x))),n.pcs),which.combine = getVarNames(x))}
  else {spatial.predictors <- NULL}
  
  if (method == "glm") {
    if (isTRUE(simulate)) {
      y.ocu <- binaryGrid(y,threshold = 0.01)
      y <- binaryGrid(y,threshold = 0.01, partial = TRUE)}
    else{
      y.ocu <- binaryGrid(y,threshold = wet.threshold)  
      y <- binaryGrid(y,threshold = wet.threshold, partial = TRUE)  
    }
  }
  
  
  # Downscaling and cross-validation (if selected...)  
  if (cross.val == "none") {
    newdata <- scaleGrid(newdata,base = x, type = "standardize")
    x <- scaleGrid(x,base = x, type = "standardize")
    gridT <- prepareData(x,y,global.vars = getVarNames(x),spatial.predictors)
    gridt <- prepareNewData(newdata,gridT)
    if (method == "analogs") {
      model <- downscaleTrain(gridT,method = "analogs", n.analogs = n.analogs, sel.fun = sel.fun)
      yp <- downscalePredict(gridt,model, simulate = FALSE)
    }
    else if (method == "glm") {
      # Amounts
      model.reg <- downscaleTrain(gridT, method = "GLM", family = Gamma(link = "log"), condition = "GT", threshold = 0, simulate = simulate)
      yp.reg <- downscalePredict(gridt,model.reg,simulate = simulate)
      # Ocurrence
      gridT <- prepareData(x,y.ocu,global.vars = getVarNames(x),spatial.predictors)
      model.ocu <- downscaleTrain(gridT,method = "GLM", family = binomial(link = "logit"), simulate = simulate)
      yp.ocu <- downscalePredict(gridt,model.ocu,simulate = simulate)
      # Complete serie
      if (!isTRUE(simulate)) {
        yp.ocu <- binaryGrid(yp.ocu, ref.obs = y.ocu, ref.pred = yp.ocu)
      }
      yp <- y
      yp$Data <- yp.ocu$Data*yp.reg$Data
      if (isTRUE(simulate)) {
        yp <- binaryGrid(yp,threshold = wet.threshold, partial = TRUE)
      }
    }
    else if (method == "lm") {
      model <- downscaleTrain(gridT,method = "GLM", family = "gaussian")
      yp <- downscalePredict(gridt,model,simulate = simulate)
    }
  }  
  else {# Leave-one-out and cross-validation 
    if (method == "analogs") {
      yp <- downscaleCV(x,y,folds = folds, sampling.strategy = sampling.strategy, scaleGrid.args = list(type = "standardize"), prepareData.args = list("spatial.predictors" = spatial.predictors),
                         method = "analogs", n.analogs = n.analogs, sel.fun = sel.fun)
    }
    else if (method == "glm") {
      # Ocurrence
      yp.ocu <- downscaleCV(x,y.ocu,folds = folds, sampling.strategy = sampling.strategy, scaleGrid.args = list(type = "standardize"), prepareData.args = list("spatial.predictors" = spatial.predictors),
                             method = "GLM", family = binomial(link = "logit"), simulate = simulate)
      # Amounts
      yp.reg <- downscaleCV(x,y,folds = folds, sampling.strategy = sampling.strategy, scaleGrid.args = list(type = "standardize"), prepareData.args = list("spatial.predictors" = spatial.predictors),
                             method = "GLM", family = Gamma(link = "log"), condition = "GT", threshold = 0, simulate = simulate)
      # Complete serie
      yp <- y
      yp$Data <- gridArithmetics(subsetGrid(yp.ocu,var = "bin"),yp.reg,operator = "*")$Data
      if (isTRUE(simulate)) {
        yp <- binaryGrid(yp,threshold = wet.threshold, partial = TRUE)
      }
    }
    else if (method == "lm") {
      yp <- downscaleCV(x,y,folds = folds, sampling.strategy = sampling.strategy, scaleGrid.args = list(type = "standardize"), prepareData.args = list("spatial.predictors" = spatial.predictors),
                         method = "GLM", family = "gaussian")
    }
  }
  return(yp)
}
