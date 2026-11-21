-- Olist E-commerce Analytics | BigQuery Standard SQL
-- Project: analog-ace-512914-s0 | Dataset: olist
-- Tables: orders, order_items, payments, reviews, customers, products, sellers, category_translation
-- Ready to copy-paste: run each section one at a time, starting with section 0.

-- =========================================================
-- PRE-STEP (only if section 3 errors: "product_category_name not found inside t")
-- Run this ONCE to fix the category_translation column names, then continue.
-- Check names first:
--   SELECT column_name FROM `analog-ace-512914-s0.olist.INFORMATION_SCHEMA.COLUMNS`
--   WHERE table_name = 'category_translation';
-- If they are string_field_0 / string_field_1, run:
--   CREATE OR REPLACE TABLE `analog-ace-512914-s0.olist.category_translation` AS
--   SELECT CAST(string_field_0 AS STRING) AS product_category_name,
--          CAST(string_field_1 AS STRING) AS product_category_name_english
--   FROM `analog-ace-512914-s0.olist.category_translation`
--   WHERE string_field_0 != 'product_category_name';
-- =========================================================

-- =========================================================
-- 0. CLEAN BASE VIEW: delivered orders with delivery metrics
-- =========================================================
CREATE OR REPLACE VIEW `analog-ace-512914-s0.olist.clean_orders` AS
SELECT
  o.order_id,
  o.customer_id,
  c.customer_unique_id,
  c.customer_state,
  o.order_status,
  SAFE_CAST(o.order_purchase_timestamp AS TIMESTAMP)        AS purchase_ts,
  SAFE_CAST(o.order_delivered_customer_date AS TIMESTAMP)   AS delivered_ts,
  SAFE_CAST(o.order_estimated_delivery_date AS TIMESTAMP)   AS estimated_ts,
  TIMESTAMP_DIFF(SAFE_CAST(o.order_delivered_customer_date AS TIMESTAMP),
                 SAFE_CAST(o.order_purchase_timestamp AS TIMESTAMP), DAY) AS delivery_days,
  TIMESTAMP_DIFF(SAFE_CAST(o.order_delivered_customer_date AS TIMESTAMP),
                 SAFE_CAST(o.order_estimated_delivery_date AS TIMESTAMP), DAY) AS days_vs_estimate,
  IF(SAFE_CAST(o.order_delivered_customer_date AS TIMESTAMP)
       <= SAFE_CAST(o.order_estimated_delivery_date AS TIMESTAMP), 1, 0) AS on_time
FROM `analog-ace-512914-s0.olist.orders` o
JOIN `analog-ace-512914-s0.olist.customers` c USING (customer_id)
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL;

-- Sanity check: row counts and nulls
SELECT COUNT(*) AS delivered_orders,
       COUNTIF(delivery_days IS NULL) AS null_delivery_days
FROM `analog-ace-512914-s0.olist.clean_orders`;

-- =========================================================
-- 1. KPIs: revenue, orders, AOV, avg review, on-time %
-- =========================================================
WITH order_rev AS (
  SELECT order_id, SUM(price) AS revenue
  FROM `analog-ace-512914-s0.olist.order_items`
  GROUP BY order_id
),
order_review AS (  -- one row per order, avoids double counting multi-review orders
  SELECT order_id, AVG(review_score) AS review_score
  FROM `analog-ace-512914-s0.olist.reviews`
  GROUP BY order_id
)
SELECT
  ROUND(SUM(r.revenue), 0)                               AS total_revenue,
  COUNT(DISTINCT co.order_id)                            AS total_orders,
  ROUND(SUM(r.revenue) / COUNT(DISTINCT co.order_id), 2) AS avg_order_value,
  ROUND(AVG(rv.review_score), 2)                         AS avg_review_score,
  ROUND(100 * AVG(co.on_time), 1)                        AS on_time_pct
FROM `analog-ace-512914-s0.olist.clean_orders` co
JOIN order_rev r USING (order_id)
LEFT JOIN order_review rv USING (order_id);

-- =========================================================
-- 2. Monthly revenue trend with MoM growth (window function)
-- =========================================================
WITH monthly AS (
  SELECT
    DATE_TRUNC(DATE(co.purchase_ts), MONTH) AS month,
    SUM(oi.price)                           AS revenue,
    COUNT(DISTINCT co.order_id)             AS orders
  FROM `analog-ace-512914-s0.olist.clean_orders` co
  JOIN `analog-ace-512914-s0.olist.order_items` oi USING (order_id)
  GROUP BY month
)
SELECT
  month, revenue, orders,
  ROUND(100 * SAFE_DIVIDE(revenue - LAG(revenue) OVER (ORDER BY month),
                          LAG(revenue) OVER (ORDER BY month)), 1) AS mom_growth_pct
FROM monthly
WHERE month BETWEEN '2017-01-01' AND '2018-08-01'  -- full months only
ORDER BY month;

-- =========================================================
-- 3. Top 10 product categories by revenue (with share)
-- =========================================================
WITH cat AS (
  SELECT
    COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
    SUM(oi.price) AS revenue,
    COUNT(DISTINCT oi.order_id) AS orders
  FROM `analog-ace-512914-s0.olist.order_items` oi
  JOIN `analog-ace-512914-s0.olist.clean_orders` co USING (order_id)
  JOIN `analog-ace-512914-s0.olist.products` p USING (product_id)
  LEFT JOIN `analog-ace-512914-s0.olist.category_translation` t
    ON p.product_category_name = t.product_category_name
  GROUP BY category
)
SELECT category, ROUND(revenue, 0) AS revenue, orders,
       ROUND(100 * revenue / SUM(revenue) OVER (), 1) AS revenue_share_pct
