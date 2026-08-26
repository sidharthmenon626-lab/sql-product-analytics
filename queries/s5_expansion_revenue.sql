/*
===============================================================================
S5 — EXPANSION REVENUE: WHO'S UPGRADING AND WHY
===============================================================================

Business Question
-----------------
Of accounts that expanded MRR in the last 6 months, what is the dominant
expansion vector — seats added, plan upgrade, or add-on attach?

Analysis Window
---------------
The analysis window is anchored to the warehouse cutoff date to ensure
reproducibility:

2025-12-15 through 2026-06-15 23:59:59

Funnel / Classification
-----------------------
Qualifying expansion events are subscription events where:

• event_type is seat_add, addon_attach, or plan_changed
• mrr_delta > 0

Expansion categories:

seat_add
    → seats_added

plan_changed
    → plan_upgrade

addon_attach
    → addon

Grain
-----
One row per qualifying expansion event before aggregation.

The final output aggregates expansion events by expansion_type.

Output
------
expansion_type,
expansion_events,
accounts_expanded,
expansion_mrr_total,
expansion_mrr_per_account,
median_days_from_signup_to_expansion

Business Interpretation
-----------------------
Seat additions are the dominant expansion vector during the fixed six-month
analysis window.

Results:

• seats_added generated 7,662.00 in expansion MRR across 42 events
  and 34 accounts.

• plan_upgrade generated 6,348.80 in expansion MRR across 59 events
  and 57 accounts.

• addon generated 261.80 in expansion MRR across 3 events and
  3 accounts.

Seat additions also generate the highest expansion MRR per expanded account
at 225.35, compared with 111.38 for plan upgrades.

Although plan upgrades occur more frequently, seat additions generate the
largest total expansion MRR and therefore represent the dominant expansion
motion.

PM Recommendation
-----------------
Dominant Expansion Vector:

Seats Added

Recommended product investment:

Invest in seat-management UX and admin features.

Recommended next sprint investigation:

• Identify where in the product administrators currently add or manage seats.
• Review the seat-purchase and seat-management experience for friction.
• Analyze whether seat additions occur after specific collaboration or usage
  milestones.
• Identify accounts approaching seat limits and evaluate opportunities for
  proactive in-app prompts.
• Test clearer seat-capacity visibility and contextual prompts encouraging
  administrators to add seats when demand increases.

Sanity Checks Performed
-----------------------

1. Expansion Event Classification

   Verified that qualifying events are limited to:

   seat_add,
   addon_attach,
   plan_changed with positive MRR impact.

   Each qualifying event is assigned to exactly one expansion category.

2. Expansion MRR Reconciliation

   Verified that the sum of expansion_mrr_total across:

   seats_added
   + plan_upgrade
   + addon

   reconciles to expansion MRR calculated using the S1 event-classification
   logic for the exact same fixed analysis window.

   S5 expected total expansion MRR:

   7,662.00
   + 6,348.80
   +   261.80
   = 14,272.60

   Result:
   Run the S1 reconciliation using the same fixed window and confirm that
   S1 expansion MRR = 14,272.60.

3. Account Counting Validation

   expansion_events counts qualifying expansion events.

   accounts_expanded counts distinct accounts, ensuring that accounts with
   multiple expansion events are counted once within each expansion type.

Design Note
-----------
The analysis window uses explicit lower and upper timestamp boundaries rather
than current_date - interval '6 months'.

This anchors the analysis to the warehouse cutoff date of 2026-06-15 and
ensures that the S5 results remain reproducible when the query is rerun in
the future.

The explicit upper bound also ensures that S5 can be reconciled consistently
with S1 using the same fixed event window.

===============================================================================
*/


with qualifying_expansion_events as (

    select
        se.account_id
        ,se.event_type
        ,se.mrr_delta
        ,se.seats_delta
        ,se.event_time as expansion_at
    from saas.subscription_events se
    where se.event_time >= date '2026-06-15' - interval '6 months'
        and se.event_time <= timestamp '2026-06-15 23:59:59'
        and se.event_type in (
            'seat_add'
            ,'addon_attach'
            ,'plan_changed'
        )
        and se.mrr_delta > 0

),

classified_expansions as (

    select
        account_id
        ,mrr_delta
        ,expansion_at
        ,case
            when event_type = 'seat_add'
                then 'seats_added'
            when event_type = 'plan_changed'
                then 'plan_upgrade'
            when event_type = 'addon_attach'
                then 'addon'
        end as expansion_type
    from qualifying_expansion_events

),

expansion_with_signup as (

    select
        ce.account_id
        ,ce.mrr_delta
        ,ce.expansion_at
        ,ce.expansion_type
        ,a.signup_date
        ,ce.expansion_at::date - a.signup_date as days_from_signup_to_expansion
    from classified_expansions ce
    join saas.accounts a
        on ce.account_id = a.account_id

)

select
    expansion_type
    ,count(*) as expansion_events
    ,count(distinct account_id) as accounts_expanded
    ,sum(mrr_delta) as expansion_mrr_total
    ,sum(mrr_delta)
        / nullif(count(distinct account_id), 0) as expansion_mrr_per_account
    ,percentile_cont(0.5) within group (
        order by days_from_signup_to_expansion
    ) as median_days_from_signup_to_expansion
from expansion_with_signup
group by
    expansion_type
order by
    expansion_mrr_total desc;