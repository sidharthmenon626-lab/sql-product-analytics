/*
===============================================================================
S4 — Feature Adoption vs Retention — N=1 Sensitivity Analysis
===============================================================================

Business question:
Which product features are associated with stronger 90-day retention?
Which features appear to be red herrings?

Purpose:
- The required primary definition uses N = 3 feature uses in the first 14 days.
- In the eligible cohort, N = 3 produces no feature adopters.
- This query therefore runs a transparent N = 1 sensitivity analysis to assess
  whether any directional feature-retention signal is observable under a less
  stringent adoption definition.
- N = 1 is a sensitivity analysis only and does not replace the required
  N = 3 definition.

Methodology:
- Eligible accounts are accounts whose signup date was at least 90 days
  before the analysis cutoff of 2026-06-15.
- 90-day retention means the account had a subscription covering the
  90-day anniversary of signup.
- Feature adoption for this sensitivity analysis is defined as using a
  feature at least once in the first 14 days after signup.
- Feature adoption uses the reliable events.feature_id → features.feature_id
  join path. Legacy events with NULL feature_id are excluded rather than
  attempting text-based feature matching.
- Events without an account_id cannot be attributed to an account and are
  excluded from account-level adoption analysis.
- Retention lift is observational, not causal. Accounts that adopt features
  may differ systematically in engagement, usage intensity, or customer
  characteristics.
  Adopter-count handling:
- No minimum adopter-count filter is applied so that all feature results remain
  visible, including negative and zero-adopter results.
- Results are ordered by accounts_adopted descending, then retention_lift_pp
  descending, so features with stronger adopter volume appear before features
  whose lift is based on very small samples.
- This ordering is a presentation choice, not a statistical significance test.
  Small adopter populations can still produce unstable retention lifts and
  should not be treated as credible evidence without further investigation.

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
- Run the eligible-account count separately and confirm the feature-level
  denominators reconcile to that population.

Interpretation:
- N = 1 produces more usable variation than the required N = 3 threshold,
  but small adopter counts can create very large and unstable lifts.
- Results are ordered by adopter count first so features with stronger
  observational support appear above features with very small adopter
  populations. Within the same adopter count, higher retention lift ranks
  first.
- API Bulk Operations is the strongest practical candidate in this sensitivity analysis because it combines a positive retention lift with a    larger adopter population than the features producing very large lifts from only 1–3 adopters.
- The observed relationship should not be interpreted as causal. A
  propensity-matched comparison or adjustment for usage intensity would be
  the appropriate next step.

PM action:
- Do not immediately launch a discoverability push based on the N = 1
  sensitivity analysis.
- Treat API Bulk Operations as a candidate for deeper investigation before
  onboarding placement, default-on treatment, or an in-app prompt.
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

