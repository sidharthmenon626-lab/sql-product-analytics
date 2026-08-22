/*
===============================================================================
Query S1 — Monthly MRR Movement Decomposition
-------------------------------------------------------------------------------
Business Question:
How did Monthly Recurring Revenue (MRR) change each month, and what drove the
change? Break Net New MRR into:
- New MRR
- Expansion MRR
- Contraction MRR
- Churn MRR
- Reactivation MRR

Output:
- month
- new_mrr
- expansion_mrr
- contraction_mrr
- churn_mrr
- reactivation_mrr
- net_new_mrr
- ending_mrr

Business Rules:
- New MRR:
    subscription_started or trial_converted with no prior cancellation.
- Expansion MRR:
    plan_changed with positive mrr_delta,
    seat_add,
    addon_attach.
- Contraction MRR:
    plan_changed with negative mrr_delta.
- Churn MRR:
    cancelled.
- Reactivation MRR:
    subscription_started or trial_converted after a previous cancellation.

Notes:
- Excludes trial_started events since trials generate $0 MRR.
- Excludes future-dated legacy events after 2026-06-15.
- Uses a rolling 12-month reporting window ending on 2026-06-15.
- Ending MRR is calculated as:
      Opening MRR + cumulative Net New MRR.

Sanity Checks:
1. Event Replay Validation
   Verify that:
       Ending MRR(month N)
       =
       Ending MRR(month N-1)
       +
       Net New MRR(month N)

   Expected Result:
   - The calculated Ending MRR should exactly equal the previous month's
     Ending MRR plus the current month's Net New MRR.
   - Difference should be 0 (or negligible due to rounding).
PM Action:
- Identify the month with the largest negative MRR movement (typically churn or
  contraction).
- Segment that month's movement by plan, customer cohort, acquisition channel,
  or account size to determine the primary driver of revenue loss.
===============================================================================
*/

with filtered_events as
(
    select
        account_id,
        event_type,
        event_time,
        date_trunc('month', event_time) as month,
        mrr_delta
    from
        saas.subscription_events
    where
        event_type <> 'trial_started'
        and event_time >= date '2026-06-15' - interval '12 months'
        and event_time <= date '2026-06-15'
),

classified_events as
(
    select
        account_id,
        month,
        event_time,
        event_type,
        mrr_delta,
        case
            when event_type in ('subscription_started', 'trial_converted')
                 and exists
                 (
                     select
                         1
                     from
                         filtered_events fe2
                     where
                         fe2.account_id = filtered_events.account_id
                         and fe2.event_type = 'cancelled'
                         and fe2.event_time < filtered_events.event_time
                 )
                then 'reactivation'

            when event_type in ('subscription_started', 'trial_converted')
                then 'new'

            when event_type = 'plan_changed'
                 and mrr_delta > 0
                then 'expansion'

            when event_type in ('seat_add', 'addon_attach')
                then 'expansion'

            when event_type = 'plan_changed'
                 and mrr_delta < 0
                then 'contraction'

            when event_type = 'cancelled'
                then 'churn'
        end as bucket
    from
        filtered_events
),

monthly_mrr_movements as
(
    select
        month,
        sum(mrr_delta) filter (where bucket = 'new') as new_mrr,
        sum(mrr_delta) filter (where bucket = 'expansion') as expansion_mrr,
        sum(mrr_delta) filter (where bucket = 'contraction') as contraction_mrr,
        sum(mrr_delta) filter (where bucket = 'churn') as churn_mrr,
        sum(mrr_delta) filter (where bucket = 'reactivation') as reactivation_mrr,
        sum(mrr_delta) as net_new_mrr
    from
        classified_events
    group by
        month
),

opening_mrr as
(
    select
        coalesce(sum(mrr), 0) as opening_mrr
    from
        saas.subscriptions
    where
        start_date < date '2025-06-15'
        and (
                end_date is null
                or end_date >= date '2025-06-15'
            )
)

select
    mmm.month,
    mmm.new_mrr,
    mmm.expansion_mrr,
    mmm.contraction_mrr,
    mmm.churn_mrr,
    mmm.reactivation_mrr,
    mmm.net_new_mrr,
    om.opening_mrr
    + sum(mmm.net_new_mrr) over
      (
          order by
              mmm.month
      ) as ending_mrr
from
    monthly_mrr_movements mmm
cross join
    opening_mrr om
order by
    mmm.month;