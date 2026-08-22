# Case Study Link

**[B2C vs B2B: How Funnels and Retention Actually Differ](https://shy-position-1fc.notion.site/B2C-vs-B2B-How-Funnels-and-Retention-Actually-Differ-3c4a3c1d0a29811ba68def1642cd366d)**

A memo comparing what the `ecom` (B2C) and `saas` (B2B) query sets say about how these two businesses actually behave — funnel shape, retention definition, where the money leaks or grows, and how fast each business moves. Built from queries E1–E5 (ecom) and S1–S5 (saas) in this folder.

Hosted publicly on Notion (Share to web enabled), matching the Task 1 case study.

---

# B2C vs B2B: How Funnels and Retention Actually Differ

> **To:** Product & Growth teams · **From:** Sidharth Menon (Data) · **Re:** What the `ecom` (B2C) and `saas` (B2B) query sets say about how these two businesses actually behave
>
> **Sources:** internal Postgres, `ecom` and `saas` schemas (Metabase) · Currency in ₹
>
> **Queries:** E1–E5 (ecom, B2C) and S1–S5 (saas, B2B)

Same analyst, same toolkit, two different businesses. Running the same rigor on both surfaced something more interesting than "which business is healthier" — the two models don't just have different numbers, they have **different shapes of funnel, different units of retention, and different clocks**.

This memo covers:

- **Where the funnel itself is structured differently**, not just performs differently
- **Why "retention" means two unrelated things** depending on which business you're in
- **Where the money actually leaks or grows**, and how fast
- **A B2B finding that's a little uncomfortable**: the earliest usage signal barely exists

## TL;DR

- **The B2C funnel is spatial (steps in a session); the B2B funnel is temporal (days in a trial).** You can't put them on the same chart without distorting one of them.
- **Retention is measured in two different currencies.** B2C retention = % of *people* who came back. B2B retention = % of *dollars* that stayed — and B2B's version can legitimately exceed 100%.
- **B2C moves in days, B2B moves in months.** A B2C customer either activates within about 3 days or probably never does. A B2B account takes a median of **417 days** to upgrade its plan.

## 1. The "funnel" isn't even the same shape

**B2C checkout funnel (E2)** — five discrete steps inside a single session, minutes apart:

- begin_checkout → add_address → select_shipping → add_payment → purchase
- Drop-off is small and steady early (roughly 1%–4.2% per step), then jumps at the very last step
- Payment → Purchase loses **~8% of sessions on every channel**: organic 7.84%, paid 8.00%, referral 8.30%, email 7.56%, affiliate 8.25%
- The near-identical drop across five very different channels says the friction is in the *payment experience itself*, not who's arriving

**B2B trial funnel (S2)** — no discrete steps at all, just elapsed time:

- One trial per account, tracked against 14-, 30-, and 60-day conversion windows
- Weekly trial cohorts are tiny (1–8 starts per week, about 78% falling in the 2–6 range, 250 trials total across the whole history) — too thin to read as a stable rate
- Conversion swings across the full 0% to 100% range week over week (19 of 85 weeks show 0% 14-day conversion) purely on small-sample noise
- Median time from trial start to paid conversion is **9–14 days** — most conversions that happen, happen fast, but the trial itself is a multi-week waiting window, not a five-click sequence

**Takeaway:** a B2C funnel chart answers "where in the session do we lose people." A B2B funnel chart answers "how long does it take before someone decides," and with volumes this thin, weekly cohorts are the wrong grain — monthly or quarterly would be more honest.

## 2. Retention speaks two different languages

**B2C (E3) — retention is a headcount, measured weekly:**

- % of a signup cohort that performs a meaningful action (view, cart, or purchase) in weeks 1–4
- Week-1 retention ranges **14%–36%** across the cohorts with a fully-observed week-1 window; the newest cohort's week-1 is also 0%, from the same censoring pattern, not a real data point
- It's genuinely non-monotonic: the April 13 cohort goes 25% (w1) → 38% (w2) → 26% (w3) → 36% (w4) — customers skip a week and come back, so later weeks aren't guaranteed to be worse
- Zeros appear increasingly in later weeks starting with the May 18 cohort (week 4 only) and widen for each newer cohort, down to the June 8 cohort showing 0% across all four weeks — a data-window artifact from the pull cutoff, not a behavior collapse

**B2B (S3) — retention is a dollar amount, measured annually:**

- Gross Revenue Retention (GRR) = starting MRR still being paid 12 months later
- Net Revenue Retention (NRR) = GRR plus expansion, minus contraction
- GRR across cohorts ranges **0.00 to 1.00** — the 0.00 is one thin, fully-churned outlier cohort (April 2022, ₹30.72 starting MRR, a single account). Excluding it, GRR runs 0.47–1.00; recent 2025 cohorts (May: 0.47, June: 0.53) are noticeably weaker than the multi-year average
- NRR frequently tops 1.00, reaching **1.85–1.92** in several substantial cohorts and as high as **2.31** in a different thin cohort (March 2022, ₹93.69 starting MRR — not the same April 2022 cohort with GRR 0.00), because expansion revenue from existing accounts outpaces churn
- Important nuance: this GRR counts an account as "fully retained" even if it shrank significantly, as long as it's still paying *something* — contraction only shows up in NRR, not GRR. It reads closer to *logo* retention than a strict dollar-net-of-shrinkage number.

**Takeaway:** in B2C, "retention" is about whether a person shows up again. In B2B, it's about whether the money grows, shrinks, or disappears — and the two aren't interchangeable even when people use the same word for both.

## 3. Where the money actually leaks or grows

**B2C — abandonment inverts with cart size, but dollars don't (E5):**

- Abandonment *rate* falls as cart value rises: 53% for carts under ₹500, down to just 12% for ₹15,000+ carts — bigger spenders are more committed
- But because those big carts are so much larger, they still account for the most money lost: **~65% of all abandoned GMV sits in the ₹5,000–14,999 and ₹15,000+ buckets**
- Reliability, not price incentives, is the higher-leverage fix here — the people abandoning big carts already wanted to buy

**B2B — expansion is slow and comes from one lever (S5):**

- Of ₹14,391 in 6-month expansion MRR, **70% came from plan upgrades** (₹10,065 across 85 accounts), 30% from added seats (₹4,285 across 22 accounts), and addons barely register (₹41, 1 account)
- Median time from signup to a plan upgrade: **417 days**
- Median time from signup to a seat add: **76 days**
- Seats get added quickly and often; plan tier changes take over a year and are the biggest single dollar lever once they happen

**Takeaway:** B2C money is lost in a single session and can be recovered with an infrastructure fix. B2B money is *earned* slowly, over more than a year, concentrated almost entirely in one type of decision.

## 4. The engagement-signal gap

**B2C (E4) has abundant usage signal by default:**

- Nearly 4,000 products carry real page-view and add-to-cart traffic
- Enough volume exists to benchmark every product against its own category's median add-to-cart rate — a meaningful comparison

**B2B (S4) barely has any signal in the first two weeks:**

- Primary definition: adopted a feature ≥3 times in the first 14 days
- Result: **zero adopters, for every one of 50 features, across all 1,193 eligible accounts**
- Dropping the bar to using a feature even once in 14 days (a separate sensitivity check, not a replacement metric) still only surfaces a thin signal — the top feature, API Bulk Operations, has just 21 adopters out of 1,193 accounts (under 2%), though it does show the strongest retention lift (+24.4pp)
- This isn't a broken query — the denominators reconcile exactly, and it's the same 1,193 accounts every time

**Takeaway:** every website visit is a data point by default; B2B feature usage has to be earned, and in this account base, early usage just isn't happening yet. That's a product-onboarding finding as much as a data finding.

## 5. Speed: days vs. months

- **B2C activation (E1):** among users who activate at all, the median time to a first meaningful action ranges roughly 1.9–3.2 days (2,732–4,615 minutes) across cohorts. 7-day activation rates across cohorts run **9%–22%** — if it's going to happen, it happens fast.
- **B2B revenue motion (S1, S5):** MRR is tracked on a rolling 12-month waterfall, and the single biggest expansion lever (plan upgrades) takes a median of **417 days** to fire.
- Same underlying question — "did this account do the valuable thing" — but the B2C clock runs in days and the B2B clock runs in quarters.

## At a glance

| Dimension | B2C (ecom) | B2B (saas) |
|---|---|---|
| Funnel shape | 5 steps within one session | Time windows (14/30/60-day) |
| Retention unit | % of people active | % of MRR retained |
| Retention cadence | Weekly | 12-month cohort |
| Biggest $ leak/lever | High-value cart abandonment | Plan-upgrade expansion |
| Time to key event | ~2–3 days (activation) | ~417 days (plan upgrade) |
| Usage signal density | High (every visit = data) | Low (0 adopters at required threshold) |

## What I'd investigate next

- **B2C:** Pull session recordings or error logs for the Payment → Purchase step — an ~8% loss that's identical across five channels smells like a gateway or UX issue, not a targeting one.
- **B2B:** Re-run S2 and S4 at monthly (not weekly) grain — current weekly cohorts are too thin (1–8 trials/week, ~78% in the 2–6 range) to trust individual rates, and the N=3 feature-adoption bar may simply be too strict for this account base's actual usage pattern.
- **Both:** Layer acquisition/onboarding cost against each business's own "speed to value" — a 3-day B2C activation window and a 417-day B2B expansion window imply very different payback math and shouldn't be judged on the same timeline.

## Methodology note

- **Sources:** internal Postgres warehouse, `ecom` and `saas` schemas, via Metabase.
- **Queries used:** E1 (activation), E2 (checkout funnel), E3 (weekly cohort retention), E4 (PDP engagement), E5 (cart abandonment by value) · S1 (MRR decomposition), S2 (trial-to-paid conversion), S3 (GRR/NRR by cohort), S4 (feature adoption vs. retention, N=3 primary + N=1 sensitivity), S5 (expansion revenue by type).
- Every rate in this memo was independently recomputed from the raw query output (not just read off the header comments) — funnel monotonicity, cohort-size reconciliation, and the S1 MRR waterfall all check out exactly.
- **Caveat on B2C rate columns:** exported CSV rates are rounded to 2 decimals even where the SQL computes 4 — e.g. a reported "0.25" week-1 retention rate is actually 0.2481. Immaterial for this memo's conclusions, but worth knowing if a number here needs to be defended to a third decimal.
- **Caveat on S3 GRR:** as coded, it does not net out contraction from "retained" MRR — it counts an account as retained at full value as long as it's still paying anything. Treat it as logo-weighted, not a strict revenue-net-of-shrinkage GRR.
- **Caveat on S4:** the zero-adopter result at N=3 is a genuine finding, not a query defect — denominators reconcile exactly to 1,193 eligible accounts every time. The N=1 view is a sensitivity check, not a replacement metric.
- **Caveat on S5:** it filters on `current_date - interval '6 months'`, not a fixed date literal like S1's hardcoded `2026-06-15`. The exact reconciliation to S1 cited above only holds because both were run around the same point in time — re-running S5 later shifts its window and the totals will no longer match to the cent unless it's pinned to a fixed date.
