/*
===============================================================================
Query S4 - Feature Adoption vs Retention - N=1 Sensitivity Analysis
===============================================================================

Business Question
-----------------
Which product features are associated with stronger 90-day retention, and which
features appear to be red herrings?

Definitions
-----------
Feature Adopted:
For this sensitivity analysis, an account is considered to have adopted a
feature if it uses that feature at least once within the first 14 days after
signup (N = 1).

Primary Threshold:
The required primary analysis uses N = 3 feature uses within the first
14 days. Because no eligible accounts reach that threshold, this N = 1
version is maintained as a separate sensitivity analysis and does not replace
the primary result.

Retained at 90 Days:
An account is retained if its subscription covers the account's 90-day
anniversary of signup. Retention is determined using subscription start_date,
end_date, and cancelled_at.

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
The required N = 3 adoption threshold produces no feature adopters in the
eligible cohort, making a feature-level retention comparison impossible under
the primary definition.

The N = 1 sensitivity analysis produces enough variation to explore
directional relationships between early feature usage and 90-day retention.
However, small adopter populations can create very large and unstable
retention lifts.

API Bulk Operations is the strongest practical candidate because it combines
a positive retention lift with a larger adopter population than features whose
larger lifts are based on only 1–3 adopters.

The observed relationships are associative rather than causal. Accounts that
adopt features may already differ in engagement, usage intensity, or other
characteristics that also influence retention.

PM Recommendation
-----------------
Do not immediately launch a discoverability push based solely on this
sensitivity analysis.

Treat API Bulk Operations as the strongest candidate for deeper investigation
before introducing an in-app prompt, onboarding placement, or default-on
treatment.

The next analysis should control for overall usage intensity or use a
propensity-matched comparison to determine whether the observed retention
association remains after accounting for selection bias.

Sanity Checks Performed
-----------------------

1. Eligible Account Reconciliation

Verified that the eligible cohort contains 1,193 accounts.

For every feature:

    accounts_adopted + accounts_not_adopted = 1,193

Result:
✓ Passed.

2. Adoption Threshold Validation

Verified that feature adoption in this sensitivity analysis requires:

    feature_uses_14d >= 1

Result:
✓ Passed.

The N = 1 threshold is used only in this separate sensitivity analysis.

3. Retention Definition Validation

Verified that an account is considered retained only when its subscription
covers the account's 90-day anniversary, using start_date, end_date, and
cancelled_at.

Result:
✓ Passed.

4. Feature Attribution Validation

Feature adoption is based on the reliable:

    events.feature_id → features.feature_id

join path.

76 feature_use events without account_id cannot be attributed to an account
and are excluded from the account-level analysis.

1,520 events without feature_id are excluded from feature adoption analysis.
Legacy rows containing feature names only in properties are not backfilled
through text matching.

Result:
✓ Passed.

Design Note
-----------
This analysis creates a complete account × feature population using a CROSS
JOIN between eligible accounts and the feature catalog.

Feature usage during the first 14 days is then LEFT JOINed onto this complete
population. This ensures that both adopters and non-adopters are represented
for every feature and allows the adopted and non-adopted counts to reconcile
to the full eligible-account population.

No minimum adopter-count filter is applied. All features are retained in the
output, including features with negative retention lift or zero adopters.

To reduce the prominence of unstable tiny-sample lifts, results are ordered by
accounts_adopted descending and then retention_lift_pp descending. This is a
presentation choice rather than a statistical significance test.

The analysis remains observational. A future version should control for
account usage intensity or use propensity matching before interpreting feature
adoption as a causal driver of retention.

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
            when coalesce(fu.feature_uses_14d, 0) >= 1
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
    accounts_adopted desc
    ,retention_lift_pp desc nulls last;

