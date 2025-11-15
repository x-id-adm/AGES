-- =================================================================================================
-- BILLING METRICS FUNCTIONS
-- =================================================================================================
-- DESCRIPTION:
--   Functions to query billing filtered by time period.
--   Allows queries like: "How much was billed today?"
--                        "How much was billed in the last 7 days?"
--                        "How much was billed in January?"
--
-- IMPORTANT:
--   - Only appointments with status 'Completed' are considered in billing
--   - Values are filtered by 'completed_at' timestamp (when marked as completed)
--   - Values in cents (divide by 100 to get currency value)
--   - Currency-agnostic: works with any currency (USD, BRL, EUR, etc.)
--
-- VERSION: 1.0
-- DATE: 2025-11-15
-- =================================================================================================


-- =================================================================================================
-- MAIN FUNCTION: Billing by Period
-- =================================================================================================

-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNCTION: get_billing_by_period                                                             │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PURPOSE:                                                                                    │
-- │   Returns total and detailed billing for a specific time period.                            │
-- │                                                                                             │
-- │ PARAMETERS:                                                                                 │
-- │   p_inbox_id (UUID) - Inbox ID to filter                                                    │
-- │   p_start_date (TIMESTAMPTZ) - Start date/time of period (inclusive)                        │
-- │   p_end_date (TIMESTAMPTZ) - End date/time of period (exclusive)                            │
-- │                                                                                             │
-- │ RETURN:                                                                                     │
-- │   JSONB with structure:                                                                     │
-- │   {                                                                                         │
-- │     "total_billing_cents": 45000,        // Total in cents                                  │
-- │     "total_billing_currency": 450.00,    // Total in currency units (generic)               │
-- │     "completed_count": 15,               // Number of completed appointments                 │
-- │     "average_ticket_cents": 3000,        // Average ticket in cents                          │
-- │     "average_ticket_currency": 30.00,    // Average ticket in currency units                 │
-- │     "period": {                                                                             │
-- │       "start": "2025-01-01T00:00:00Z",                                                      │
-- │       "end": "2025-02-01T00:00:00Z"                                                         │
-- │     }                                                                                       │
-- │   }                                                                                         │
-- │                                                                                             │
-- │ LOGIC:                                                                                      │
-- │   Sums all value_cents from appointments with status 'Completed' that were                  │
-- │   completed (completed_at) within the specified period.                                     │
-- │                                                                                             │
-- │ USAGE EXAMPLE:                                                                              │
-- │   -- Billing from last 7 days                                                               │
-- │   SELECT get_billing_by_period(                                                             │
-- │       'inbox-uuid',                                                                         │
-- │       NOW() - INTERVAL '7 days',                                                            │
-- │       NOW()                                                                                 │
-- │   );                                                                                        │
-- │                                                                                             │
-- │   -- Billing from January 2025                                                              │
-- │   SELECT get_billing_by_period(                                                             │
-- │       'inbox-uuid',                                                                         │
-- │       '2025-01-01 00:00:00'::TIMESTAMPTZ,                                                   │
-- │       '2025-02-01 00:00:00'::TIMESTAMPTZ                                                    │
-- │   );                                                                                        │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION get_billing_by_period(
    p_inbox_id UUID,
    p_start_date TIMESTAMPTZ,
    p_end_date TIMESTAMPTZ
)
RETURNS JSONB AS $$
DECLARE
    v_total_cents BIGINT;
    v_completed_count INT;
    v_avg_ticket_cents BIGINT;
    v_result JSONB;
BEGIN
    -- Calculate total billing and completed appointments count
    SELECT
        COALESCE(SUM(value_cents), 0),
        COUNT(*)
    INTO v_total_cents, v_completed_count
    FROM "4a_customer_service_history"
    WHERE inbox_id = p_inbox_id
      AND service_status = 'Completed'
      AND completed_at >= p_start_date
      AND completed_at < p_end_date
      AND value_cents IS NOT NULL
      AND value_cents > 0;

    -- Calculate average ticket
    IF v_completed_count > 0 THEN
        v_avg_ticket_cents := v_total_cents / v_completed_count;
    ELSE
        v_avg_ticket_cents := 0;
    END IF;

    -- Build JSON result
    v_result := jsonb_build_object(
        'total_billing_cents', v_total_cents,
        'total_billing_currency', ROUND(v_total_cents::NUMERIC / 100, 2),
        'completed_count', v_completed_count,
        'average_ticket_cents', v_avg_ticket_cents,
        'average_ticket_currency', ROUND(v_avg_ticket_cents::NUMERIC / 100, 2),
        'period', jsonb_build_object(
            'start', p_start_date,
            'end', p_end_date
        )
    );

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;


