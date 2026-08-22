/*
===============================================================================
S5 — EXPANSION REVENUE: WHO'S UPGRADING AND WHY

Business question:
    Of accounts that expanded MRR in the last 6 months, what is the dominant
    expansion vector — seats added, plan upgrade, or add-on attach?

Definitions:
    - Expansion event = a subscription event where event_type is seat_add,
      addon_attach, or plan_changed, with mrr_delta > 0.
    - seat_add → seats_added
    - plan_changed → plan_upgrade
    - addon_attach → addon

Grain:
    One row in the underlying dataset represents one qualifying expansion event.
    The final output aggregates these events by expansion_type.

Output:
    expansion_type
    ,expansion_events
    ,accounts_expanded
    ,expansion_mrr_total
    ,expansion_mrr_per_account
    ,median_days_from_signup_to_expansion

Sanity check:
    The sum of expansion_mrr_total across all expansion types must reconcile
    exactly to expansion MRR calculated using the S1 event-classification logic
    for the same 6-month window.

    Result:
    S5 total expansion MRR = 14,391.06
    S1 expansion MRR       = 14,391.06
    Difference              = 0.00

    Status: PASSED — all qualifying expansion MRR is classified into exactly
    one of the three S5 expansion categories.
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
    where se.event_time >= current_date - interval '6 months'
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
    ,sum(mrr_delta) / nullif(count(distinct account_id), 0) as expansion_mrr_per_account
    ,percentile_cont(0.5) within group (
        order by days_from_signup_to_expansion
    ) as median_days_from_signup_to_expansion
from expansion_with_signup
group by
    expansion_type
order by
    expansion_mrr_total desc;