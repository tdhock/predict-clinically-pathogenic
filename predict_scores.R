works_with_R("3.2.3",
             data.table="1.9.7",
             missMDA="1.10",
             glmnet="1.9.5",
             "tdhock/WeightedROC@ef8f35ba7ae85e2995fa66afe13732cebb8b5633",
             xgboost="0.4.4",
             party="1.0.13")

arg.vec <- c(
  "data-2016-11-09/train.txt.RData",
  "data-2016-11-09/test1.txt"
  )
arg.vec <- c(
  "data/2013to2016minus-HGMD.txt.RData",
  "data/2016-minusHGMD.txt"
  )

arg.vec <- commandArgs(trailingOnly=TRUE)

stopifnot(length(arg.vec)==2)
model.RData <- normalizePath(arg.vec[1], mustWork=TRUE)
test.txt <- normalizePath(arg.vec[2], mustWork=TRUE)
input.dt <- fread(test.txt, na.strings="-")
objs <- load(model.RData)

feature.name.vec <- univariate.model.list[[1]]$col.name
feature.in.test <- feature.name.vec %in% names(input.dt)
feature.missing <- feature.name.vec[!feature.in.test]
if(length(feature.missing)){
  stop(model.RData, " needs features listed above to predict, but ",
       test.txt, " does not have ",
       paste(feature.missing, collapse=", "))
}

test.features <- as.matrix(input.dt[, feature.name.vec, with=FALSE])

nb <- estim_ncpPCA(test.features)
test.mipca <- MIPCA(test.features, nb$ncp)
test.imputed <- test.mipca$res.imputePCA
test.df <- data.frame(
  test.features,
  check.names=FALSE)
## prediction function is
## ifelse(is.na(feature, na.guess,
##  ifelse(feature <= thresh, "Benign", "Pathogenic")
is.pathogenic <- 2
pred.fun.list <- list(
  ctree=function(fit){
    pred.list <- treeresponse(fit, test.df)
    sapply(pred.list, "[", is.pathogenic)
  },
  xgboost=function(fit){
    predict(fit, test.features, missing=NA)            
  },
  cforest=function(fit){
    pred.list <- treeresponse(fit, test.df)
    sapply(pred.list, "[", is.pathogenic)
  },
  glmnet=function(fit){
    pred.mat <- predict(fit, test.imputed, type="response")
    as.numeric(pred.mat)
  })

pred.score.dt.list <- list()
pred.label.dt.list <- list()
for(model.name in names(model.list)){
  model.prefix <- sub("[.].*", "", model.name)
  pred.fun <- pred.fun.list[[model.prefix]]
  model <- model.list[[model.name]]
  pred.score <- pred.fun(model)
  input.dt[[paste0(model.name, "_score")]] <- pred.score
  pred.score.dt.list[[model.name]] <- pred.score
  pred.label <- ifelse(
    pred.score <= 0.5, "Benign", "Pathogenic")
  input.dt[[paste0(model.name, "_pred")]] <- pred.label
  pred.label.dt.list[[model.name]] <- pred.label
}#model.name
out.classes.txt <- paste0(test.txt, "_predictions.txt")
cat("Writing ",
    nrow(input.dt), " rows and ",
    ncol(input.dt), " cols to ",
    out.classes.txt,
    "\n", sep="")
write.table(
  input.dt,
  out.classes.txt,
  quote=FALSE,
  sep="\t",
  row.names=FALSE,
  col.names=TRUE)

if("clinvar" %in% names(input.dt)){
  pred.score.dt.list$clinvar <- input.dt$clinvar
  for(weight.name in names(univariate.model.list)){
    univariate.model.dt <- univariate.model.list[[weight.name]]
    for(model.i in 1:nrow(univariate.model.dt)){
      model.info <- univariate.model.dt[model.i,]
      model.name <- paste0(
        model.info$col.name, ".weights=", weight.name)
      test.feature.vec <- input.dt[[paste(model.info$col.name)]]
      pred.score.vec <- ifelse(
        is.na(test.feature.vec),
        model.info$na.score,
        test.feature.vec*model.info$feature.sign)
      pred.score.dt.list[[model.name]] <- pred.score.vec
      pred.label.dt.list[[model.name]] <- ifelse(
        pred.score.vec <= model.info$thresh, "Benign", "Pathogenic")
    }
  }
  predictedScores <- list(
    scores=do.call(data.table, pred.score.dt.list),
    labels=do.call(data.table, pred.label.dt.list))
  out.scores.RData <- paste0(test.txt, "_predictions.RData")
  cat("Writing ",
      out.scores.RData,
      "\n", sep="")
  save(
    predictedScores,
    file=out.scores.RData)
}