/* 
=============================================================================== 
Query S2 - Trial-to-Paid Conversion by Cohort
=============================================================================== 
 
Business Question 
----------------- 
Of accounts that started a trial in week W, what fraction converted to paid 
by day 14, 30, and 60? 
 
Definitions 
----------- 
Trial Start 
    First trial row per account in saas.trials. 
 
Converted 
    A trial is considered converted when converted_at is populated. 
 
Cohort 
    DATE_TRUNC('week', started_at). 
 
Conversion Windows 
    Conversion is measured based on the number of days between started_at 
    and converted_at. 
 
    • Converted by 14 days: days_trial_to_paid <= 14 
    • Converted by 30 days: days_trial_to_paid <= 30 
    • Converted by 60 days: days_trial_to_paid <= 60 
 
Grain 
----- 
One row per trial start week. 
 
Output 
------ 
trial_week, 
trials_started, 
converted_by_14d, 
converted_by_30d, 
converted_by_60d, 
conv_rate_14d, 
conv_rate_30d, 
conv_rate_60d, 
median_days_trial_to_paid 
 
Business Interpretation 
----------------------- 
Across the dataset, all observed trial-to-paid conversions occurred within 
the first 14 days of the trial. As a result, the 14-day, 30-day, and 60-day 
conversion counts and conversion rates are identical for every cohort. 
 
Out of 250 trial accounts, 113 converted within 14 days, resulting in an 
overall observed trial-to-paid conversion rate of approximately 45%. No 
additional conversions occurred between days 15 and 30 or between days 31 
and 60. 
 
This suggests that, for accounts that convert, the conversion decision is 
typically made early in the trial lifecycle. Extending the observation window 
beyond 14 days does not currently capture additional conversions in this 
dataset. 
 
Weekly cohort conversion rates vary substantially, including several cohorts 
with 0% conversion and others with 100% conversion. However, most cohorts 
contain only a small number of trial accounts, making individual weekly rates 
highly sensitive to one or two account outcomes. These cohort-level results 
should therefore be interpreted cautiously. 
 
Recent cohorts may also be right-censored for the 30-day and 60-day windows. 
A cohort that has not yet existed for the full observation period should not 
be directly compared with fully matured cohorts for those conversion metrics. 
 
PM Recommendation 
----------------- 
Worst Conversion Cohorts: 
Multiple cohorts recorded a 0% trial-to-paid conversion rate, so there is no 
single uniquely worst cohort based on the current output alone. 
 
Recommended qualifying cut: 
Signup Source 
 
Break the selected low-conversion cohort down by signup source and compare 
trial-to-paid conversion rates across acquisition channels. 
 
Interpretation: 
 
• If poor conversion is concentrated in one or a small number of signup 
  sources, the issue is more likely related to acquisition quality, targeting, 
  messaging, or marketing expectations. 
 
• If conversion is consistently poor across all signup sources, the issue is 
  more likely related to the product experience, trial onboarding, activation, 
  or the value delivered during the trial. 
 
Recommended next investigation: 
 
• Compare trial-to-paid conversion by signup source. 
• Compare activation behavior between converted and non-converted accounts. 
• Identify whether non-converting accounts reach key product activation 
  milestones during the first 14 days. 
• Investigate onboarding behavior and product usage before the conversion 
  decision point. 
 
Sanity Checks Performed 
----------------------- 
 
1. Conversion Window Monotonicity 
 
   Verified that: 
 
   converted_by_14d <= converted_by_30d <= converted_by_60d 
 
   Result: 
   ✓ Passed. No invalid cohorts were returned. 
 
2. Conversion Rate Consistency 
 
   Verified that conversion rates are calculated using trials_started as the 
   denominator: 
 
   converted_by_window / trials_started 
 
   Result: 
   ✓ Passed. 
 
3. Conversion Timing Validation 
 
   Verified that converted accounts are counted only when: 
 
   days_trial_to_paid <= 14 
   days_trial_to_paid <= 30 
   days_trial_to_paid <= 60 
 
   Result: 
   ✓ Passed. 
 
4. Conversion Window Comparison 
 
   Compared aggregate conversions across the three observation windows: 
 
   • Converted by 14 days: 113 accounts 
   • Converted by 30 days: 113 accounts 
   • Converted by 60 days: 113 accounts 
 
   Result: 
   ✓ All observed conversions occurred within the first 14 days. 
 
5. Trial Population Validation 
 
   Verified that the trial cohort contains one first trial per account. 
 
   Result: 
   ✓ 250 trial accounts included in the analysis. 
 
Design Note 
----------- 
This solution first identifies the earliest trial for each account using 
ROW_NUMBER(), ensuring that accounts with multiple trial records are assigned 
to their first trial cohort only. 
 
The trial-to-paid duration is calculated as the difference between converted_at 
and started_at. Accounts without a conversion retain a NULL conversion duration 
and are therefore excluded from conversion-window counts and the median 
trial-to-paid calculation. 
 
Conditional aggregation using FILTER is used to calculate the number of 
accounts converted within 14, 30, and 60 days. Conversion rates are calculated 
using the full trial cohort as the denominator. 
 
The median trial-to-paid metric uses PERCENTILE_CONT(0.5) and is calculated 
only across accounts with a non-NULL conversion duration. 
 
Because recent trial cohorts may not have completed the full 30-day or 60-day 
observation window, those metrics are subject to right-censoring and should 
not be interpreted as final conversion performance. 
 
=============================================================================== 
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