-- =================================================================================================
-- CONVENIENCE FUNCTIONS: Common Periods
-- =================================================================================================

-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNCTION: get_billing_today                                                                 │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PURPOSE:                                                                                    │
-- │   Returns billing from current day (from 00:00:00 until now).                               │
-- │                                                                                             │
-- │ USAGE EXAMPLE:                                                                              │
-- │   SELECT get_billing_today('inbox-uuid');                                                   │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION get_billing_today(
    p_inbox_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_today_start TIMESTAMPTZ;
BEGIN
    -- Start of today (00:00:00)
    v_today_start := date_trunc('day', NOW());

    RETURN get_billing_by_period(
        p_inbox_id,
        v_today_start,
        NOW()
    );
END;
$$ LANGUAGE plpgsql;


-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNCTION: get_billing_last_n_days                                                           │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PURPOSE:                                                                                    │
-- │   Returns billing from last N days.                                                         │
-- │                                                                                             │
-- │ USAGE EXAMPLE:                                                                              │
-- │   -- Last 7 days                                                                            │
-- │   SELECT get_billing_last_n_days('inbox-uuid', 7);                                          │
-- │                                                                                             │
-- │   -- Last 30 days                                                                           │
-- │   SELECT get_billing_last_n_days('inbox-uuid', 30);                                         │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION get_billing_last_n_days(
    p_inbox_id UUID,
    p_days INT
)
RETURNS JSONB AS $$
BEGIN
    RETURN get_billing_by_period(
        p_inbox_id,
        NOW() - (p_days || ' days')::INTERVAL,
        NOW()
    );
END;
$$ LANGUAGE plpgsql;


-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNCTION: get_billing_specific_month                                                        │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PURPOSE:                                                                                    │
-- │   Returns billing from a specific month.                                                    │
-- │                                                                                             │
-- │ PARAMETERS:                                                                                 │
-- │   p_inbox_id (UUID) - Inbox ID                                                              │
-- │   p_year (INT) - Year (e.g. 2025)                                                           │
-- │   p_month (INT) - Month (1-12)                                                              │
-- │                                                                                             │
-- │ USAGE EXAMPLE:                                                                              │
-- │   -- January 2025                                                                           │
-- │   SELECT get_billing_specific_month('inbox-uuid', 2025, 1);                                 │
-- │                                                                                             │
-- │   -- December 2024                                                                          │
-- │   SELECT get_billing_specific_month('inbox-uuid', 2024, 12);                                │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION get_billing_specific_month(
    p_inbox_id UUID,
    p_year INT,
    p_month INT
)
RETURNS JSONB AS $$
DECLARE
    v_start_date TIMESTAMPTZ;
    v_end_date TIMESTAMPTZ;
BEGIN
    -- Month validation
    IF p_month < 1 OR p_month > 12 THEN
        RAISE EXCEPTION 'Invalid month: %. Must be between 1 and 12.', p_month;
    END IF;

    -- First day of month at 00:00:00
    v_start_date := make_timestamptz(p_year, p_month, 1, 0, 0, 0);

    -- First day of next month at 00:00:00
    v_end_date := v_start_date + INTERVAL '1 month';

    RETURN get_billing_by_period(
        p_inbox_id,
        v_start_date,
        v_end_date
    );
END;
$$ LANGUAGE plpgsql;


-- =================================================================================================
-- LTV (LIFETIME VALUE) FUNCTIONS PER CUSTOMER
-- =================================================================================================

-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNCTION: get_customer_ltv                                                                  │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PURPOSE:                                                                                    │
-- │   Returns the LTV (Lifetime Value) of a specific customer.                                  │
-- │                                                                                             │
-- │ PARAMETERS:                                                                                 │
-- │   p_root_id (BIGINT) - Customer record ID (3a_customer_root_record)                         │
-- │                                                                                             │
-- │ RETURN:                                                                                     │
-- │   JSONB with structure:                                                                     │
-- │   {                                                                                         │
-- │     "root_id": 123,                                                                         │
-- │     "client_id": "CT456",                                                                   │
-- │     "treatment_name": "John Doe",                                                           │
-- │     "total_spent_cents": 60000,          // Total spent in cents                            │
-- │     "total_spent_currency": 600.00,      // Total spent in currency units                   │
-- │     "total_completed_appointments": 3,                                                      │
-- │     "average_ticket_cents": 20000,       // Average ticket in cents                          │
-- │     "average_ticket_currency": 200.00,   // Average ticket in currency units                 │
-- │     "first_purchase_at": "2025-01-15T10:00:00Z",                                            │
-- │     "last_purchase_at": "2025-11-10T14:30:00Z",                                             │
-- │     "customer_lifetime_days": 299        // Days since first purchase                        │
-- │   }                                                                                         │
-- │                                                                                             │
-- │ USAGE EXAMPLE:                                                                              │
-- │   SELECT get_customer_ltv(123);                                                             │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION get_customer_ltv(
    p_root_id BIGINT
)
RETURNS JSONB AS $$
DECLARE
    v_result JSONB;
BEGIN
    -- Fetch customer data
    SELECT
        jsonb_build_object(
            'root_id', cr.id,
            'client_id', cr.client_id,
            'treatment_name', cr.treatment_name,
            'total_spent_cents', cr.total_spent_cents,
            'total_spent_currency', ROUND(cr.total_spent_cents::NUMERIC / 100, 2),
            'total_completed_appointments', cr.total_completed_appointments,
            'average_ticket_cents', CASE
                WHEN cr.total_completed_appointments > 0
                THEN cr.total_spent_cents / cr.total_completed_appointments
                ELSE 0
            END,
            'average_ticket_currency', CASE
                WHEN cr.total_completed_appointments > 0
                THEN ROUND((cr.total_spent_cents::NUMERIC / cr.total_completed_appointments) / 100, 2)
                ELSE 0
            END,
            'first_purchase_at', cr.first_purchase_at,
            'last_purchase_at', cr.last_purchase_at,
            'customer_lifetime_days', CASE
                WHEN cr.first_purchase_at IS NOT NULL
                THEN EXTRACT(DAY FROM (COALESCE(cr.last_purchase_at, NOW()) - cr.first_purchase_at))::INT
                ELSE 0
            END
        )
    INTO v_result
    FROM "3a_customer_root_record" cr
    WHERE cr.id = p_root_id;

    -- If customer not found
    IF v_result IS NULL THEN
        RAISE EXCEPTION 'Customer with root_id % not found', p_root_id;
    END IF;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;


-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNCTION: get_top_customers_by_ltv                                                          │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PURPOSE:                                                                                    │
-- │   Returns top N customers ordered by LTV (highest to lowest).                               │
-- │                                                                                             │
-- │ PARAMETERS:                                                                                 │
-- │   p_inbox_id (UUID) - Inbox ID to filter                                                    │
-- │   p_limit (INT) - Number of customers to return (default: 10)                               │
-- │                                                                                             │
-- │ RETURN:                                                                                     │
-- │   JSONB array with top customers ordered by total_spent_cents                               │
-- │                                                                                             │
-- │ USAGE EXAMPLE:                                                                              │
-- │   -- Top 10 customers                                                                       │
-- │   SELECT get_top_customers_by_ltv('inbox-uuid', 10);                                        │
-- │                                                                                             │
-- │   -- Top 50 customers                                                                       │
-- │   SELECT get_top_customers_by_ltv('inbox-uuid', 50);                                        │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION get_top_customers_by_ltv(
    p_inbox_id UUID,
    p_limit INT DEFAULT 10
)
RETURNS JSONB AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_agg(customer_data)
    INTO v_result
    FROM (
        SELECT jsonb_build_object(
            'root_id', cr.id,
            'client_id', cr.client_id,
            'treatment_name', cr.treatment_name,
            'total_spent_cents', cr.total_spent_cents,
            'total_spent_currency', ROUND(cr.total_spent_cents::NUMERIC / 100, 2),
            'total_completed_appointments', cr.total_completed_appointments,
            'average_ticket_cents', CASE
                WHEN cr.total_completed_appointments > 0
                THEN cr.total_spent_cents / cr.total_completed_appointments
                ELSE 0
            END,
            'average_ticket_currency', CASE
                WHEN cr.total_completed_appointments > 0
                THEN ROUND((cr.total_spent_cents::NUMERIC / cr.total_completed_appointments) / 100, 2)
                ELSE 0
            END,
            'last_purchase_at', cr.last_purchase_at
        ) as customer_data
        FROM "3a_customer_root_record" cr
        WHERE cr.inbox_id = p_inbox_id
          AND cr.total_spent_cents > 0
        ORDER BY cr.total_spent_cents DESC
        LIMIT p_limit
    ) top_customers;

    RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql;


-- =================================================================================================
-- CONVENIENCE VIEW: Consolidated Customer Billing Summary
-- =================================================================================================

-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ VIEW: vw_customer_billing_summary                                                           │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PURPOSE:                                                                                    │
-- │   View showing consolidated billing summary per customer.                                   │
-- │                                                                                             │
-- │ COLUMNS:                                                                                    │
-- │   • root_id, client_id, treatment_name                                                      │
-- │   • total_spent_cents, total_spent_currency                                                 │
-- │   • total_completed_appointments                                                            │
-- │   • average_ticket_cents, average_ticket_currency                                           │
-- │   • first_purchase_at, last_purchase_at                                                     │
-- │   • customer_lifetime_days                                                                  │
-- │                                                                                             │
-- │ USAGE EXAMPLE:                                                                              │
-- │   -- View all customers ordered by LTV                                                      │
-- │   SELECT * FROM vw_customer_billing_summary                                                 │
-- │   ORDER BY total_spent_cents DESC                                                           │
-- │   LIMIT 20;                                                                                 │
-- │                                                                                             │
-- │   -- View customers who spent more than 100000 cents (1000 currency units)                  │
-- │   SELECT * FROM vw_customer_billing_summary                                                 │
-- │   WHERE total_spent_currency > 1000                                                         │
-- │   ORDER BY total_spent_cents DESC;                                                          │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE VIEW vw_customer_billing_summary AS
SELECT
    cr.id as root_id,
    cr.client_id,
    cr.inbox_id,
    cr.treatment_name,
    cr.total_spent_cents,
    ROUND(cr.total_spent_cents::NUMERIC / 100, 2) as total_spent_currency,
    cr.total_completed_appointments,
    CASE
        WHEN cr.total_completed_appointments > 0
        THEN cr.total_spent_cents / cr.total_completed_appointments
        ELSE 0
    END as average_ticket_cents,
    CASE
        WHEN cr.total_completed_appointments > 0
        THEN ROUND((cr.total_spent_cents::NUMERIC / cr.total_completed_appointments) / 100, 2)
        ELSE 0
    END as average_ticket_currency,
    cr.first_purchase_at,
    cr.last_purchase_at,
    CASE
        WHEN cr.first_purchase_at IS NOT NULL
        THEN EXTRACT(DAY FROM (COALESCE(cr.last_purchase_at, NOW()) - cr.first_purchase_at))::INT
        ELSE 0
    END as customer_lifetime_days,
    cr.created_at,
    cr.updated_at
FROM "3a_customer_root_record" cr
WHERE cr.total_spent_cents > 0
ORDER BY cr.total_spent_cents DESC;


-- =================================================================================================
-- END OF FUNCTIONS
-- =================================================================================================
-- To test the functions:
--
-- BILLING BY TIME:
--   SELECT get_billing_today('your-inbox-uuid');
--   SELECT get_billing_last_n_days('your-inbox-uuid', 7);
--   SELECT get_billing_last_n_days('your-inbox-uuid', 30);
--   SELECT get_billing_specific_month('your-inbox-uuid', 2025, 1);
--
-- LTV PER CUSTOMER:
--   SELECT get_customer_ltv(123);
--   SELECT get_top_customers_by_ltv('your-inbox-uuid', 10);
--   SELECT * FROM vw_customer_billing_summary LIMIT 20;
-- =================================================================================================
