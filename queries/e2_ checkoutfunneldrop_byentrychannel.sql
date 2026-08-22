/*
===============================================================================
Query E2 - Checkout Funnel Drop-off by Entry Channel
===============================================================================

Business Question
-----------------
Where is checkout leaking, and is the leak the same across paid social vs
organic search?

Funnel
------
begin_checkout
    → add_address
    → select_shipping
    → add_payment
    → purchase

Grain
-----
One row per acquisition channel.

Output
------
channel,
begin_checkout,
address,
shipping,
payment,
purchased,
drop_address_pct,
drop_shipping_pct,
drop_payment_pct,
drop_final_pct

Business Interpretation
-----------------------
The largest drop-off occurs consistently between the Payment and Purchase
steps (~8%) across every acquisition channel, while earlier checkout stages
experience relatively small losses (approximately 1–4%).

Because this pattern is consistent across Organic Search, Paid Social,
Referral, Email, and Affiliate traffic, the primary friction appears to be
within the payment completion experience rather than being driven by a
specific acquisition channel.

PM Recommendation
-----------------
Highest Drop-off Stage:
Payment → Purchase

Recommended next sprint investigation:

• Review session recordings for users abandoning after reaching payment.
• Analyze payment gateway failure logs and error codes.
• Compare abandonment by payment method (Card, UPI, Wallet, etc.).
• Check whether taxes, shipping charges, or other fees are introduced only
  at the final payment step.
• Segment abandonment by device, browser, and geography to identify any
  platform-specific issues.

Sanity Checks Performed
-----------------------

1. Funnel Monotonicity

   Verified that:

   begin_checkout >= address >= shipping >= payment >= purchased

   Result:
   ✓ Passed.

2. Drop-off Percentage Validation

   Confirmed that every calculated drop-off percentage falls within the
   valid range of 0%–100%.

   Result:
   ✓ Passed.

3. Purchase Validation

   Verified that the total purchased sessions equal the number of sessions
   whose max_step = 5.

   Validation Query:

   select
       count(*)
   from session_step_reached
   where max_step = 5;

   Result:
   ✓ Passed.

4. Manual Arithmetic Validation

   Spot-checked percentage calculations.

   Example (Organic):

   ((6374 - 6160) / 6374) * 100 = 3.36%

   Result:
   ✓ Matches query output.

Design Note
-----------
This solution assigns each session its furthest completed checkout stage
using MAX(step_number) instead of independently checking whether a session
contains every funnel event.

Using MAX(step_number) guarantees a monotonic funnel where later-stage
counts can never exceed earlier-stage counts, even if intermediate events
are missing due to instrumentation issues. This produces reliable funnel
metrics suitable for product analytics and prevents impossible conversion
rates.

===============================================================================
*/


with session_step_reached as
(
    select
        s.session_id,
        sc.channel,
        max(
            case
                when se.event_type = 'purchase' then 5
                when se.event_type = 'add_payment' then 4
                when se.event_type = 'select_shipping' then 3
                when se.event_type = 'add_address' then 2
                when se.event_type = 'begin_checkout' then 1
                else 0
            end
        ) as max_step

    from ecom.sessions s

    join ecom.session_channels sc
        on s.session_id = sc.session_id

    join ecom.session_events se
        on s.session_id = se.session_id

    group by
        s.session_id,
        sc.channel
),

funnel_counts as
(
    select
        channel,
        count(*) filter (where max_step >= 1) as begin_checkout,
        count(*) filter (where max_step >= 2) as address,
        count(*) filter (where max_step >= 3) as shipping,
        count(*) filter (where max_step >= 4) as payment,
        count(*) filter (where max_step >= 5) as purchased

    from session_step_reached

    where max_step >= 1

    group by
        channel
),

funnel_metrics as
(
    select
        channel,
        begin_checkout,
        address,
        shipping,
        payment,
        purchased,

        round(
            100.0 * (begin_checkout - address)
            / nullif(begin_checkout, 0),
            2
        ) as drop_address_pct,

        round(
            100.0 * (address - shipping)
            / nullif(address, 0),
            2
        ) as drop_shipping_pct,

        round(
            100.0 * (shipping - payment)
            / nullif(shipping, 0),
            2
        ) as drop_payment_pct,

        round(
            100.0 * (payment - purchased)
            / nullif(payment, 0),
            2
        ) as drop_final_pct

    from funnel_counts
)

select
    channel,
    begin_checkout,
    address,
    shipping,
    payment,
    purchased,
    drop_address_pct,
    drop_shipping_pct,
    drop_payment_pct,
    drop_final_pct

from funnel_metrics

order by
    begin_checkout desc;