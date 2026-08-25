/*
===============================================================================
Query E4 — PDP Engagement: High-View, Low-Cart Products
===============================================================================

Business Question
-----------------
Which products attract lots of product detail page (PDP) views but fail to
generate add-to-cart actions? These products may indicate pricing issues,
poor product imagery/content, or stock/availability problems.

Definitions
-----------
- views = count of 'product_view' events.
- add_to_cart_sessions = distinct sessions with an 'add_to_cart' event.
- atc_rate = add_to_cart_sessions / views.
- atc_rate_vs_category_median = product ATC rate - category median ATC rate.

Output
------
- product_id
- product_name
- category
- views
- add_to_cart_sessions
- atc_rate
- atc_rate_vs_category_median
- views_rank
- atc_rate_rank

Pattern
-------
- Conditional aggregation using FILTER
- COUNT(DISTINCT ...)
- Multi-CTE query
- Ordered-set aggregate (PERCENTILE_CONT)
- Window functions (DENSE_RANK)
- Defensive division using NULLIF()

Design Notes
------------
- Views are counted as product_view events.
- Add-to-cart is measured as distinct sessions, not events.
- Products are benchmarked against the median ATC rate of their own category.
  This avoids unfair comparisons across categories with naturally different
  conversion behaviour.
- The report is ordered by products performing worst relative to their
  category while still receiving significant traffic.

Sanity Checks
-------------
1. Verify add_to_cart_sessions <= views for every product.
2. Verify atc_rate is always between 0 and 1.
3. Verify every category median lies between the minimum and maximum
   ATC rate for products in that category.
4. Consider excluding products with very low views (e.g. <100) if using
   this report operationally to reduce noise.

PM Action
---------
Review the top 10 flagged SKUs and assign one primary investigation
hypothesis:

- Price
- Product images / PDP quality
- Stock / Variant availability

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