
#  PROJECT  : Customer Churn Prediction & Analysis
#  FILE     : churn_model.py
#  PURPOSE  : Connect to MySQL, train a Random Forest model,
#             and write predictions back to MySQL
#  AUTHOR   : Shivani




# STEP 1 — IMPORT LIBRARIES
# These are the tools Python needs to do the job


import mysql.connector                               # connects Python to MySQL
import pandas as pd                                  # handles data as tables
from sklearn.ensemble import RandomForestClassifier  # the ML model we are using
from sklearn.model_selection import train_test_split # splits data into train/test
from sklearn.metrics import accuracy_score, roc_auc_score, classification_report
from sklearn.preprocessing import LabelEncoder       # converts text columns to numbers



# STEP 2 — CONNECT TO MYSQL
# Python connects directly to our churn_db database


conn = mysql.connector.connect(
    host     = "localhost",   # MySQL is running on our own laptop
    user     = "root",        # default MySQL username
    password = "Destiny@2001",  # replace with your MySQL password
    database = "churn_db"     # the database we created in Phase 1
)

print("Connected to MySQL successfully!")



# STEP 3 — FETCH DATA FROM MYSQL
# We pull data from all tables using a SQL query
# Python reads this directly into a table (DataFrame)


query = """
    SELECT
        c.customer_id,
        c.age,
        c.gender,
        c.state,
        c.segment,
        con.contract_type,
        con.monthly_charges,
        con.payment_method,
        con.auto_renewal,
        con.churned,
        ROUND(DATEDIFF(con.end_date, con.start_date) / 30, 0) AS tenure_months,
        COALESCE(AVG(u.login_count), 0)                        AS avg_monthly_logins,
        COALESCE(AVG(u.feature_usage_score), 0)                AS avg_feature_score,
        COALESCE(AVG(u.nps_score), 5)                          AS avg_nps_score,
        COALESCE(SUM(u.support_tickets_raised), 0)             AS total_tickets_raised
    FROM customers c
    JOIN contracts con ON c.customer_id = con.customer_id
    LEFT JOIN usage_logs u ON c.customer_id = u.customer_id
    GROUP BY
        c.customer_id, c.age, c.gender, c.state, c.segment,
        con.contract_type, con.monthly_charges,
        con.payment_method, con.auto_renewal, con.churned,
        con.end_date, con.start_date
"""

# Load the SQL result directly into a pandas DataFrame (like an Excel table)
df = pd.read_sql(query, conn)

print(f"Data fetched: {len(df):,} rows and {len(df.columns)} columns")
print(f"   Overall churn rate: {df['churned'].mean():.1%}")



# STEP 4 — FEATURE ENGINEERING
# ML models only understand numbers — not text like "Male" or "SMB"
# LabelEncoder converts each unique text value into a number
# e.g. "Male"=1, "Female"=0, "Other"=2


model_df = df.copy()   # make a copy so original data stays safe

# Text columns that need to be converted to numbers
text_columns = ['gender', 'state', 'segment', 'contract_type', 'payment_method']

le = LabelEncoder()
for col in text_columns:
    model_df[col] = le.fit_transform(model_df[col])

print("Text columns converted to numbers")



# STEP 5 — DEFINE FEATURES AND TARGET
# Features (X) = columns the model learns FROM
# Target   (y) = column the model is trying to PREDICT (churned)
# Note: total_charges removed — it is mathematically derived
#       from monthly_charges x tenure which causes leakage


feature_columns = [
    'age',
    'gender',
    'state',
    'segment',
    'contract_type',
    'monthly_charges',
    'payment_method',
    'auto_renewal',
    'tenure_months',
    'avg_monthly_logins',
    'avg_feature_score'
]

X = model_df[feature_columns]   # features — what the model learns from
y = model_df['churned']          # target   — what the model predicts (0 or 1)

print(f"Features defined: {len(feature_columns)} columns")



# STEP 6 — SPLIT DATA INTO TRAINING AND TESTING SETS
# 80% of data is used to train the model
# 20% of data is kept aside to test how accurate it is
# The model never sees the test data during training


X_train, X_test, y_train, y_test = train_test_split(
    X, y,
    test_size    = 0.2,   # 20% for testing
    random_state = 42     # fixed so results are same every time you run
)

print(f"Data split — Training: {len(X_train):,} rows | Testing: {len(X_test):,} rows")



# STEP 7 — TRAIN THE RANDOM FOREST MODEL
# Random Forest builds many decision trees and combines results
# max_depth limits tree depth to prevent overfitting
# min_samples_leaf ensures each decision covers enough customers


