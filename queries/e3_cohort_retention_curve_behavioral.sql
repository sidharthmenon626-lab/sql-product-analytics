/*
===============================================================================
Query E3 — Weekly Cohort Retention Curve (Behavioral)
===============================================================================

Business Question:
"Of users who signed up in week W, what fraction came back and performed a
meaningful action in Week 1, Week 2, Week 3 and Week 4?"

Method:
- Cohorts begin on 2026-04-19 (event instrumentation launch).
- Week index is calculated relative to each customer's signup timestamp.
- Week 0 is the signup cohort (baseline).
- Meaningful events:
    - product_view
    - add_to_cart
    - purchase
- Pre-signup sessions are excluded.
- One customer is counted at most once per week.

Sanity Checks:
1. w0_active = cohort_size exactly.
2. week_index should never be negative.
3. customer_week_activity should contain one row per customer per week_index.
4. week_index should range from 1–4 in the final retention calculation.

Design Notes:
- Relative week is computed using the difference between session start and
  signup time instead of calendar weeks.
- Weekly retention is measured independently for each week. Customers may
  skip weeks and return later, so later-week retention is not guaranteed to
  be lower than earlier weeks.
===============================================================================
*/

with signup_cohort as
(
    select
        customer_id,
        created_at as signup_time,
        date_trunc('week', created_at) as cohort_week
    from
        ecom.customers
    where
        created_at >= '2026-04-19'
)

, meaningful_sessions as
(
    select distinct
        s.customer_id,
        s.session_id,
        s.started_at
    from
        ecom.sessions s
    inner join
        ecom.session_events se
        on s.session_id = se.session_id
    where
        s.customer_id is not null
        and se.event_type in
        (
            'product_view',
            'add_to_cart',
            'purchase'
        )
)

, activity_by_week as
(
    select
        sc.customer_id,
        sc.signup_time,
        sc.cohort_week,
        ms.started_at,
        floor
        (
            extract(epoch from (ms.started_at - sc.signup_time))
            / (86400 * 7)
        ) as week_index
    from
        signup_cohort sc
    left join
        meaningful_sessions ms
        on sc.customer_id = ms.customer_id
       and ms.started_at >= sc.signup_time
)

, customer_week_activity as
(
    select distinct
        customer_id,
        cohort_week,
        week_index
    from
        activity_by_week
    where
        week_index between 1 and 4
)

select
    sc.cohort_week,

    count(distinct sc.customer_id) as cohort_size,

    count(distinct sc.customer_id) as w0_active,

    count(distinct cwa.customer_id)
        filter (where cwa.week_index = 1) as w1_retained,

    count(distinct cwa.customer_id)
        filter (where cwa.week_index = 2) as w2_retained,

    count(distinct cwa.customer_id)
        filter (where cwa.week_index = 3) as w3_retained,

    count(distinct cwa.customer_id)
        filter (where cwa.week_index = 4) as w4_retained,

    round
    (
        count(distinct cwa.customer_id)
            filter (where cwa.week_index = 1)::numeric
        /
        count(distinct sc.customer_id),
        4
    ) as w1_retention_rate,

    round
    (
        count(distinct cwa.customer_id)
            filter (where cwa.week_index = 2)::numeric
        /
        count(distinct sc.customer_id),
        4
    ) as w2_retention_rate,

    round
    (
        count(distinct cwa.customer_id)
            filter (where cwa.week_index = 3)::numeric
        /
        count(distinct sc.customer_id),
        4
    ) as w3_retention_rate,

    round
    (
        count(distinct cwa.customer_id)
            filter (where cwa.week_index = 4)::numeric
        /
        count(distinct sc.customer_id),
        4
    ) as w4_retention_rate

from
    signup_cohort sc

left join
    customer_week_activity cwa
    on sc.customer_id = cwa.customer_id

group by
    sc.cohort_week

order by
    sc.cohort_week;