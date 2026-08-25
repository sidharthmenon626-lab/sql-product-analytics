# B2C vs B2B Analytics — 10 SQL Queries (Task 2)

Ten SQL queries split across two real-shaped warehouses — `ecom` (B2C, 5 queries) and `saas` (B2B, 5 queries) — built to answer the same underlying questions (how do users activate, where does the funnel leak, what does retention look like, where does revenue come from) in two structurally different businesses.

**Skills:** PostgreSQL · Metabase · CTE Pipelines · Window Functions · Funnel & Retention Analysis · SaaS Unit Economics

**House style:** CTEs over subqueries · window functions for trend/ranking/percentiles · `NULLIF(..., 0)` on every denominator · every query header-commented with its business question, definitions, and an explicit sanity-check assertion.

## 📌 Executive Summary

- **The two funnels aren't even the same shape.** B2C checkout is 5 steps inside one session, minutes apart; B2B trial conversion is measured in 14/30/60-day time windows, not discrete steps.
- **"Retention" means two different things.** B2C retention (E3) is % of people active weekly; B2B retention (S3) is % of MRR kept over 12 months — B2B's version can exceed 100% via expansion.
- **B2C moves in days, B2B moves in months.** Median time to B2C activation ranges ~1.9–3.2 days across cohorts (E1); median time to a B2B plan upgrade is **417 days** (S5).
- **Money leaks and grows differently.** In B2C, high-value carts abandon *less often* but still account for ~65% of lost GMV (E5). In B2B, 70% of expansion MRR comes from a single lever — plan upgrades (S5).
- **B2B's earliest usage signal barely exists.** At the required N=3 feature-adoption threshold, **zero of 1,193 eligible accounts** adopted any of 50 features in their first 14 days (S4) — a real finding, not a query bug.

## At a glance

| Dimension | B2C (ecom) | B2B (saas) |
|---|---|---|
| Funnel shape | 5 steps within one session | Time windows (14/30/60-day) |
| Retention unit | % of people active | % of MRR retained |
| Retention cadence | Weekly | 12-month cohort |
| Biggest $ leak/lever | High-value cart abandonment | Plan-upgrade expansion |
| Time to key event | ~2–3 days (activation) | ~417 days (plan upgrade) |
| Usage signal density | High (every visit = data) | Low (0 adopters at required threshold) |

## 📊 Key Charts
*E2 — Stage-to-stage checkout funnel by acquisition channel. The drop is nearly identical across all five channels at Payment→Purchase (~8%); a payment-experience issue, not a channel one.*
<img width="500" height="500" alt="e2_checkout_funnel_by_channel" src="https://github.com/user-attachments/assets/ec24ff14-9a66-4c5a-863d-5a23852bc13b" />

*E5 — Abandonment rate falls as cart value rises (53%→12%), but GMV left on the table inverts: ~65% of it sits in the top two value buckets.*
<img width="500" height="500" alt="e5_abandonment_rate_vs_gmv_lost" src="https://github.com/user-attachments/assets/e6e376db-a582-493a-a7cf-8d756378f4df" />

*S1 — Monthly MRR movement by driver. New MRR dominates every month, expansion is the steady second contributor, and churn briefly spikes in January and March 2026 (deepest at −₹13,821 in March) before recovering — net movement stays positive throughout, growing ending MRR from ~₹146.6K to ~₹347K over the 13-month window.*
<img width="358" height="278" alt="s1_mrr_waterfall" src="https://github.com/user-attachments/assets/5caddefe-2ae2-4629-b9dd-776e9f5495bf" />

*S5 — 70% of 6-month expansion MRR comes from plan upgrades (median 417 days to happen), 30% from seat adds (faster, median 76 days), and addons are negligible (~0.3%, median 59 days, just 1 account).*
<img width="500" height="500" alt="s5_expansion_revenue_mix" src="https://github.com/user-attachments/assets/414fc820-8284-4052-8161-80a39ecaeb35" />


> **Note:** S5 filters on `current_date - interval '6 months'`, not a fixed date. The exact total (and the `seats_added` share specifically) will drift slightly depending on when this chart was captured relative to when the rest of this analysis was run — the percentage split above is stable even if the absolute ₹ total moves.

## 📄 Case study

The full write-up — a memo comparing what the B2C and B2B query sets say about funnel shape, retention, revenue, and speed — lives in Notion:

