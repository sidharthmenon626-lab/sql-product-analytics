/*
===============================================================================
Query E1 — Activation Curve: Time-to-First-Meaningful-Action
-------------------------------------------------------------------------------
Business Question:
How fast do new signups become real users, and how has that changed
cohort-over-cohort?

Definitions:
- Cohort = Signup week
- Meaningful action = First of:
    • add_to_cart
    • begin_checkout
    • purchase
- Activated user = Customer whose first meaningful action occurred within
  7 days of signup.

Output:
- signup_week
- cohort_size
- activated_7d
- activation_rate_7d
- median_minutes_to_activation
- p90_minutes_to_activation

Notes:
- Excludes cohorts before 2026-04-19 because event instrumentation had
  not yet launched.
- Meaningful actions are only considered if they occur on or after the
  customer's signup timestamp.
- The most recent 1–2 cohorts may appear artificially low because they
  have not yet completed the full 7-day activation window (right censoring).

Sanity Checks Performed:
✓ Verified activated_7d <= cohort_size for every signup cohort.
✓ Verified no customer classified as activated had
  minutes_to_activation > 10080 (7 days).
✓ Verified activation times are non-negative by considering only
  meaningful events occurring on or after signup.
Design Note:
The earliest meaningful action is determined only from events occurring
on or after customer signup. This avoids counting anonymous or historical
events that may have been associated with the customer before registration.
===============================================================================
*/

with signup_cohort as
(
    select
        customer_id,
        created_at as signup_time,
        date_trunc('week', created_at) as signup_week
    from
        ecom.customers
    where
        created_at >= date '2026-04-19'
),

activation_metrics as
(
    select
        sc.customer_id,
        sc.signup_week,
        sc.signup_time,

        min(se.occurred_at) as first_meaningful_action_at,

        extract
        (
            epoch from
            (
                min(se.occurred_at) - sc.signup_time
            )
        ) / 60.0 as minutes_to_activation,

        case
            when
                min(se.occurred_at)
                <= sc.signup_time + interval '7 day'
            then 1
            else 0
        end as activated_7d

    from
        signup_cohort sc

        left join ecom.session_events se
            on sc.customer_id = se.customer_id
           and se.event_type in
           (
               'add_to_cart',
               'begin_checkout',
               'purchase'
           )
           and se.occurred_at >= sc.signup_time

    group by
        sc.customer_id,
        sc.signup_week,
        sc.signup_time
)

select
    signup_week,
    count(*) as cohort_size,
    sum(activated_7d) as activated_7d,

    round
    (
        sum(activated_7d)::numeric
        / count(*),
        4
    ) as activation_rate_7d,

    percentile_cont(0.5)
    within group
    (
        order by
            case
                when activated_7d = 1
                then minutes_to_activation
            end
    ) as median_minutes_to_activation,

    percentile_cont(0.9)
    within group
    (
        order by
            case
                when activated_7d = 1
                then minutes_to_activation
            end
    ) as p90_minutes_to_activation

from
    activation_metrics

group by
    signup_week

order by
    signup_week;