/*
S3 — Gross Revenue Churn and Net Revenue Retention by Cohort

Business question:
Of the MRR we had from a given monthly cohort 12 months ago,
how much did we keep (GRR) and how much did we keep including
expansion (NRR)?

Key definitions:
- Cohort = first month with positive MRR
- Starting MRR = MRR at cohort start
- Retained MRR = starting MRR from accounts still paying at Month 12
- Expansion = Month 12 MRR above starting MRR
- Contraction = starting MRR lost from accounts still paying
- Churn = starting MRR from accounts no longer paying
- GRR = Retained MRR / Starting MRR
- NRR = (Retained MRR + Expansion - Contraction) / Starting MRR

Data quality:
- Excludes future-dated subscription events after 2026-06-15,
  consistent with the S1 data-quality cutoff.
- MRR is reconstructed from subscription_events because
  subscriptions.mrr does not reliably reflect add-ons and plan changes.

Sanity checks:
- GRR <= 1.0 always.
- NRR can exceed 1.0; this represents positive net expansion.
- GRR + (Churn MRR / Starting MRR) ≈ 1.0.
*/

with monthly_mrr_delta as
(
    select
        account_id
        ,date_trunc('month', event_time)::date as event_month
        ,sum(mrr_delta) as monthly_delta
    from saas.subscription_events
    where event_time <= timestamp '2026-06-15 23:59:59'
    group by
        account_id
        ,date_trunc('month', event_time)::date
)

,cumulative_mrr as
(
    select
        account_id
        ,event_month
        ,monthly_delta
        ,sum(monthly_delta) over (
            partition by account_id
            order by event_month
        ) as cumulative_mrr
    from monthly_mrr_delta
)

,month_spine as
(
    select
        generate_series(
            min(event_month)
            ,max(event_month)
            ,interval '1 month'
        )::date as month
    from cumulative_mrr
)

,account_months as
(
    select
        a.account_id
        ,ms.month
    from (
        select distinct
            account_id
        from cumulative_mrr
    ) a
    cross join month_spine ms
)

,monthly_mrr as
(
    select
        am.account_id
        ,am.month
        ,(
            select
                cm.cumulative_mrr
            from cumulative_mrr cm
            where cm.account_id = am.account_id
                and cm.event_month <= am.month
            order by
                cm.event_month desc
            limit 1
        ) as mrr
    from account_months am
)

,cohort_accounts as
(
    select
        account_id
        ,month as cohort_month
        ,mrr as cohort_starting_mrr
    from
    (
        select
            account_id
            ,month
            ,mrr
            ,row_number() over (
                partition by account_id
                order by month
            ) as rn
        from monthly_mrr
        where mrr > 0
            and month + interval '12 months' <= (
                select max(month)
                from monthly_mrr
            )
    ) x
    where rn = 1
)

,cohort_12m as
(
    select
        ca.account_id
        ,ca.cohort_month
        ,ca.cohort_starting_mrr
        ,mm.mrr as mrr_12m
    from cohort_accounts ca
    left join monthly_mrr mm
        on ca.account_id = mm.account_id
        and mm.month = ca.cohort_month + interval '12 months'
)

,mrr_movements as
(
    select
        account_id
        ,cohort_month
        ,cohort_starting_mrr
        ,coalesce(mrr_12m, 0) as mrr_12m

        ,case
            when coalesce(mrr_12m, 0) > 0
                then cohort_starting_mrr
            else 0
        end as retained_mrr_12m

        ,case
            when coalesce(mrr_12m, 0) > cohort_starting_mrr
                then coalesce(mrr_12m, 0) - cohort_starting_mrr
            else 0
        end as expansion_mrr_12m

        ,case
            when coalesce(mrr_12m, 0) > 0
                and mrr_12m < cohort_starting_mrr
                then cohort_starting_mrr - mrr_12m
            else 0
        end as contraction_mrr_12m

        ,case
            when coalesce(mrr_12m, 0) = 0
                then cohort_starting_mrr
            else 0
        end as churn_mrr_12m
    from cohort_12m
)

select
    cohort_month
    ,sum(cohort_starting_mrr) as cohort_starting_mrr
    ,sum(retained_mrr_12m) as retained_mrr_12m
    ,sum(expansion_mrr_12m) as expansion_mrr_12m
    ,sum(contraction_mrr_12m) as contraction_mrr_12m
    ,sum(churn_mrr_12m) as churn_mrr_12m
    ,sum(retained_mrr_12m)
        / nullif(sum(cohort_starting_mrr), 0) as grr
    ,sum(
        retained_mrr_12m
        + expansion_mrr_12m
        - contraction_mrr_12m
    )
        / nullif(sum(cohort_starting_mrr), 0) as nrr
from mrr_movements
group by
    cohort_month
order by
    cohort_month;