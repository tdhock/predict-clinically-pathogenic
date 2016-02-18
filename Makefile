figure-two-features.png: figure-two-features.R
	R --no-save < $<
figure-test-error.png: figure-test-error.R models.RData
	R --no-save < $<
models.RData: models.R folds.RData trainData.RData  
	R --no-save < $<
folds.RData: folds.R trainData.RData
	R --no-save < $<
trainData.RData: trainData.R
	R --no-save < $<
