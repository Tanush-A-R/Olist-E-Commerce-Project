# Olist E-commerce: Sales & Delivery Performance Analysis

**Question:** Where does revenue come from, and what hurts customer satisfaction and repeat purchases?

**Data:** Olist Brazilian E-commerce public dataset (Kaggle), ~100k orders, 8 linked tables, 2016-2018.

**Tools:** Google BigQuery (SQL: CTEs, window functions, joins) | Power BI | GitHub

## Headline metrics (delivered orders)
| Metric | Value |
|---|---|
| Revenue | R$ 13.22M |
| Orders | 96,470 |
| Avg order value | R$ 137.04 |
| Avg review score | 4.16 / 5 |
| On-time delivery | 91.9% |
| Repeat-customer rate | 3.0% (2,801 of 93,350) |

## Approach
1. Loaded 8 CSVs into BigQuery and built a cleaned view of delivered orders with delivery metrics.
2. Wrote 8 analytical queries (KPIs, monthly trend with MoM growth, category share, state performance, delay vs review, repeat rate, payment mix, seller ranking).
3. Built a flat reporting table and a one-page Power BI dashboard with DAX measures.

## Key insights
1. **Late delivery is the biggest driver of bad reviews.** Orders delivered 7+ days late average **1.70 stars** (79.2% are 1-2 star reviews) vs **4.32 stars** (8.9%) for orders delivered 7+ days early. Even 1-7 days late drops the average to 2.72 stars.
2. **Delivery performance varies sharply by state.** SP delivers in 8.3 days with 94.2% on time, while AL (75.9%), MA (79.6%) and SE (83.7%) lag. RJ, the second-largest market, is at 87.0%.
3. **Revenue is concentrated.** SP, RJ and MG together generate about 63% of revenue (SP alone about 38%). The top 5 categories drive about 40%: health_beauty (9.3%), watches_gifts (8.8%), bed_bath_table (7.7%).
4. **Retention is the weak spot.** Only 3.0% of customers placed more than one order.
5. **Growth plateaued in 2018.** Monthly revenue grew about 7.5x from Jan 2017 (R$112K) to Aug 2018 (R$839K), peaking in Nov 2017 (R$988K), then moved sideways.
6. **A small group of sellers drives a large share of sales, and many rate below average.** The top 15 sellers (out of about 3,100) generate about R$2.3M, roughly 18% of revenue. 10 of them rate below the platform average of 4.16, including 3.35, 3.83 and 3.87 for three of the top 9.
7. **Credit card dominates payments.** 78.3% of payment value is by credit card (about 3.5 installments on average), followed by boleto at 17.9%, vouchers at 2.4% and debit card at 1.4%.

## Recommendations
1. Prioritise delivery SLA improvements in RJ (largest late-order volume among big markets) and the North/Northeast states (AL, MA, SE, PI, CE, BA all below 87% on-time). Target 90%+ on-time.
2. Trigger proactive delay alerts or vouchers for orders that miss their estimate, since lateness cuts average rating from about 4.3 to 2.7 stars.
3. Launch a post-delivery re-engagement campaign for the 97% one-time buyers, starting with the top categories (health_beauty, watches_gifts, bed_bath_table).
4. Introduce seller scorecards (review score and on-time rate) for the top 15 sellers, starting with the lowest-rated high-volume ones, since they carry a large share of revenue.

## Notes on method
- Scope: delivered orders only. Revenue is item price in BRL (freight excluded).
- Delay buckets use whole days between delivery and the estimated date.
- Reviews are averaged per order before joining, to avoid double-counting orders with multiple reviews.
- Repeat rate is based on `customer_unique_id`.
- Payment values include freight and can be split across several payment types per order, so they are not comparable to item revenue. Seller ranking covers sellers with 30+ delivered orders.

## Repo contents
- `queries.sql`: all BigQuery SQL
- `dashboard.pbix` and `dashboard.pdf`: Power BI file and export
- `screenshots/`: dashboard images

## Dashboard
![Dashboard](screenshots/dashboard.png)