FROM cat
ORDER BY revenue DESC
LIMIT 10;

-- =========================================================
-- 4. Revenue and satisfaction by state
-- =========================================================
SELECT
  co.customer_state,
  COUNT(DISTINCT co.order_id)          AS orders,
  ROUND(SUM(oi.price), 0)              AS revenue,
  ROUND(AVG(co.delivery_days), 1)      AS avg_delivery_days,
  ROUND(100 * AVG(co.on_time), 1)      AS on_time_pct
FROM `analog-ace-512914-s0.olist.clean_orders` co
JOIN `analog-ace-512914-s0.olist.order_items` oi USING (order_id)
GROUP BY co.customer_state
ORDER BY revenue DESC;

-- =========================================================
-- 5. KEY INSIGHT: delivery delay vs review score
-- =========================================================
SELECT
  CASE
    WHEN days_vs_estimate <= -7 THEN '1. 7+ days early'
    WHEN days_vs_estimate <= 0  THEN '2. On time / early'
    WHEN days_vs_estimate <= 7  THEN '3. 1-7 days late'
    ELSE                             '4. 7+ days late'
  END AS delivery_bucket,
  COUNT(*)                          AS orders,
  ROUND(AVG(rv.review_score), 2)    AS avg_review_score,
  ROUND(100 * COUNTIF(rv.review_score <= 2) / COUNT(*), 1) AS pct_bad_reviews
FROM `analog-ace-512914-s0.olist.clean_orders` co
JOIN (SELECT order_id, AVG(review_score) AS review_score
      FROM `analog-ace-512914-s0.olist.reviews` GROUP BY order_id) rv USING (order_id)
GROUP BY delivery_bucket
ORDER BY delivery_bucket;

-- =========================================================
-- 6. Repeat-customer rate
-- =========================================================
WITH cust AS (
  SELECT customer_unique_id, COUNT(DISTINCT order_id) AS orders
  FROM `analog-ace-512914-s0.olist.clean_orders`
  GROUP BY customer_unique_id
)
SELECT
  COUNT(*)                              AS customers,
  COUNTIF(orders > 1)                   AS repeat_customers,
  ROUND(100 * COUNTIF(orders > 1) / COUNT(*), 2) AS repeat_rate_pct
FROM cust;

-- =========================================================
-- 7. Payment mix
-- =========================================================
SELECT
  payment_type,
  COUNT(DISTINCT order_id)             AS orders,
  ROUND(SUM(payment_value), 0)         AS value,
  ROUND(100 * SUM(payment_value) / SUM(SUM(payment_value)) OVER (), 1) AS value_share_pct,
  ROUND(AVG(payment_installments), 1)  AS avg_installments
FROM `analog-ace-512914-s0.olist.payments`
GROUP BY payment_type
ORDER BY value DESC;

-- =========================================================
-- 8. Seller performance: top 15 by revenue with rank + review
-- =========================================================
WITH seller_stats AS (
  SELECT
    oi.seller_id,
    ROUND(SUM(oi.price), 0)          AS revenue,
    COUNT(DISTINCT oi.order_id)      AS orders,
    ROUND(AVG(rv.review_score), 2)   AS avg_review,
    ROUND(100 * AVG(co.on_time), 1)  AS on_time_pct
  FROM `analog-ace-512914-s0.olist.order_items` oi
  JOIN `analog-ace-512914-s0.olist.clean_orders` co USING (order_id)
  LEFT JOIN (SELECT order_id, AVG(review_score) AS review_score
             FROM `analog-ace-512914-s0.olist.reviews` GROUP BY order_id) rv USING (order_id)
  GROUP BY oi.seller_id
  HAVING orders >= 30
)
SELECT *, RANK() OVER (ORDER BY revenue DESC) AS revenue_rank
FROM seller_stats
ORDER BY revenue_rank
LIMIT 15;

-- =========================================================
-- 9. EXPORT TABLE FOR POWER BI (one flat table, order-item grain)
--    In BigQuery: run, then Save Results > CSV (or connect Power BI directly)
-- =========================================================
CREATE OR REPLACE TABLE `analog-ace-512914-s0.olist.dashboard_flat` AS
SELECT
  co.order_id,
  DATE(co.purchase_ts)                     AS order_date,
  co.customer_unique_id,
  co.customer_state,
  COALESCE(t.product_category_name_english, 'unknown') AS category,
  oi.price,
  oi.freight_value,
  co.delivery_days,
  co.days_vs_estimate,
  co.on_time,
  rv.review_score,
  pm.payment_type
FROM `analog-ace-512914-s0.olist.clean_orders` co
JOIN `analog-ace-512914-s0.olist.order_items` oi USING (order_id)
JOIN `analog-ace-512914-s0.olist.products` p USING (product_id)
LEFT JOIN `analog-ace-512914-s0.olist.category_translation` t
  ON p.product_category_name = t.product_category_name
LEFT JOIN (SELECT order_id, AVG(review_score) AS review_score
           FROM `analog-ace-512914-s0.olist.reviews` GROUP BY order_id) rv USING (order_id)
LEFT JOIN (SELECT order_id, ANY_VALUE(payment_type) AS payment_type
           FROM `analog-ace-512914-s0.olist.payments` GROUP BY order_id) pm USING (order_id);
