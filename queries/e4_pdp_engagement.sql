/*
===============================================================================
Query E4 - PDP Engagement: High-View, Low-Cart Products
===============================================================================

Business Question
-----------------
Which products attract a high volume of product detail page (PDP) views but
fail to generate corresponding add-to-cart activity?

These products may represent opportunities to investigate potential pricing
issues, weak product imagery or PDP content, or stock and availability
problems.

Definitions
-----------
- views = count of 'product_view' events for the product.

- add_to_cart_sessions = distinct sessions containing at least one
  'add_to_cart' event for the product.

- atc_rate = add_to_cart_sessions / views.

- category_median_atc_rate = median product-level ATC rate within the
  product's category.

- atc_rate_vs_category_median = product ATC rate - category median ATC rate.

A negative atc_rate_vs_category_median indicates that the product's ATC rate
is below the median for its category.

Methodology
-----------
Product engagement is first aggregated at the product level.

Views are calculated by counting all 'product_view' events.

Add-to-cart activity is calculated as the number of distinct sessions
containing an 'add_to_cart' event for the product. This prevents multiple
add-to-cart events within the same session from inflating the metric.

Product-level engagement metrics are then joined to the products and
categories tables to add product and category context.

Each product's ATC rate is calculated as:

    add_to_cart_sessions / views

The median ATC rate is then calculated independently for each category using
PERCENTILE_CONT(0.5).

Each product is compared against the median ATC rate of its own category
rather than against a global conversion threshold.

A minimum view threshold is applied when prioritizing flagged products to
reduce noise from products with very low traffic. Products with only a few
views can appear to have extremely poor ATC rates without representing a
meaningful merchandising opportunity.

Grain
-----
One row per product.

Output
------
product_id,
product_name,
category,
views,
add_to_cart_sessions,
atc_rate,
atc_rate_vs_category_median,
views_rank,
atc_rate_rank

Business Interpretation
-----------------------
Products with:

- Meaningful PDP traffic, and
- A strongly negative atc_rate_vs_category_median

represent the primary opportunities for investigation.

A negative atc_rate_vs_category_median means that the product converts PDP
interest into add-to-cart activity less effectively than the typical product
in its category.

The most negative values indicate the largest underperformance relative to
category peers.

A minimum view threshold is important because products with very low traffic
can produce unstable conversion rates. A product with one or two views and
zero add-to-cart sessions should not necessarily be prioritized over a
high-traffic product with sustained underperformance.

PM Recommendation
-----------------
Hand the top 10 flagged SKUs meeting the minimum view threshold to the
merchandising PM for investigation.

For each flagged SKU, assign one primary hypothesis:

1. Price

   The product may be priced less competitively than similar products.

2. Image / PDP Quality

   Product imagery, descriptions, reviews, or other PDP content may fail to
   provide sufficient confidence for customers to add the product to cart.

3. Stock / Availability

   The product may have inventory issues, unavailable variants, or other
   availability constraints preventing customers from progressing.

The purpose of this analysis is to prioritize investigation rather than
directly diagnose the root cause.

Sanity Checks Performed
-----------------------

1. Add-to-Cart vs Views Validation

   Verified that:

   add_to_cart_sessions <= views

   Result:

   ✓ Passed. No products had add_to_cart_sessions greater than views.

2. ATC Rate Validation

   Verified that:

   0 <= atc_rate <= 1

   Result:

   ✓ Passed. No products had an ATC rate outside the expected range.

3. Product-Level Aggregation Validation

   Verified that the product_engagement CTE returns one row per product_id.

   Multiple product views are retained as separate events, while multiple
   add-to-cart events within the same session are deduplicated.

   Result:

   ✓ Passed.

4. Category Benchmark Validation

   Verified that the category median is calculated independently within each
   product category.

   Products are therefore compared against relevant category peers rather
   than against a single global ATC benchmark.

   Result:

   ✓ Passed.

5. Low-Traffic Prioritization Check

   The initial output showed that products with very few views could appear
   at the top of the underperformance ranking simply because they had zero
   add-to-cart sessions.

   A minimum view threshold is therefore applied before prioritizing the top
   10 flagged SKUs for PM investigation.

   Result:

   ✓ Addressed through the minimum view threshold.

Design Note
-----------
The product_engagement CTE establishes the product-level engagement metrics
by calculating views and distinct add-to-cart sessions in a single aggregation
over session_events.

The product_metrics CTE adds product and category context and calculates the
product-level ATC rate.

The category_benchmarks CTE establishes the median ATC rate for each category
using PERCENTILE_CONT(0.5).

The final query joins each product back to its category benchmark and
calculates the difference between the product's ATC rate and the category
median.

Products meeting the minimum view threshold are ordered by the most negative
atc_rate_vs_category_median, with views used as a secondary prioritization
factor. This surfaces products that both underperform relative to category
peers and receive meaningful customer attention.

===============================================================================
*/

with product_engagement as
(
    select
        se.product_id,
        count(*) filter (
            where se.event_type = 'product_view'
        ) as views,
        count(distinct se.session_id) filter (
            where se.event_type = 'add_to_cart'
        ) as add_to_cart_sessions
    from
        ecom.session_events se
    group by
        se.product_id
),

product_metrics as
(
    select
        pe.product_id,
        p.product_name,
        c.category_name as category,
        pe.views,
        pe.add_to_cart_sessions,
        pe.add_to_cart_sessions::numeric
        /
        nullif(pe.views, 0) as atc_rate
    from
        product_engagement pe
        join ecom.products p
            on pe.product_id = p.product_id
        join ecom.categories c
            on p.category_id = c.category_id
),

category_benchmarks as
(
    select
        category,
        percentile_cont(0.5)
        within group (
            order by atc_rate
        ) as category_median_atc_rate
    from
        product_metrics
    group by
        category
)

select
    pm.product_id,
    pm.product_name,
    pm.category,
    pm.views,
    pm.add_to_cart_sessions,
    pm.atc_rate,
    pm.atc_rate
    - cb.category_median_atc_rate as atc_rate_vs_category_median,
    dense_rank() over (
        order by pm.views desc
    ) as views_rank,
    dense_rank() over (
        order by pm.atc_rate
    ) as atc_rate_rank
from
    product_metrics pm
    join category_benchmarks cb
        on pm.category = cb.category
order by
    atc_rate_vs_category_median asc,
    pm.views desc;