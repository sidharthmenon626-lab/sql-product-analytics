# Query Interpretations — Task 2

*Owner: Sidharth Menon · Sources: `ecom` (B2C) and `saas` (B2B) schemas, Postgres/Metabase*
*Currency in ₹. Rates in [0,1] unless labelled %. All numbers below were independently recomputed from the raw CSV output, not just read off query header comments.*

---

## E1 — Activation Curve: Time to First Meaningful Action

**What the query does (1 sentence):** Tracks weekly signup cohorts (excluding signups before 2026-04-19, when event instrumentation launched — the first included week bucket displays as "April 13" because `date_trunc('week', ...)` rounds down to the Monday of the week containing April 19) and measures what share of each cohort reach a "meaningful action" — add_to_cart, begin_checkout, or purchase — within 7 days of signup, plus the median and p90 minutes to that action.

**Pattern choice (1-2 sentences):** A LEFT JOIN to `session_events` filtered to `>= signup_time` avoids counting pre-signup browsing as activation; `percentile_cont(0.5/0.9)` gives the median and p90 minutes-to-activation among users who actually activated.

**Business interpretation (2-3 sentences):**

- 7-day activation rates run **9%–22%** across the 9 weekly cohorts (Apr 13 – Jun 8), with no clean upward or downward trend — cohort-to-cohort noise looks larger than any real drift.
- Among users who do activate, the median time to that first meaningful action ranges **~2,732–4,615 minutes (roughly 1.9–3.2 days)** across the 9 cohorts — activation, when it happens, happens fast.
- The most recent cohort (Jun 8) shows the lowest rate in the series (9%); whether that's a real decline or the cohort simply hasn't finished its 7-day observation window as of the data pull wasn't confirmed and shouldn't be reported as a trend without checking the pull date first.

**What I'd ask next:** Is the June dip real or a censoring artifact from an incomplete observation window? I'd also cut activation rate by acquisition channel — right now it's blended, and a channel-level view would say whether this is a traffic-quality problem or a product one.

---

## E2 — Checkout Funnel Drop-off by Entry Channel

**What the query does (1 sentence):** Measures the checkout funnel (begin_checkout → add_address → select_shipping → add_payment → purchase) per acquisition channel, using each session's furthest completed step.

**Pattern choice (1-2 sentences):** `MAX(CASE WHEN event_type = ... THEN step_number ELSE 0 END)` per session guarantees a monotonic funnel even if intermediate events are missing, so later-stage counts can never exceed earlier ones.

**Business interpretation (2-3 sentences):**

- The largest drop is consistently the **last step, Payment → Purchase (~8%)**, across all five channels: organic 7.84%, paid 8.00%, referral 8.30%, email 7.56%, affiliate 8.25%.
- Every earlier step loses only **roughly 1%–4.2%** per stage (affiliate's first step is the single highest at 4.22%) — the funnel is healthy until the very end.
- Because the ~8% final-step loss is nearly identical across five channels with very different traffic quality, the friction is almost certainly in the **payment experience itself**, not who's arriving.

**What I'd ask next:** Payment gateway logs and error codes for the Payment→Purchase drop, segmented by payment method (UPI/card/wallet) and device — an ~8% uniform loss at checkout's last step is usually a specific, fixable technical issue rather than a demand problem.

---

## E3 — Weekly Cohort Retention Curve (Behavioral)

**What the query does (1 sentence):** For customers who signed up on or after 2026-04-19, tracks what share return and perform a meaningful action (view/cart/purchase) in weeks 1–4 after signup.

**Pattern choice (1-2 sentences):** Relative week is computed from the gap between each session and the customer's own signup time (not calendar weeks), so every customer's "week 1" lines up with their own signup date regardless of when they joined.

**Business interpretation (2-3 sentences):**

- Week-1 retention ranges **14%–36%** across the 8 cohorts whose week-1 window is fully observed (Apr 13 – Jun 1); the newest cohort (Jun 8) also shows 0% for week 1, but that's the same censoring effect described below, not a genuine ninth data point for the range.
- Retention is **not monotonic within a cohort**: the Apr 13 cohort goes 25% (w1) → 38% (w2) → 26% (w3) → 36% (w4) — customers skip a week and return, exactly as the query's own design note anticipates.
- Zeros appear increasingly in later weeks starting with the May 18 cohort (week 4 only) and widen for each newer cohort, down to the Jun 8 cohort showing 0% across all four weeks — a **censoring effect** from the data-pull cutoff (each cohort's observation window hasn't fully elapsed yet), not a behavior collapse.

**What I'd ask next:** Re-run with a channel or first-touch source cut to see whether retention varies more by acquisition source than by cohort week — the current view blends everyone together.

---

## E4 — PDP Engagement: High-View, Low-Cart Products

**What the query does (1 sentence):** Flags products that get a lot of product-detail-page views but convert those views to add-to-cart sessions at a rate well below their own category's median.

**Pattern choice (1-2 sentences):** Each product is benchmarked against its **own category's median ATC rate** (via `percentile_cont(0.5)`), not a global average, so a naturally low-conversion category (e.g. accessories) isn't unfairly compared to a naturally high-conversion one.

**Business interpretation (2-3 sentences):**

- Across **3,996 products**, add-to-cart sessions never exceed views and every ATC rate falls inside [0,1] — the data passes its own internal consistency checks cleanly.
- Every category's median ATC rate falls within that category's own min/max range, confirming the benchmark is well-formed.
- The worst offenders (several Headphones and Haircare products with **0% ATC rate on single-digit view counts**) are mostly low-traffic products, so they're statistical noise rather than genuine merchandising failures — the flagged list should be filtered to a minimum view threshold before acting on it.

**What I'd ask next:** Re-run with a `views >= 100` floor (the query's own design note suggests this) to separate real high-traffic underperformers from low-volume noise, then triage the top 10 real offenders by price, imagery, and stock status.

