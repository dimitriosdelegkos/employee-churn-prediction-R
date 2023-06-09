# Employee Churn Prediction
## The goal of this project is to make a model which can predict if an employee will leave a company, based on specific features. For this purpose, a series of different classification algorithms are being used.

# Import the libraries
library(plyr)
library(tidyverse)
library(RColorBrewer)
library(httpgd)
library(caTools)
library(caret)
library(rpart)
library(randomForest)
library(xgboost)
library(e1071)
library(h2o)

# Get the data
## The data includes employee informations, such as the salary, the department, the duration of being at the company, etc.
employees <- read.csv("data/hr_train.csv")
head(employees)

options(tibble.width = Inf)

# EDA and Preprocessing
employees <- employees %>% as_tibble()
head(employees)

## check the na values per column
employees %>%
    summarise_all(~ sum(is.na(.))) %>%
    gather(key = "column", value = "na_count")

## rename the sales column
employees <- employees %>% rename(department = sales)
summary(employees)

## create factors for the categorical variables
employees <- employees %>% mutate(
    department = factor(department),
    salary = factor(salary)
)
head(employees)
## Let's summarize the data per department
employees %>%
    group_by(department) %>%
    summarise(
        mean(satisfaction_level),
        mean(last_evaluation),
        mean(number_project),
        mean(average_montly_hours),
        mean(time_spend_company),
        mean(Work_accident),
        mean(left),
        mean(promotion)
    )

## Let's visualize the satisfaction level per department and salary
employees %>%
    group_by(department, salary) %>%
    summarise(satisfaction_level = mean(satisfaction_level)) %>%
    ggplot(mapping = aes(x = department, y = salary, fill = satisfaction_level)) +
    geom_tile() +
    scale_fill_distiller(palette = "Spectral", direction = +1)

## Let's explore the time_spend_company column
employees %>%
    select(time_spend_company) %>%
    ggplot() +
    geom_boxplot(aes(x = time_spend_company)) +
    coord_flip()

## Let's explore the above outliers
outliers <- employees %>%
    filter(time_spend_company > 5) %>%
    select(left) %>%
    table()

prop.table(outliers)


## Compute the position of labels
data_for_pie_chart <- prop.table(outliers) %>%
    as.data.frame() %>%
    arrange(desc(Freq)) %>%
    mutate(prop = Freq / sum(Freq) * 100) %>%
    mutate(ypos = cumsum(prop) - 0.5 * prop)

## Plot the pie chart
data_for_pie_chart %>%
    ggplot() +
    geom_bar(aes(x = "", y = prop, fill = c("remained: 76.1%", "left: 23.9%")), stat = "identity") +
    coord_polar("y", start = 0) +
    theme_void() +
    theme(legend.position = "none") +
    geom_text(aes(x = "", y = ypos, label = c("remained: 76.1%", "left: 23.9%")), color = "white", size = 6) +
    scale_fill_brewer(palette = "Set1") +
    ggtitle("Employees with 5+ years in the company")


## Filter the outliers
employees_without_outliers <- employees %>%
    filter(time_spend_company <= 5)

## Now, let's group them by department.
grouped_by_dep <- employees_without_outliers %>%
    group_by(department) %>%
    summarise(
        mean(satisfaction_level),
        mean(last_evaluation),
        mean(number_project),
        mean(average_montly_hours),
        mean(time_spend_company),
        mean(Work_accident),
        m_left = mean(left),
        mean(promotion)
    )

## Let's visualize the above results
grouped_by_dep %>% ggplot() +
    geom_col(aes(x = reorder(department, -m_left), y = m_left, fill = department))

## Let's explore the Average Montly Hours per department and salary.
employees_without_outliers %>%
    group_by(department, salary) %>%
    summarise(avg_monthly_hours = mean(average_montly_hours)) %>%
    ggplot(mapping = aes(x = department, y = salary, fill = avg_monthly_hours)) +
    geom_tile() +
    scale_fill_distiller(palette = "Spectral", direction = -1) +
    ggtitle("Average Montly Hours per department/salary")

