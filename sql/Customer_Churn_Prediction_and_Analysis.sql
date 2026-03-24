-- ============================================================
--  PROJECT  : Customer Churn Prediction & Analysis
--  FILE     : 01_schema.sql
--  PURPOSE  : Create all tables required for the project
--  DATABASE : MySQL
--  AUTHOR   : Shivani
-- ============================================================
 
-- Create and select the database
CREATE DATABASE IF NOT EXISTS churn_db;
USE churn_db;

-- ============================================================
-- TABLE 1: customers
-- Stores core demographic and account info for each customer
-- ============================================================
CREATE TABLE IF NOT EXISTS customers (
    customer_id     INT PRIMARY KEY AUTO_INCREMENT,
    full_name       VARCHAR(100)    NOT NULL,
    email           VARCHAR(150)    UNIQUE NOT NULL,
    gender          VARCHAR(10),
    age             INT,
    state           VARCHAR(50),
    segment         VARCHAR(30),        -- 'SMB', 'Mid-Market', 'Enterprise'
    signup_date     DATE
);
-- ============================================================
-- TABLE 2: products
-- Stores the subscription plans offered by the company
-- ============================================================
CREATE TABLE IF NOT EXISTS products (
    product_id      INT PRIMARY KEY AUTO_INCREMENT,
    product_name    VARCHAR(80)     NOT NULL,
    category        VARCHAR(50),
    monthly_price   DECIMAL(8,2)
);


-- ============================================================
-- TABLE 3: contracts
-- One row per customer contract — the core churn fact table
-- churned = 1 means the customer has already left
-- ============================================================
CREATE TABLE IF NOT EXISTS contracts (
    contract_id         INT PRIMARY KEY AUTO_INCREMENT,
    customer_id         INT,
    product_id          INT,
    contract_type       VARCHAR(20),
    start_date          DATE,
    end_date            DATE,
    monthly_charges     DECIMAL(8,2),
    total_charges       DECIMAL(10,2),
    payment_method      VARCHAR(40),
    auto_renewal        BOOLEAN,
    churned             BOOLEAN DEFAULT FALSE,
    churn_date          DATE,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    FOREIGN KEY (product_id)  REFERENCES products(product_id)
);


-- ============================================================
-- TABLE 4: usage_logs
-- Monthly product usage per customer
-- Low usage = strong churn signal
-- ============================================================
CREATE TABLE IF NOT EXISTS usage_logs (
    usage_id                INT PRIMARY KEY AUTO_INCREMENT,
    customer_id             INT,
    usage_month             DATE,
    login_count             INT,
    feature_usage_score     DECIMAL(5,2),  -- 0 to 100
    support_tickets_raised  INT,
    nps_score               INT,           -- Net Promoter Score 1-10, NULL if not surveyed
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);