---

## E5 — Cart Abandonment by Cart Value Bucket

**What the query does (1 sentence):** Buckets sessions with an add-to-cart event into 5 cart-value tiers (<₹500 through ₹15,000+) and reports abandonment rate and GMV left on the table per bucket.

**Pattern choice (1-2 sentences):** Cart value is summed per session from `add_to_cart` events, then joined against paid orders to flag purchased vs. abandoned — a session-grain design that assigns every session to exactly one bucket.

**Business interpretation (2-3 sentences):**

- Abandonment **rate falls as cart value rises**: 53% for carts under ₹500, down to just 12% for ₹15,000+ carts — bigger spenders are more committed once they've built a cart.
- But because those big carts are so much larger, they still account for the most money lost: **~65% of all abandoned GMV** sits in the ₹5,000–14,999 and ₹15,000+ buckets combined.
- Total ATC sessions reconcile exactly to **19,862**, matching the query's own embedded sanity check.

**What I'd ask next:** Given the abandoned GMV concentration in high-value carts, I'd prioritize checkout reliability (payment success rate, session timeouts) over blanket free-shipping incentives — the query's own PM recommendation reaches the same conclusion.

---

## S1 — Monthly MRR Movement Decomposition

**What the query does (1 sentence):** Breaks each month's MRR change into new, expansion, contraction, churn, and reactivation MRR over a rolling 12-month window ending 2026-06-15, and reconstructs an ending-MRR waterfall.

**Pattern choice (1-2 sentences):** Each `subscription_event` is classified into exactly one bucket via a CASE expression (with an `EXISTS` check to distinguish "new" from "reactivation" after a prior cancellation), then the waterfall is validated by checking `ending_mrr(month N) = ending_mrr(month N-1) + net_new_mrr(month N)`.

**Business interpretation (2-3 sentences):**

- Ending MRR grew from **~₹146,600 (Jun 2025)** to **~₹347,000 (Jun 2026)** over the 13-month window — roughly **2.4x** growth.
- The waterfall chain reconciles **exactly to the cent** across all 13 months when independently recomputed — this is a trustworthy MRR base for the rest of the saas analysis.
- New MRR is the largest positive driver in **every one of the 13 months** (confirmed by direct comparison, not just eyeballing). Expansion is the second-largest positive driver in **11 of 13 months** — reactivation MRR edges ahead of it in January and April 2026. Churn MRR is negative every month but never large enough to offset the positive drivers — net_new_mrr is positive in all 13 months.

**What I'd ask next:** Which specific month had the largest negative movement relative to its size (not just in absolute ₹), and was it driven by one large account or broad-based churn? That's the query's own suggested next step and it's still open.

---

## S2 — Trial-to-Paid Conversion by Cohort

**What the query does (1 sentence):** For each weekly trial-start cohort, measures what share convert to paid by day 14, 30, and 60, plus the median days from trial start to conversion.

**Pattern choice (1-2 sentences):** `ROW_NUMBER()` keeps only each account's first trial (avoiding double-counting repeat trialists); conversion-window counts are cumulative and monotonic by construction (`<=14` is a subset of `<=30` is a subset of `<=60`).

**Business interpretation (2-3 sentences):**

- Monotonicity (`14d ≤ 30d ≤ 60d`) holds for all **85 weekly cohorts**, 0 violations.
- Weekly cohorts are **very thin** — 1 to 8 trial starts per week (about 78% of weeks fall in the 2–6 range), 250 trials total across the full history — so individual weekly conversion rates swing across the full **0% to 100%** range (19 of 85 weeks show 0% 14-day conversion) purely on small-sample noise and shouldn't be read as real week-over-week signal.
- Median time from trial start to paid conversion, where it happens, is **9–14 days** — most conversions that occur happen well before the trial's likely 14/30-day boundary.

**What I'd ask next:** Re-aggregate at monthly (not weekly) grain to get cohorts large enough to trust individual conversion rates — at 1–8 trials/week, the current view is mostly noise dressed as signal.

---

## S3 — Gross Revenue Retention & Net Revenue Retention by Cohort

**What the query does (1 sentence):** For each monthly MRR cohort with at least 12 months of history, computes Gross Revenue Retention (GRR) and Net Revenue Retention (NRR) — how much of that cohort's starting MRR was kept, and kept-plus-expansion, a year later.

