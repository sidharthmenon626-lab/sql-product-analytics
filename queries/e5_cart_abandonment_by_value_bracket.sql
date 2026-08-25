/*
===============================================================================
E5 – Cart Abandonment by Cart Value Bucket
===============================================================================

Business Question
-----------------
"Cart abandonment is 70% overall — but is it the same for ₹500 carts as
₹15,000 carts? Where do we lose the most rupees?"

Business Logic
--------------
• Cart value is calculated as the sum of (quantity × unit_price) across all
  add_to_cart events within a session.

• Each session belongs to exactly one cart value bucket:

      <₹500
      ₹500–₹1,999
      ₹2,000–₹4,999
      ₹5,000–₹14,999
      ₹15,000+

• A purchased session is defined as a session linked to an order with
  payment_status = 'paid'.

• An abandoned session is a cart session with no matching paid order.

Output Columns
--------------
cart_bucket
atc_sessions
purchased_sessions
abandoned_sessions
abandonment_rate
gmv_left_on_table

Design Notes
------------
• The query is intentionally built at the session grain.

• cart_sessions creates one row per session containing total cart value.

• purchase_sessions identifies sessions that resulted in successful purchases.

• session_metrics joins both datasets and derives:
      - purchased flag
      - cart bucket

• Final aggregation is performed only after every session has been assigned
  exactly one bucket.

Sanity Check
------------
Run separately:

    select count(*)
    from cart_sessions;

Expected Result:
The count must equal the sum of atc_sessions across all cart buckets.

Verification
------------
Total ATC Sessions (Unsegmented) = 19,862

Bucket Totals
-------------
<₹500              1,288
₹500–₹1,999        4,975
₹2,000–₹4,999      5,595
₹5,000–₹14,999     5,879
₹15,000+           2,125
--------------------------------
Total             19,862

PASS ✓

PM Action
---------
If abandoned GMV is concentrated in the highest-value buckets,
prioritize checkout reliability improvements.

If abandoned GMV is concentrated in the lowest-value bucket,
prioritize free-shipping thresholds and pricing incentives.

Result for this dataset:
Approximately 65% of abandoned GMV comes from the
₹5,000–₹14,999 and ₹15,000+ buckets.

Recommended Priority:
Improve checkout reliability before pricing incentives.
===============================================================================
*/

with cart_sessions as
(
    select
        session_id
      , sum(quantity * unit_price) as cart_value
    from
        ecom.session_events
    where
        event_type = 'add_to_cart'
    group by
        session_id
)

, purchase_sessions as
(
    select distinct
        s.session_id
    from
        ecom.sessions s
    inner join
        ecom.orders o
        on s.session_id = o.session_id
    where
        o.payment_status = 'paid'
)

, session_metrics as
(
    select
        cs.session_id
      , cs.cart_value
      , case
            when ps.session_id is not null then true
            else false
        end as purchased
      , case
            when cs.cart_value < 500 then '<₹500'
            when cs.cart_value between 500 and 1999 then '₹500–₹1,999'
            when cs.cart_value between 2000 and 4999 then '₹2,000–₹4,999'
            when cs.cart_value between 5000 and 14999 then '₹5,000–₹14,999'
            else '₹15,000+'
        end as cart_bucket
    from
        cart_sessions cs
    left join
        purchase_sessions ps
        on cs.session_id = ps.session_id
)

select
    cart_bucket
  , count(*) as atc_sessions
  , count(*) filter (where purchased) as purchased_sessions
  , count(*) filter (where not purchased) as abandoned_sessions
  , round(
        count(*) filter (where not purchased)::numeric
        / nullif(count(*), 0),
        4
    ) as abandonment_rate
  , sum(
        case
            when not purchased then cart_value
            else 0
        end
    ) as gmv_left_on_table
from
    session_metrics
group by
    cart_bucket
order by
    case
        when cart_bucket = '<₹500' then 1
        when cart_bucket = '₹500–₹1,999' then 2
        when cart_bucket = '₹2,000–₹4,999' then 3
        when cart_bucket = '₹5,000–₹14,999' then 4
        when cart_bucket = '₹15,000+' then 5
    end;
