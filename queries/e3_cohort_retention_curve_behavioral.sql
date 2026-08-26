/* 
=============================================================================== 
Query E3 - Cohort Retention Curve (Weekly, Behavioral) 
=============================================================================== 
 
Business Question 
----------------- 
Of users who signed up in week W, what fraction came back and performed a 
meaningful action in Week 1, Week 2, Week 3, and Week 4? 
 
Meaningful Activity 
------------------- 
A meaningful return is defined as a session containing at least one of the 
following events: 
 
product_view 
add_to_cart 
purchase 
 
Pure bounce sessions are excluded. 
 
Methodology 
----------- 
Customers are grouped into weekly signup cohorts based on their signup date. 
 
Each meaningful session is assigned a relative week index based on the time 
difference between the session start and the customer's signup time: 
 
week_index = FLOOR(
    EXTRACT(EPOCH FROM (session_start - signup_time)) / (86400 * 7)
) 
 
Week 0 represents the signup cohort baseline. 
 
Week 1 represents activity occurring 7–13 days after signup. 
Week 2 represents activity occurring 14–20 days after signup. 
Week 3 represents activity occurring 21–27 days after signup. 
Week 4 represents activity occurring 28–34 days after signup. 
 
Grain 
----- 
One row per signup cohort week. 
 
Output 
------ 
cohort_week, 
cohort_size, 
w0_active, 
w1_retained, 
w2_retained, 
w3_retained, 
w4_retained, 
w1_retention_rate, 
w2_retention_rate, 
w3_retention_rate, 
w4_retention_rate 
 
Business Interpretation 
----------------------- 
Retention is measured independently for each relative week. A customer is 
counted as retained in a given week if they perform at least one meaningful 
action during that specific week. 
 
Customers are not required to be active in previous weeks to be counted in a 
later week. As a result, retention counts are not required to decrease 
monotonically across every individual cohort. A customer may skip one or more 
weeks and return later. 
 
PM Recommendation 
----------------- 
If Week 1 retention falls below 20%, the primary bottleneck is likely 
activation. In this case, the next sprint should focus on improving the 
early user experience and helping new users reach their first meaningful 
product interaction sooner. 
 
Potential actions include: 
 
• Improve onboarding guidance and product education. 
• Reduce friction before the first meaningful action. 
• Identify where newly signed-up users abandon the activation journey. 
• Test prompts, nudges, or guided workflows that encourage early engagement. 
 
If Week 1 retention is healthy but retention drops significantly by Week 4, 
the primary issue is likely habit formation rather than activation. 
 
Potential actions include: 
 
• Introduce recurring product value or repeat-use triggers. 
• Test reminders, notifications, or re-engagement campaigns. 
• Identify features associated with users who remain active over multiple weeks. 
• Investigate whether users receive enough ongoing value after their initial 
  activation. 
 
Sanity Checks Performed 
----------------------- 
 
1. Cohort Baseline Validation 
 
   Verified that: 
 
   w0_active = cohort_size 
 
   Week 0 is treated as the signup cohort baseline rather than requiring a 
   separate meaningful session during the signup period. 
 
   Result: 
   ✓ Passed. 
 
2. Pre-Signup Activity Validation 
 
   Verified that sessions occurring before a customer's signup time are 
   excluded from the retention calculation. 
 
   The timestamp condition is placed in the LEFT JOIN condition rather than 
   the WHERE clause to preserve customers with no meaningful sessions. 
 
   Result: 
   ✓ Passed. 
 
3. Customer-Week Deduplication 
 
   Verified that each customer is counted at most once within each relative 
   week using DISTINCT on customer_id, cohort_week, and week_index. 
 
   Result: 
   ✓ Passed. 
 
4. Relative Week Validation 
 
   Verified that retention is calculated using the time difference between 
   session start and signup time rather than calendar-week activity. 
 
   Result: 
   ✓ Passed. 
 
5. Censoring Awareness 
 
   Event instrumentation began on 2026-04-19, so cohorts before this date 
   are excluded. More recent cohorts may not yet have had enough time to 
   reach Weeks 2, 3, or 4 and should not be interpreted as having zero 
   retention for unobserved periods. 
 
Design Note 
----------- 
This solution calculates retention relative to each customer's individual 
signup time rather than grouping activity into calendar weeks. 
 
The customer_week_activity CTE establishes one row per customer per relative 
week, ensuring that multiple meaningful sessions within the same week do not 
inflate retention counts. 
 
Week 0 is used as the cohort baseline and is therefore equal to cohort_size. 
Weeks 1 through 4 measure independent behavioral retention based on whether 
the customer performed at least one meaningful action during the respective 
relative week. 
 
Because retention is measured independently by week, customers may become 
inactive and later return. Therefore, individual cohort retention curves are 
not guaranteed to decrease monotonically across every week. 
 
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