## Let's explore the Average Work accident per department and salary.
employees_without_outliers %>%
    group_by(department, salary) %>%
    summarise(avg_work_accident = mean(Work_accident)) %>%
    ggplot(mapping = aes(x = department, y = salary, fill = avg_work_accident)) +
    geom_tile() +
    scale_fill_distiller(palette = "Spectral", direction = -1) +
    ggtitle("Average Work accident per department/salary")

## Let's explore the Average Satisfaction Level per department and salary.
employees_without_outliers %>%
    group_by(department, salary) %>%
    summarise(avg_satisfaction_level = mean(satisfaction_level)) %>%
    ggplot(mapping = aes(x = department, y = salary, fill = avg_satisfaction_level)) +
    geom_tile() +
    scale_fill_distiller(palette = "Spectral", direction = +1) +
    ggtitle("Average Satisfaction Level per department/salary")

## Let's explore the Average Leave per department and salary.
employees_without_outliers %>%
    group_by(department, salary) %>%
    summarise(avg_leave = mean(left)) %>%
    ggplot(mapping = aes(x = department, y = salary, fill = avg_leave)) +
    geom_tile() +
    scale_fill_distiller(palette = "Spectral", direction = -1) +
    ggtitle("Average Leave per department/salary")

# Dealing with categorical features

## 'Salary' column is ordinal , so i will do a Label Encoding
employees_without_outliers <- employees_without_outliers %>%
    mutate(salary = as.numeric(as_factor(factor(salary, levels = c("low", "medium", "high"), labels = c(1, 2, 3)))))

## Apply One-Hot Encoding to the 'department' column
employees_cleaned <- dummyVars(" ~ .", data = employees_without_outliers) %>%
    predict(employees_without_outliers) %>%
    as_tibble()

# Scale the data
col_to_be_scaled <- c("number_project", "average_montly_hours", "time_spend_company", "salary")
employees_scaled <- employees_cleaned %>% as.data.frame()

scaler.info <- employees_scaled[, col_to_be_scaled] %>% scale()

employees_scaled[, col_to_be_scaled] <- employees_scaled[, col_to_be_scaled] %>% scale()

employees_scaled %>% glimpse()

# Train - Test Split
set.seed(123)
split_mask <- sample.split(employees_scaled$left, SplitRatio = 0.8)
training_set <- subset(employees_scaled, split_mask == TRUE)
test_set <- subset(employees_scaled, split_mask == FALSE)

dim(training_set)
dim(test_set)

# Class Imbalance
employees_scaled %>%
    select(left) %>%
    table()

model_weights <- ifelse(training_set$left == 0, 0.71, 1.68) # for class imbalance

# Train different classification algorithms

## Logistic Regression
logr <- train(left ~ ., data = training_set, method = "glm", family = "binomial", trControl = trainControl(method = "cv", number = 10), weights = model_weights)
logr
predictions <- predict(logr, test_set)
predictions <- ifelse(predictions > 0.5, 1, 0)
predictions <- data.frame(predictions)

## Confusion Matrix
cm1 <- table(as.matrix(test_set[, 7]), as.matrix(predictions))
cm1

## Accuracy
accuracy1 <- sum(diag(cm1)) / sum(cm1)
accuracy1

## Decision Tree Classifier
dtc <- rpart(formula = left ~ ., data = training_set, weights = model_weights)
pred <- predict(dtc, test_set)
pred <- ifelse(pred > 0.5, 1, 0)

## Confusion Matrix
cm2 <- table(as.matrix(test_set[, 7]), as.matrix(as.numeric(pred)))
cm2

## Accuracy
accuracy2 <- sum(diag(cm2)) / sum(cm2)
accuracy2

## Random Forest Classifier
rfc <- randomForest(left ~ ., data = training_set, ntree = 100, importance = TRUE, weights = model_weights)
pred <- predict(rfc, test_set)
pred <- ifelse(pred > 0.5, 1, 0)