-- ============================================================
-- TABLE 5: support_tickets
-- Individual support ticket records
-- High tickets + low resolution = churn risk
-- ============================================================
CREATE TABLE IF NOT EXISTS support_tickets (
    ticket_id       INT PRIMARY KEY AUTO_INCREMENT,
    customer_id     INT,
    opened_date     DATE,
    resolved_date   DATE,
    severity        VARCHAR(20),
    resolved        BOOLEAN,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

SELECT 'products'        AS table_name, COUNT(*) AS row_count FROM products
UNION ALL
SELECT 'customers',       COUNT(*) FROM customers
UNION ALL
SELECT 'contracts',       COUNT(*) FROM contracts
UNION ALL
SELECT 'usage_logs',      COUNT(*) FROM usage_logs
UNION ALL
SELECT 'support_tickets', COUNT(*) FROM support_tickets;


-- ============================================================
-- KPI 1: OVERALL CHURN RATE
-- Business Question: What percentage of our customers have churned?
-- Why it matters: This is the headline metric — the single number
--                 every stakeholder wants to see first.
-- ============================================================

SELECT
    COUNT(*)                                        AS total_customers,
    SUM(churned)                                    AS total_churned,
    COUNT(*) - SUM(churned)                         AS total_active,
    ROUND(SUM(churned) / COUNT(*) * 100, 2)         AS churn_rate_pct
FROM contracts;


-- ============================================================
-- KPI 2: CHURN RATE BY CUSTOMER SEGMENT
-- Business Question: Which segment — SMB, Mid-Market, or
--                    Enterprise — has the highest churn?
-- Why it matters: Helps the business decide where to focus
--                 retention efforts and budget.
-- ============================================================

SELECT
    c.segment,
    COUNT(*)                                        AS total_customers,
    SUM(con.churned)                                AS churned_customers,
    ROUND(SUM(con.churned) / COUNT(*) * 100, 2)     AS churn_rate_pct,
    -- Average monthly revenue per segment
    ROUND(AVG(con.monthly_charges), 2)              AS avg_monthly_charges
FROM customers c
JOIN contracts con ON c.customer_id = con.customer_id
GROUP BY c.segment
ORDER BY churn_rate_pct DESC;


-- ============================================================
-- KPI 3: CHURN RATE BY CONTRACT TYPE
-- Business Question: Do monthly customers churn more than
--                    annual customers?
-- Why it matters: Justifies pushing customers toward annual
--                 contracts as a retention strategy.
-- ============================================================

SELECT
    contract_type,
    COUNT(*)                                        AS total_customers,
    SUM(churned)                                    AS churned_customers,
    ROUND(SUM(churned) / COUNT(*) * 100, 2)         AS churn_rate_pct
FROM contracts
GROUP BY contract_type
ORDER BY churn_rate_pct DESC;


-- ============================================================
-- KPI 4: MONTHLY RECURRING REVENUE (MRR) LOST TO CHURN
-- Business Question: How much revenue are we losing every month
--                    because of churned customers?
-- Why it matters: Translates churn from a % into a rupee/dollar
--                 value — makes it real for finance teams.
-- ============================================================

SELECT
    ROUND(SUM(CASE WHEN churned = 1 THEN monthly_charges ELSE 0 END), 2)   AS mrr_lost,
    ROUND(SUM(CASE WHEN churned = 0 THEN monthly_charges ELSE 0 END), 2)   AS mrr_retained,
    ROUND(SUM(monthly_charges), 2)                                          AS total_mrr,
    ROUND(
        SUM(CASE WHEN churned = 1 THEN monthly_charges ELSE 0 END)
        / SUM(monthly_charges) * 100, 2
    )                                                                       AS pct_revenue_at_risk
FROM contracts;


-- ============================================================
-- KPI 5: CHURN BY STATE
-- Business Question: Which states have the highest churn?
-- Why it matters: Uncovers regional patterns — could indicate
--                 localised service issues or competitor activity.
-- ============================================================

SELECT
    c.state,
    COUNT(*)                                        AS total_customers,
    SUM(con.churned)                                AS churned_customers,
    ROUND(SUM(con.churned) / COUNT(*) * 100, 2)     AS churn_rate_pct
FROM customers c
JOIN contracts con ON c.customer_id = con.customer_id
GROUP BY c.state
ORDER BY churn_rate_pct DESC;


-- ============================================================
-- KPI 6: CHURN RATE BY PRODUCT / PLAN
-- Business Question: Which product plan loses the most customers?
-- Why it matters: Reveals if a specific plan has pricing,
--                 feature, or onboarding problems.
-- ============================================================

SELECT
    p.product_name,
    COUNT(*)                                        AS total_customers,
    SUM(con.churned)                                AS churned_customers,
    ROUND(SUM(con.churned) / COUNT(*) * 100, 2)     AS churn_rate_pct,
    ROUND(AVG(con.monthly_charges), 2)              AS avg_monthly_charges
FROM contracts con
JOIN products p ON con.product_id = p.product_id
GROUP BY p.product_name
ORDER BY churn_rate_pct DESC;


-- ============================================================
-- KPI 7: IMPACT OF AUTO-RENEWAL ON CHURN
-- Business Question: Do customers without auto-renewal churn more?
-- Why it matters: Supports the business case for enabling
--                 auto-renewal by default.
-- ============================================================

SELECT
    CASE WHEN auto_renewal = 1 THEN 'Auto-Renewal ON'
         ELSE 'Auto-Renewal OFF' END                AS auto_renewal_status,
    COUNT(*)                                        AS total_customers,
    SUM(churned)                                    AS churned_customers,
    ROUND(SUM(churned) / COUNT(*) * 100, 2)         AS churn_rate_pct
FROM contracts
GROUP BY auto_renewal
ORDER BY churn_rate_pct DESC;


-- ============================================================
-- KPI 8: AVERAGE TENURE OF CHURNED vs ACTIVE CUSTOMERS
-- Business Question: How long do churned customers stay before
--                    leaving compared to active ones?
-- Why it matters: Tells us the "danger window" — when customers
--                 are most at risk of leaving.
-- ============================================================

SELECT
    CASE WHEN churned = 1 THEN 'Churned' ELSE 'Active' END  AS customer_status,
    COUNT(*)                                                  AS total_customers,
    -- DATEDIFF gives number of days between two dates
    ROUND(AVG(DATEDIFF(end_date, start_date) / 30), 1)       AS avg_tenure_months,
    ROUND(AVG(monthly_charges), 2)                            AS avg_monthly_charges,
    ROUND(AVG(total_charges), 2)                              AS avg_lifetime_value
FROM contracts
GROUP BY churned;


-- ============================================================
-- KPI 9: CHURN TREND BY MONTH
-- Business Question: Is churn getting better or worse over time?
-- Why it matters: Tracks whether retention initiatives are working.
--                 Used to draw the trend line in Power BI.
-- ============================================================

SELECT
    -- Extract year and month from churn_date
    DATE_FORMAT(churn_date, '%Y-%m')                AS churn_month,
    COUNT(*)                                        AS customers_churned,
    ROUND(SUM(monthly_charges), 2)                  AS revenue_lost
FROM contracts
WHERE churned = 1
  AND churn_date IS NOT NULL
GROUP BY DATE_FORMAT(churn_date, '%Y-%m')
ORDER BY churn_month;


-- ============================================================
-- KPI 10: AVERAGE USAGE STATS — CHURNED vs ACTIVE
-- Business Question: How differently do churned customers
--                    behave compared to active ones?
-- Why it matters: Proves that usage metrics are valid churn
--                 signals — validates the ML features we'll use.
-- ============================================================

SELECT
    CASE WHEN con.churned = 1 THEN 'Churned' ELSE 'Active' END  AS customer_status,
    ROUND(AVG(u.login_count), 1)                                 AS avg_monthly_logins,
    ROUND(AVG(u.feature_usage_score), 1)                         AS avg_feature_score,
    ROUND(AVG(u.support_tickets_raised), 2)                      AS avg_support_tickets,
    ROUND(AVG(u.nps_score), 1)                                   AS avg_nps_score
FROM usage_logs u
JOIN contracts con ON u.customer_id = con.customer_id
GROUP BY con.churned;


-- ============================================================
-- KPI 11: TOP 10 HIGH-VALUE CUSTOMERS WHO CHURNED
-- Business Question: Who are our most valuable lost customers?
-- Why it matters: Prioritises win-back campaigns — going after
--                 high-value churned customers first.
-- ============================================================

SELECT
    c.customer_id,
    c.full_name,
    c.segment,
    c.state,
    con.product_name_ref,
    con.monthly_charges,
    con.total_charges                               AS lifetime_value,
    con.churn_date
FROM customers c
JOIN (
    SELECT con.*, p.product_name AS product_name_ref
    FROM contracts con
    JOIN products p ON con.product_id = p.product_id
    WHERE con.churned = 1
) con ON c.customer_id = con.customer_id
ORDER BY con.total_charges DESC
LIMIT 10;


-- ============================================================
-- KPI 12: SUPPORT TICKET SEVERITY FOR CHURNED vs ACTIVE
-- Business Question: Do churned customers raise more critical
--                    support tickets?
-- Why it matters: Links poor support experience directly to
--                 churn — a case for improving support SLAs.
-- ============================================================

SELECT
    CASE WHEN con.churned = 1 THEN 'Churned' ELSE 'Active' END  AS customer_status,
    st.severity,
    COUNT(*)                                                      AS ticket_count,
    ROUND(AVG(
        CASE WHEN st.resolved = 1
             THEN DATEDIFF(st.resolved_date, st.opened_date)
        END
    ), 1)                                                         AS avg_resolution_days
FROM support_tickets st
JOIN contracts con ON st.customer_id = con.customer_id
GROUP BY con.churned, st.severity
ORDER BY customer_status, ticket_count DESC;


-- ============================================================
-- KPI 13: PAYMENT METHOD vs CHURN
-- Business Question: Does the payment method affect churn?
-- Why it matters: Customers on manual payment methods (like
--                 net banking) may forget to renew — a UPI or
--                 auto-debit nudge could reduce churn.
-- ============================================================

SELECT
    payment_method,
    COUNT(*)                                        AS total_customers,
    SUM(churned)                                    AS churned_customers,
    ROUND(SUM(churned) / COUNT(*) * 100, 2)         AS churn_rate_pct
FROM contracts
GROUP BY payment_method
ORDER BY churn_rate_pct DESC;


-- ============================================================
-- FINAL VIEW: MASTER KPI TABLE FOR POWER BI
-- Combines customer info + contract + usage averages
-- into one clean table that Power BI will import directly.
-- ============================================================

CREATE OR REPLACE VIEW vw_master_churn AS
SELECT
    c.customer_id,
    c.full_name,
    c.gender,
    c.age,
    c.state,
    c.segment,
    c.signup_date,
    con.contract_type,
    con.monthly_charges,
    con.total_charges,
    con.payment_method,
    con.auto_renewal,
    con.churned,
    con.churn_date,
    ROUND(DATEDIFF(con.end_date, con.start_date) / 30, 0)   AS tenure_months,
    p.product_name,
    p.category                                               AS product_category,
    -- Aggregated usage signals
    ROUND(AVG(u.login_count), 1)                             AS avg_monthly_logins,
    ROUND(AVG(u.feature_usage_score), 1)                     AS avg_feature_score,
    ROUND(AVG(u.nps_score), 1)                               AS avg_nps_score,
    SUM(u.support_tickets_raised)                            AS total_tickets_raised
FROM customers c
JOIN contracts    con ON c.customer_id  = con.customer_id
JOIN products     p   ON con.product_id = p.product_id
LEFT JOIN usage_logs u ON c.customer_id = u.customer_id
GROUP BY
    c.customer_id, c.full_name, c.gender, c.age, c.state,
    c.segment, c.signup_date, con.contract_type, con.monthly_charges,
    con.total_charges, con.payment_method, con.auto_renewal,
    con.churned, con.churn_date, con.end_date, con.start_date,
    p.product_name, p.category;



