/*
===============================================================================
Query S4 - Feature Adoption vs Retention
===============================================================================

Business Question
-----------------
Which product features predict 90-day retention, and which features appear to
be red herrings?

Definitions
-----------
Feature Adopted:
An account is considered to have adopted a feature if it uses that feature at
least 3 times within the first 14 days after signup.

Retained at 90 Days:
An account is retained if its subscription is still active 90 days after
signup. This is determined using subscription start_date, end_date, and
cancelled_at rather than billing-period fields.

Eligible Accounts:
Accounts whose signup date is at least 90 days before the analysis cutoff of
2026-06-15.

Grain
-----
One row per product feature.

Output
------
feature_name,
accounts_adopted,
accounts_not_adopted,
retention_rate_adopted_pct,
retention_rate_not_adopted_pct,
retention_lift_pp,
retention_lift_pct

Business Interpretation
-----------------------
The required N = 3 adoption threshold produces no feature adopters within the
eligible cohort of 1,193 accounts. Therefore, the primary analysis cannot
produce a meaningful feature-level comparison of 90-day retention.

This is a data finding rather than a SQL issue: repeated feature usage within
the first 14 days is too sparse in the available event data to support the
required adoption definition.

A separate N = 1 sensitivity analysis is maintained to explore whether any
directional feature-retention relationship becomes visible under a less
stringent definition. That analysis does not replace the primary N = 3 result.

PM Recommendation
-----------------
Do not launch a discoverability push, onboarding change, default-on treatment,
or in-app prompt based on the N = 3 analysis because no feature reaches the
required adoption threshold.

Use the N = 1 sensitivity analysis only for exploratory investigation. Any
feature showing a positive association with retention should be tested further
while controlling for overall account usage intensity or through a
propensity-matched comparison.

Sanity Checks Performed
-----------------------

1. Eligible Account Reconciliation

Verified that the eligible cohort contains 1,193 accounts.

For every feature:

    accounts_adopted + accounts_not_adopted = 1,193

Result:
✓ Passed.

2. Adoption Threshold Validation

Verified that feature adoption requires:

    feature_uses_14d >= 3

Result:
✓ Passed.

No eligible account reaches the N = 3 adoption threshold.

3. Retention Definition Validation

Verified that an account is considered retained only when its subscription
covers the account's 90-day anniversary, using start_date, end_date, and
cancelled_at.

Result:
✓ Passed.

4. Feature Attribution Validation

Feature adoption is based only on the reliable:

    events.feature_id → features.feature_id

join path.

Events without account_id cannot be attributed to an account and are excluded.
Events without feature_id are excluded rather than attempting unreliable
text-based matching against legacy feature names stored in properties.

Result:
✓ Passed.

Design Note
-----------
This analysis creates a complete account × feature comparison using a CROSS
JOIN between eligible accounts and the feature catalog.

Feature usage within the first 14 days is then LEFT JOINed onto this complete
population. This ensures that both adopters and non-adopters are represented
for every feature and allows:

    accounts_adopted + accounts_not_adopted

to reconcile to the full eligible-account population.

The analysis is observational and does not establish causality. Accounts that
adopt more features may already differ in engagement or usage intensity from
accounts that do not. A future analysis should control for these differences
using usage controls or propensity matching.

===============================================================================
*/

with eligible_accounts as
(
    select
        account_id
        ,signup_date
    from
        saas.accounts
    where
        signup_date + interval '90 days' <= date '2026-06-15'
)

,subscription_retention as
(
    select
        ea.account_id
        ,ea.signup_date
        ,max(
            case
                when s.start_date <= ea.signup_date + interval '90 days'
                    and (
                        s.cancelled_at is null
                        or s.cancelled_at > ea.signup_date + interval '90 days'
                    )
                    and (
                        s.end_date is null
                        or s.end_date > ea.signup_date + interval '90 days'
                    )
                    then 1
                else 0
            end
        ) as retained_90d
    from
        eligible_accounts ea
    left join
        saas.subscriptions s
        on ea.account_id = s.account_id
    group by
        ea.account_id
        ,ea.signup_date
)

,feature_usage_14d as
(
    select
        ea.account_id
        ,e.feature_id
        ,f.feature_name
        ,count(*) as feature_uses_14d
    from
        eligible_accounts ea
    join
        saas.events e
        on ea.account_id = e.account_id
    join
        saas.features f
        on e.feature_id = f.feature_id
    where
        e.event_type = 'feature_use'
        and e.occurred_at >= ea.signup_date
        and e.occurred_at < ea.signup_date + interval '14 days'
        and e.feature_id is not null
    group by
        ea.account_id
        ,e.feature_id
        ,f.feature_name
)

,feature_adoption as
(
    select
        ea.account_id
        ,f.feature_id
        ,f.feature_name
        ,coalesce(fu.feature_uses_14d, 0) as feature_uses_14d
        ,case
            when coalesce(fu.feature_uses_14d, 0) >= 3
                then 1
            else 0
        end as adopted
    from
        eligible_accounts ea
    cross join
        saas.features f
    left join
        feature_usage_14d fu
        on ea.account_id = fu.account_id
        and f.feature_id = fu.feature_id
)

,feature_retention as
(
    select
        fa.feature_id
        ,fa.feature_name
        ,count(*) filter (where fa.adopted = 1) as accounts_adopted
        ,count(*) filter (where fa.adopted = 0) as accounts_not_adopted
        ,avg(sr.retained_90d::numeric) filter (where fa.adopted = 1) as retention_rate_adopted
        ,avg(sr.retained_90d::numeric) filter (where fa.adopted = 0) as retention_rate_not_adopted
    from
        feature_adoption fa
    join
        subscription_retention sr
        on fa.account_id = sr.account_id
    group by
        fa.feature_id
        ,fa.feature_name
)

,feature_ranked as
(
    select
        feature_id
        ,feature_name
        ,accounts_adopted
        ,accounts_not_adopted
        ,retention_rate_adopted * 100 as retention_rate_adopted_pct
        ,retention_rate_not_adopted * 100 as retention_rate_not_adopted_pct
        ,(
            retention_rate_adopted
            - retention_rate_not_adopted
        ) * 100 as retention_lift_pp
        ,(
            retention_rate_adopted
            - retention_rate_not_adopted
        )
        / nullif(retention_rate_not_adopted, 0) * 100 as retention_lift_pct
    from
        feature_retention
)

select
    feature_name
    ,accounts_adopted
    ,accounts_not_adopted
    ,retention_rate_adopted_pct
    ,retention_rate_not_adopted_pct
    ,retention_lift_pp
    ,retention_lift_pct
from
    feature_ranked
order by
    retention_lift_pp desc nulls last;