## Confusion Matrix
cm3 <- table(as.matrix(test_set[, 7]), as.matrix(pred))
cm3

## Accuracy
accuracy3 <- sum(diag(cm3)) / sum(cm3)
accuracy3

## XGBOOST Classifier
xgbc <- xgboost(data = as.matrix(training_set[, -7]), label = training_set$left, nrounds = 100, weights = model_weights)
pred <- predict(xgbc, newdata = as.matrix(test_set[, -7]))
pred <- ifelse(pred > 0.5, 1, 0)

## Confusion Matrix
cm4 <- table(as.matrix(test_set[, 7]), as.matrix(pred))
cm4

## Accuracy
accuracy4 <- sum(diag(cm4)) / sum(cm4)
accuracy4

## Naive Bayes Classifier
nb <- naiveBayes(left ~ ., data = training_set)
pred <- predict(nb, test_set)

## Confusion Matrix
cm5 <- table(as.matrix(test_set[, 7]), as.matrix(as.numeric(pred)))
cm5

## Accuracy
accuracy5 <- sum(diag(cm5)) / sum(cm5)
accuracy5

## KNN Classifier
knn <- train(factor(left) ~ ., data = training_set, method = "knn", trControl = trainControl(method = "cv", number = 10), weights = model_weights)
pred <- predict(nb, test_set)

## Confusion Matrix
cm6 <- table(as.matrix(test_set[, 7]), as.matrix(as.numeric(levels(pred))[pred]))
cm6

## Accuracy
accuracy6 <- sum(diag(cm6)) / sum(cm6)
accuracy6

## Support Vector Classifier
svc <- svm(left ~ ., data = training_set, weights = model_weights, type = "C-classification")
pred <- predict(svc, test_set)

## Confusion Matrix
cm7 <- table(as.matrix(test_set[, 7]), as.matrix(as.numeric(levels(pred))[pred]))
cm7

## Accuracy
accuracy7 <- sum(diag(cm7)) / sum(cm7)
accuracy7

## Artificial Neural Network
h2o.init(nthreads = -1)

training_set$left <- as.factor(training_set$left)
test_set$left <- as.factor(test_set$left)

model <- h2o.deeplearning(
    y = "left",
    training_frame = as.h2o(training_set),
    hidden = c(10, 10),
    epochs = 100,
    activation = "Rectifier",
    train_samples_per_iteration = -2
)

pred <- h2o.predict(model, newdata = as.h2o(test_set))
pred <- pred[, 1]

## Confusion Matrix
cm8 <- table(as.matrix(test_set[, 7]), as.matrix(pred))
cm8

## Accuracy
accuracy8 <- sum(diag(cm8)) / sum(cm8)
accuracy8

# Overall Comparison
models <- c("Logistic Regression", "Decision Tree", "Random Forest", "XGBoost", "Naive Bayes", "KNN", "SVM", "ANN")
accuracy <- c(accuracy1, accuracy2, accuracy3, accuracy4, accuracy5, accuracy6, accuracy7, accuracy8)

accuracy_df <- data.frame(models, accuracy)
accuracy_df <- accuracy_df %>% arrange(desc(accuracy))
accuracy_df

# Appendix

## Predict the churn rate for a new employee
test_prediction <- function(ls) {
    df_pred <- data.frame(matrix(nrow = 0, ncol = length(colnames(employees_cleaned[, -7]))))
    colnames(df_pred) <- colnames(employees_cleaned[, -7])
    df_pred[1, ] <- ls
    df_pred[1, col_to_be_scaled] <- scale(df_pred[1, col_to_be_scaled], attr(scaler.info, "scaled:center"), attr(scaler.info, "scaled:scale"))
    test_pred <- predict(rfc, df_pred)
    return(test_pred[[1]])
}

test_prediction(list(0.22, 0.46, 2, 150, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1))

test_prediction(list(0.2, 0.72, 6, 224, 4, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 2))

## Save the model and the scaler
saveRDS(rfc, "rfc.rds")
saveRDS(scaler.info, "scaler.rds")
