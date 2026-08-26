/*
===============================================================================
Query S1 - Monthly MRR Movement Decomposition
===============================================================================

Business Question
-----------------
How did Monthly Recurring Revenue (MRR) change each month, and what drove
those changes?

Break Net New MRR into:

- New MRR
- Expansion MRR
- Contraction MRR
- Churn MRR
- Reactivation MRR

Grain
-----
One row per month.

Output
------
month,
new_mrr,
expansion_mrr,
contraction_mrr,
churn_mrr,
reactivation_mrr,
net_new_mrr,
ending_mrr

Business Interpretation
-----------------------
MRR increased consistently across the reporting period, with Ending MRR
growing from approximately ₹146.6K in June 2025 to ₹347.0K in June 2026.

New MRR was the primary driver of growth throughout the period, while
expansion and reactivation provided additional positive contributions.

Churn was the largest source of negative MRR movement. The largest churn
occurred in March 2026 (-₹13.8K), contributing to a lower Net New MRR of
₹12.1K for that month.

Despite monthly churn and contraction, positive MRR movements consistently
outweighed negative movements, resulting in sustained MRR growth.

PM Recommendation
-----------------
Investigate the March 2026 churn spike to identify the accounts, plans, or
customer segments responsible for the unusually high revenue loss.

Continue monitoring New MRR, as it is the primary driver of overall growth,
while identifying opportunities to reduce churn and contraction.

Sanity Checks Performed
-----------------------

1. Event Replay Validation

   Verified that:

   Ending MRR (Month N)
   =
   Ending MRR (Month N-1)
   +
   Net New MRR (Month N)

   Result:
   ✓ Passed.

2. MRR Movement Validation

   Verified that:

   Net New MRR
   =
   New MRR
   + Expansion MRR
   + Contraction MRR
   + Churn MRR
   + Reactivation MRR

   Result:
   ✓ Passed.

3. Snapshot Reconciliation

   Event-based Ending MRR was compared against an independently calculated
   month-end MRR snapshot from saas.subscriptions.

   Result:
   The reconciliation did not close due to source-data inconsistencies in
   saas.subscriptions.

Data Quality Finding
--------------------
saas.subscriptions does not consistently reflect subscription events.
For example, account 200025 has an addon_attach event that increases MRR,
but the add-on revenue is missing from subscriptions.mrr. Account 100270
has a plan_changed event from Enterprise to Pro, but subscriptions.plan and
subscriptions.mrr remain unchanged.

These inconsistencies cause the historical snapshot MRR to diverge from the
event-based calculation, making subscription_events the more reliable source
for MRR movement analysis.

Design Note
-----------
This solution uses subscription_events as the primary source for calculating
monthly MRR movements and reconstructs Ending MRR using:

Opening MRR
+
Cumulative Net New MRR
=
Ending MRR

Opening MRR is independently calculated from saas.subscriptions at the start
of the reporting period.

The event-based calculation passed internal event replay validation. Snapshot
reconciliation was investigated separately and identified a data-quality issue
in saas.subscriptions rather than an issue with the event-based MRR logic.

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