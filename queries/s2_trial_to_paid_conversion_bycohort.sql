/*
query: S2 - Trial-to-Paid Conversion by Cohort

business question:
of accounts that started a trial in week W, what fraction
converted to paid by day 14, 30, and 60?

definitions:
- trial start = first trial row per account in saas.trials
- converted = converted_at is populated
- cohort = week of first trial start
- conversion windows are inclusive of days 14, 30, and 60
- median trial-to-paid time is calculated among converted accounts

output:
trial_week
trials_started
converted_by_14d
converted_by_30d
converted_by_60d
conv_rate_14d
conv_rate_30d
conv_rate_60d
median_days_trial_to_paid

sanity check:
converted_by_14d <= converted_by_30d <= converted_by_60d

interpretation note:
recent cohorts are right-censored because they have not had enough
time to observe the full 30- or 60-day conversion window.
*/

with first_trials as
(
    select
        account_id
        ,started_at
        ,converted_at
        ,date_trunc('week', started_at) as trial_week
    from
    (
        select
            account_id
            ,started_at
            ,converted_at
            ,row_number() over (
                partition by account_id
                order by started_at
            ) as row_number
        from
            saas.trials
    ) t
    where
        row_number = 1
),

trial_conversions as
(
    select
        ft.account_id
        ,ft.started_at
        ,ft.trial_week
        ,ft.converted_at
        ,extract(
            day from (ft.converted_at - ft.started_at)
        ) as days_trial_to_paid
    from
        first_trials ft
),

cohort_metrics as
(
    select
        trial_week
        ,count(*) as trials_started
        ,count(*) filter (
            where days_trial_to_paid <= 14
        ) as converted_by_14d
        ,count(*) filter (
            where days_trial_to_paid <= 30
        ) as converted_by_30d
        ,count(*) filter (
            where days_trial_to_paid <= 60
        ) as converted_by_60d
        ,percentile_cont(0.5) within group (
            order by days_trial_to_paid
        ) as median_days_trial_to_paid
    from
        trial_conversions
    group by
        trial_week
)

select
    trial_week
    ,trials_started
    ,converted_by_14d
    ,converted_by_30d
    ,converted_by_60d
    ,converted_by_14d::numeric / nullif(trials_started, 0) as conv_rate_14d
    ,converted_by_30d::numeric / nullif(trials_started, 0) as conv_rate_30d
    ,converted_by_60d::numeric / nullif(trials_started, 0) as conv_rate_60d
    ,median_days_trial_to_paid
from
    cohort_metrics
order by
    trial_week;