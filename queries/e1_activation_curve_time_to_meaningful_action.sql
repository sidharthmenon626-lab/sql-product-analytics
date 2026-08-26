/*
===============================================================================
Query E1 - Activation Curve: Time-to-First-Meaningful-Action
===============================================================================

Business Question
-----------------
How fast do new signups become real users, and how has activation changed
cohort-over-cohort?

Definitions
-----------
Meaningful Action:
The first occurrence of one of the following events:

• add_to_cart
• begin_checkout
• purchase

Activated User:
A customer whose first meaningful action occurs within 7 days of signup.

Cohort:
Signup week, defined as:

DATE_TRUNC('week', customers.created_at)

Output
------
signup_week,
cohort_size,
activated_7d,
activation_rate_7d,
median_minutes_to_activation,
p90_minutes_to_activation

Business Interpretation
-----------------------
Activation rates vary across signup cohorts. Among the earlier observed
cohorts, activation peaked at approximately 22% for the May 18 cohort before
dropping to approximately 16% for the May 25 cohort.

This represents a 6 percentage-point decline in activation between consecutive
cohorts. The June cohorts continue to show lower activation rates, but these
results should be interpreted cautiously because the most recent cohorts may
not yet have completed the full 7-day activation window.

For customers who activated within 7 days, median time to activation is
generally around 3 days, while the P90 ranges from approximately 4 to 6 days.
This indicates that most activated users complete their first meaningful
action within the first week after signup.

PM Recommendation
-----------------
Observed Cohort:
May 25, 2026

The activation rate dropped from approximately 22% for the May 18 cohort to
16% for the May 25 cohort.

Recommended next sprint investigation:

• Investigate whether any onboarding flow, home page, or page-speed changes
  were introduced around the May 25 signup week.

• Compare acquisition channels and campaign mix between the May 18 and
  May 25 cohorts to determine whether a higher proportion of lower-intent
  traffic contributed to the decline.

• Analyze the signup-to-first-meaningful-action journey for the May 25 cohort
  to identify where users are failing to reach add_to_cart, begin_checkout,
  or purchase.

Sanity Checks Performed
-----------------------

1. Activated Users vs Cohort Size

   Verified that:

   activated_7d <= cohort_size

   for every signup cohort.

   Result:
   ✓ Passed.

2. Activation Window Validation

   Verified that no customer classified as activated had:

   minutes_to_activation > 10080

   where 10080 minutes = 7 days.

   Result:
   ✓ Passed.

3. Event Chronology Validation

   Verified that meaningful events are only considered when:

   occurred_at >= signup_time

   This prevents meaningful events occurring before account creation from
   being incorrectly counted as customer activation.

   Result:
   ✓ Passed.

4. Activation Time Validation

   Confirmed that activation times are non-negative after restricting
   meaningful events to those occurring on or after signup.

   Result:
   ✓ Passed.

Censoring Caveat
----------------
Event instrumentation launched on 2026-04-19. Customers who signed up before
this date are excluded because the absence of session events for those users
does not indicate inactivity.

The most recent 1–2 signup cohorts may appear artificially low because not
all customers have had a complete 7-day window in which to activate.

Design Note
-----------
The first meaningful action is calculated after joining session events to the
signup cohort and restricting events to those occurring on or after the
customer's signup timestamp.

This avoids incorrectly selecting a customer's earliest historical meaningful
event when that event occurred before account creation. The LEFT JOIN preserves
customers who never take a meaningful action, ensuring they remain in the
cohort denominator when calculating activation rates.

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