model = RandomForestClassifier(
    n_estimators     = 100,   # build 100 decision trees
    max_depth        = 6,     # max 6 levels deep per tree — prevents overfitting
    min_samples_leaf = 10,    # each leaf needs at least 10 customers
    random_state     = 42     # fixed so results are reproducible
)

# This one line trains the entire model
model.fit(X_train, y_train)

print("Random Forest model trained successfully!")



# STEP 8 — EVALUATE THE MODEL
# We test the model on the 20% test data it has never seen
# Accuracy = % of predictions that were correct
# AUC Score = how well model separates churners from non-churners
#             1.0 = perfect | 0.5 = random guessing


y_pred       = model.predict(X_test)              # hard prediction: 0 or 1
y_pred_proba = model.predict_proba(X_test)[:, 1]  # probability: 0.0 to 1.0

accuracy = accuracy_score(y_test, y_pred)
auc      = roc_auc_score(y_test, y_pred_proba)

print("\n" + "="*50)
print("   MODEL EVALUATION RESULTS")
print("="*50)
print(f"   Accuracy  : {accuracy:.2%}")
print(f"   AUC Score : {auc:.4f}")
print("\n   Detailed Report:")
print(classification_report(y_test, y_pred, target_names=['Active', 'Churned']))
print("="*50)

# Show which features were most important for predictions
feature_importance = pd.DataFrame({
    'Feature'   : feature_columns,
    'Importance': model.feature_importances_
}).sort_values('Importance', ascending=False)

print("\n   Top 5 features driving churn:")
print(feature_importance.head(5).to_string(index=False))



# STEP 9 — GENERATE PREDICTIONS FOR ALL 5,000 CUSTOMERS
# Now we use the trained model to predict churn for
# every single customer in the database


all_predictions   = model.predict(X)              # 0 = stay, 1 = churn
all_probabilities = model.predict_proba(X)[:, 1]  # probability 0.0 to 1.0

# Assign risk segment based on churn probability
def assign_risk(prob):
    if prob >= 0.60:
        return 'High Risk'     # more than 60% chance of churning
    elif prob >= 0.30:
        return 'Medium Risk'   # 30% to 60% chance of churning
    else:
        return 'Low Risk'      # less than 30% chance of churning

# Build the predictions DataFrame
predictions_df = pd.DataFrame({
    'customer_id'       : df['customer_id'],
    'churn_predicted'   : all_predictions,
    'churn_probability' : all_probabilities.round(4),
    'risk_segment'      : [assign_risk(p) for p in all_probabilities]
})

print(f"\n Predictions generated for all {len(predictions_df):,} customers")
print(f"   High Risk   : {(predictions_df.risk_segment == 'High Risk').sum():,} customers")
print(f"   Medium Risk : {(predictions_df.risk_segment == 'Medium Risk').sum():,} customers")
print(f"   Low Risk    : {(predictions_df.risk_segment == 'Low Risk').sum():,} customers")



# STEP 10 — CREATE PREDICTIONS TABLE IN MYSQL
# We create a new table called 'predictions' in churn_db
# and insert all 5,000 predictions into it
# Raw data tables are never touched or modified


cursor = conn.cursor()

# Drop table if it already exists so we can rerun safely
cursor.execute("DROP TABLE IF EXISTS predictions")

# Create the new predictions table
cursor.execute("""
    CREATE TABLE predictions (
        customer_id         INT PRIMARY KEY,
        churn_predicted     BOOLEAN,
        churn_probability   DECIMAL(6,4),
        risk_segment        VARCHAR(20),
        FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
    )
""")

# Insert all predictions into MySQL
insert_query = """
    INSERT INTO predictions
        (customer_id, churn_predicted, churn_probability, risk_segment)
    VALUES
        (%s, %s, %s, %s)
"""

rows = list(predictions_df.itertuples(index=False, name=None))
cursor.executemany(insert_query, rows)

# Commit saves the data permanently to the database
conn.commit()

print(f"\n{len(predictions_df):,} predictions saved to MySQL table 'predictions'")



# STEP 11 — VERIFY DATA WAS SAVED CORRECTLY
# Quick check to confirm predictions table exists in MySQL


verify = pd.read_sql("""
    SELECT
        risk_segment,
        COUNT(*)                        AS customers,
        ROUND(AVG(churn_probability)*100, 1) AS avg_churn_prob_pct
    FROM predictions
    GROUP BY risk_segment
    ORDER BY avg_churn_prob_pct DESC
""", conn)

print("\n   Predictions table saved in MySQL:")
print(verify.to_string(index=False))



# STEP 12 — CLOSE CONNECTION
# Always close the database connection when done


cursor.close()
conn.close()

print("\nMySQL connection closed")
print("\nPhase 2 Complete!")
print("   Predictions table is now live in MySQL.")
print("   Ready to connect Power BI for Phase 3!")