**[B2C vs B2B: How Funnels and Retention Actually Differ](https://shy-position-1fc.notion.site/B2C-vs-B2B-How-Funnels-and-Retention-Actually-Differ-3c4a3c1d0a29811ba68def1642cd366d)**

(Also mirrored in full in `Case_study.md` in this folder.)

## 🔗 Author

Sidharth Menon — [LinkedIn](https://www.linkedin.com/in/sidharthmenon793)

## 📂 Queries

| # | File | Schema | Business question | Key data insight |
|---|------|--------|-------------------|-------------------|
| E1 | [`e1_activation_curve_time_to_meaningful_action.sql`](queries/e1_activation_curve_time_to_meaningful_action.sql) | ecom | How quickly do new signups take a meaningful action? | 7-day activation rates run **9%–22%** across cohorts; median time-to-activation ranges ~1.9–3.2 days |
| E2 | [`e2_checkout_funnel_by_channel.sql`](queries/e2_checkout_funnel_by_channel.sql) | ecom | Where does checkout leak, and does it differ by channel? | Payment→Purchase loses **~8%** on every channel — a payment-experience issue, not a channel one |
| E3 | [`e3_cohort_retention_curve_behavioral.sql`](queries/e3_cohort_retention_curve_behavioral.sql) | ecom | Of new signups, who comes back and does something in weeks 1–4? | Week-1 retention **14%–36%** (fully-observed cohorts); non-monotonic — customers skip weeks and return |
| E4 | [`e4_pdp_engagement.sql`](queries/e4_pdp_engagement.sql) | ecom | Which products get views but not add-to-carts? | 3,996 products benchmarked against category-median ATC rate; low-view flags are mostly noise |
| E5 | [`e5_cart_abandonment_by_value_bracket.sql`](queries/e5_cart_abandonment_by_value_bracket.sql) | ecom | Is cart abandonment the same across cart values? | Abandonment rate falls with cart size (53%→12%), but **~65%** of abandoned GMV sits in the top 2 value buckets |
| S1 | [`s1_monthly_mrr_decomposition.sql`](queries/s1_monthly_mrr_decomposition.sql) | saas | How did MRR move each month, and why? | Ending MRR grew **~₹146.6K → ~₹347K** over 13 months; waterfall reconciles exactly |
| S2 | [`s2_trial_to_paid_conversion_by_cohort.sql`](queries/s2_trial_to_paid_conversion_by_cohort.sql) | saas | What share of trials convert by day 14/30/60? | Monotonic in all 85 cohorts; median trial-to-paid **9–14 days**; weekly cohorts too thin (1–8/week) to trust individually |
| S3 | [`s3_grr_nrr_by_cohort.sql`](queries/s3_grr_nrr_by_cohort.sql) | saas | How much of a cohort's starting MRR did we keep (and grow)? | GRR **0.00–1.00** (one thin, fully-churned outlier cohort aside, 0.47–1.00), NRR up to **2.31**; GRR does not net out contraction (logo-weighted) |
| S4 | [`s4_feature_adoption_retention.sql`](queries/s4_feature_adoption_retention.sql) + [`s4_feature_adoption_retention_sensitivity.sql`](queries/s4_feature_adoption_retention_sensitivity.sql) | saas | Which features predict 90-day retention? | **Zero adopters** at the required N=3 threshold, across all 1,193 eligible accounts; N=1 sensitivity shows API Bulk Operations as the strongest thin signal |
| S5 | [`s5_expansion_revenue.sql`](queries/s5_expansion_revenue.sql) | saas | Who's expanding MRR, and how? | **70%** of 6-month expansion MRR is plan upgrades (median 417 days to happen); total drifts over time vs. S1 since S5 uses `current_date`, not a fixed window |

Each query lives in the `queries/` folder.

## 🚀 How to run

1. Open Metabase → **New Question → Native query** → select the **`ecom`** or **`saas`** schema depending on the query.
2. Paste any `.sql` file into the editor and run it — each is self-contained (no setup scripts, no temp tables).
3. Check the header comment's **sanity-check assertion** first, before trusting the output.
4. S1 uses a rolling 12-month window ending 2026-06-15. S3 only has an upper-bound cutoff of 2026-06-15 — it has **no lower-bound date filter**, so its cohorts run back to 2022, much further than S1's window. E1/E3 both exclude signups before **2026-04-19** (event instrumentation launch) — E1's displayed week bucket for that first cohort shows as "April 13" purely because `date_trunc('week', ...)` rounds down to that week's Monday, not because 04-13 is a separate cutoff. Adjust the date literals to re-point at a different period.
5. No Metabase access? Any Postgres client (psql, DBeaver) connected to the same schemas runs these unchanged.

## 🧠 Reflection

- **What I learned.** Running the same analytical lens on two different business models exposed that "funnel" and "retention" aren't universal concepts — they take on the shape of the business they're measuring. Forcing a B2C funnel template onto B2B data (or vice versa) would have produced a misleading chart, not a comparable one.
- The most useful finding wasn't a headline metric — it was a **null result**: zero feature adopters at the required N=3 threshold (S4). Confirming that was real (not a query bug) took independently recomputing every denominator, and it turned out to be a genuine, actionable product-onboarding signal.
- Cross-checking queries against each other caught real things: the first CSV pull of S5's expansion MRR total matched S1's independently-computed figure to the cent (₹14,391.06 both ways) — strong evidence both queries were internally consistent at that point in time. A later live pull came in at ₹14,292.06, ~₹99 lower, because S5 filters on `current_date` rather than a fixed date like S1 — the window shifted between pulls. The percentage split (70/30/~0.3) held steady either way; only the absolute total moved.
- **What I'd do differently.** I'd re-run S2 and S4 at monthly cohort grain from the start — weekly B2B cohorts (1–8 trials/week) are too thin to read as signal, and I only found that out after building the weekly version first.
- I'd also confirm the exact CSV export precision before writing the memo — Metabase's export silently rounds rate columns to 2 decimals even when the SQL computes 4, which I only caught by recomputing from raw counts.
