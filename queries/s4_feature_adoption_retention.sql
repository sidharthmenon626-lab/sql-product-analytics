/*
===============================================================================
S4 — Feature Adoption vs Retention
===============================================================================

Business question:
Which product features are associated with stronger 90-day retention?
Which features appear to be red herrings?

Methodology:
- Eligible accounts are accounts whose signup date was at least 90 days
  before the analysis cutoff of 2026-06-15.
- 90-day retention means the account had a subscription covering the
  90-day anniversary of signup.
- Feature adoption is defined as using a feature at least 3 times in the
  first 14 days after signup (N = 3), using the required default threshold.
- Feature adoption uses the reliable events.feature_id → features.feature_id
  join path. Legacy events with NULL feature_id are excluded rather than
  attempting text-based feature matching.
- Events without an account_id cannot be attributed to an account and are
  excluded from account-level adoption analysis.
- Retention lift is observational, not causal. Accounts that adopt features
  may differ systematically in engagement, usage intensity, or customer
  characteristics. A propensity-matched comparison or adjustment for usage
  intensity would be the appropriate next step.

Important interpretation:
- N = 3 is the primary/default adoption definition and is not changed to
  manufacture a larger adopter population.
- In the eligible cohort, N = 3 produces no feature adopters. Therefore,
  the primary definition cannot produce a meaningful feature-level
  retention comparison.
- A separate N = 1 sensitivity analysis is used to assess whether any
  directional feature-retention signal is observable under a less stringent
  adoption definition. That analysis is documented separately and should
  not be interpreted as replacing the N = 3 result.

Data-quality notes:
- 76 feature_use events have no account_id and are excluded because they
  cannot be attributed to an account.
- 1,520 events have no feature_id and are excluded from feature adoption
  analysis because the feature cannot be reliably identified.
- Legacy event rows contain feature names in properties rather than
  feature_id, indicating vocabulary/schema drift. These rows are not
  backfilled through text matching.

Sanity check:
- accounts_adopted + accounts_not_adopted must equal the total number of
  eligible accounts for every feature.
- The eligible cohort contains 1,193 accounts, so every feature should
  reconcile to 1,193 accounts.

PM action:
- Do not launch a discoverability push based on the N = 3 analysis because
  there are no adopters under the required threshold.
- Use the separate N = 1 sensitivity analysis only as exploratory evidence.
- If a directional signal appears in the sensitivity analysis, investigate
  it further before recommending onboarding placement, default-on treatment,
  or an in-app prompt.
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