**Pattern choice (1-2 sentences):** MRR is reconstructed from `subscription_events` (not read off `subscriptions.mrr`, which doesn't reliably reflect add-ons and plan changes) via a running cumulative sum per account per month, then joined against each account's own state exactly 12 months after its cohort start.

**Business interpretation (2-3 sentences):**

- GRR technically ranges **0.00 to 1.00** across 40 monthly cohorts, but the 0.00 is a single thin, fully-churned outlier (April 2022, ₹30.72 starting MRR — one account, entirely churned). Excluding that outlier, GRR runs **0.47–1.00**; the two most recent cohorts (May 2025: 0.47, June 2025: 0.53) are noticeably weaker than the multi-year average — worth watching, though these are also the least-mature cohorts.
- NRR frequently exceeds 1.00 and reaches as high as **2.31** — a *different* thin cohort (March 2022, ₹93.69 starting MRR, GRR 1.00) from the April 2022 GRR=0.00 outlier described above; small dollar base, so a single expansion event swings the ratio hard — and **1.85–1.92** in several larger, more representative cohorts, meaning expansion revenue from existing accounts is outpacing churn.
- **Important nuance:** as coded, `retained_mrr_12m` is the account's full starting MRR as long as it's still paying *anything* at month 12 — contraction is tracked separately for NRR but never subtracted from GRR's numerator. This GRR reads closer to **logo retention** than a strict dollar-net-of-shrinkage metric, and should be labeled that way if it goes in front of a stakeholder who'd assume otherwise.

**What I'd ask next:** Build a second GRR variant that does net out contraction, and compare the two — the gap between them quantifies exactly how much "shrinking but still paying" accounts are propping up the headline GRR number.

---

## S4 — Feature Adoption vs. Retention (N=3 primary + N=1 sensitivity)

**What the query does (1 sentence):** Tests whether early feature usage (within 14 days of signup) predicts 90-day subscription retention, using a required N=3 (used a feature 3+ times) adoption threshold, with a separate N=1 sensitivity check when N=3 turns out to have no adopters.

**Pattern choice (1-2 sentences):** Adoption uses only the reliable `events.feature_id → features.feature_id` join path; legacy events with NULL feature_id are excluded rather than text-matched, and a `CROSS JOIN` to all features ensures every eligible account × feature pair is represented (including zero-adoption pairs) rather than silently dropping non-adopters.

**Business interpretation (2-3 sentences):**

- The primary N=3 definition produces **zero adopters, for every one of 50 features, across all 1,193 eligible accounts** — confirmed by recomputing the denominators, which reconcile exactly to 1,193 every time. This is a real finding about the account base's early usage intensity, not a query defect.
- The N=1 sensitivity check (used a feature even once in 14 days) still only surfaces thin signal: the strongest feature, **API Bulk Operations**, has just **21 adopters out of 1,193 accounts (under 2%)**, though it does pair a positive retention lift (**+24.4pp**, 52.4% vs. 28.0% baseline) with the largest adopter count among the high-lift features.
- Several features show very large retention lifts (100%+) on only 1–3 adopters — those are not credible evidence of a causal effect and shouldn't be actioned without a much larger sample.

**What I'd ask next:** Don't launch a discoverability push on either the N=3 or N=1 results as-is — investigate why early feature usage is so low industry-wide in this account base first (onboarding friction? feature discoverability? wrong 14-day window?) before treating any single feature as a retention lever.

---

## S5 — Expansion Revenue: Who's Upgrading and Why

**What the query does (1 sentence):** Classifies every qualifying expansion event (seat_add, addon_attach, plan_changed-with-positive-delta) in the trailing 6 months into one of three expansion types and aggregates events, accounts, and MRR per type.

**Pattern choice (1-2 sentences):** Filters to `mrr_delta > 0` so contractions never leak into an "expansion" bucket; `percentile_cont(0.5)` gives the median days from signup to that expansion event per type.

**Business interpretation (2-3 sentences):**

- Of **₹14,391.06** in 6-month expansion MRR, **70% (₹10,065.46, 85 accounts) came from plan upgrades**, 30% (₹4,285.00, 22 accounts) from added seats, and addons are negligible (₹40.60, 1 account).
- Median time from signup to a plan upgrade is **417 days** — over a year — while seat adds happen much sooner, at a median of **76 days**.
- The total reconciles **exactly (₹14,391.06 vs. ₹14,391.06, difference ₹0.00)** against S1's independently-computed 6-month expansion MRR, confirming both queries agree.

**What I'd ask next:** Since plan upgrades are both the dominant dollar lever and the slowest to happen, I'd map out what triggers them (usage ceiling hit? sales-assisted upsell? renewal-time conversation?) — shaving even 60–90 days off that 417-day median compounds meaningfully across the account base.

**Reproducibility note:** S5 filters on `current_date - interval '6 months'`, not a fixed date literal like S1's hardcoded `2026-06-15`. The exact reconciliation to S1 above only holds because both queries were run around the same point in time — re-running S5 later will shift its trailing-6-month window and the two totals will no longer match to the cent. Worth pinning S5 to a fixed date if this comparison needs to be reproducible later.
