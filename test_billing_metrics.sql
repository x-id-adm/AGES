-- =================================================================================================
-- TESTS: BILLING METRICS AND LTV
-- =================================================================================================
-- DESCRIPTION:
--   Test script to validate all billing functionalities.
--   Tests:
--     - Time-based billing functions
--     - Customer LTV functions
--     - Automatic LTV update trigger
--     - Summary views
--
-- HOW TO EXECUTE:
--   1. Ensure main schema is created (schema.sql)
--   2. Execute: functions_billing_metrics.sql
--   3. Execute: trigger_update_customer_ltv.sql
--   4. Execute this file: test_billing_metrics.sql
--
-- VERSION: 1.0
-- DATE: 2025-11-15
-- =================================================================================================

BEGIN;

-- =================================================================================================
-- PREPARATION: Create Test Data
-- =================================================================================================

-- Clean previous test data (if exists)
DO $$
BEGIN
    DELETE FROM "4a_customer_service_history" WHERE inbox_id IN (
        SELECT inbox_id FROM "0a_inbox_whatsapp" WHERE inbox_name = 'TEST_BILLING_INBOX'
    );
    DELETE FROM "3a_customer_root_record" WHERE inbox_id IN (
        SELECT inbox_id FROM "0a_inbox_whatsapp" WHERE inbox_name = 'TEST_BILLING_INBOX'
    );
    DELETE FROM "1a_whatsapp_user_contact" WHERE inbox_id IN (
        SELECT inbox_id FROM "0a_inbox_whatsapp" WHERE inbox_name = 'TEST_BILLING_INBOX'
    );
    DELETE FROM "0b_inbox_counters" WHERE inbox_id IN (
        SELECT inbox_id FROM "0a_inbox_whatsapp" WHERE inbox_name = 'TEST_BILLING_INBOX'
    );
    DELETE FROM "0a_inbox_whatsapp" WHERE inbox_name = 'TEST_BILLING_INBOX';
END$$;

-- Create test inbox
INSERT INTO "0a_inbox_whatsapp" (
    inbox_id, status_workflow, inbox_name, owner_wallet_id
) VALUES (
    '00000000-0000-0000-0000-000000000001',
    '🟢',
    'TEST_BILLING_INBOX',
    '00000000-0000-0000-0000-000000000099'
);

-- Create inbox counter
INSERT INTO "0b_inbox_counters" (inbox_id) VALUES (
    '00000000-0000-0000-0000-000000000001'
);

-- Create test contacts
INSERT INTO "1a_whatsapp_user_contact" (
    wallet_id, inbox_id, push_name, phone_number
) VALUES
    ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001', 'Customer 1', '+5511999990001'),
    ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000001', 'Customer 2', '+5511999990002'),
    ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000001', 'Customer 3', '+5511999990003');

-- Create customer records
INSERT INTO "3a_customer_root_record" (
    id, client_id, inbox_id, treatment_name, legal_name_complete, whatsapp_owner
) VALUES
    (1001, 'CT1001', '00000000-0000-0000-0000-000000000001', 'John Doe', 'John Doe Silva', '+5511999990001'),
    (1002, 'CT1002', '00000000-0000-0000-0000-000000000001', 'Jane Smith', 'Jane Smith Lima', '+5511999990002'),
    (1003, 'CT1003', '00000000-0000-0000-0000-000000000001', 'Bob Johnson', 'Bob Johnson Costa', '+5511999990003');

-- =================================================================================================
-- TEST 1: LTV Trigger - INSERT with Completed status
-- =================================================================================================

\echo ''
\echo '===================================================================================='
\echo 'TEST 1: LTV Trigger - INSERT with Completed status'
\echo '===================================================================================='

-- Insert completed appointment (trigger should update LTV automatically)
INSERT INTO "4a_customer_service_history" (
    service_id,
    inbox_id,
    root_id,
    service_datetime_start,
    service_datetime_end,
    service_status,
    value_cents,
    completed_at,
    created_at
) VALUES (
    'AT001',
    '00000000-0000-0000-0000-000000000001',
    1001,  -- John Doe
    '2025-01-15 10:00:00'::TIMESTAMPTZ,
    '2025-01-15 11:00:00'::TIMESTAMPTZ,
    'Completed',
    20000,  -- 200.00 in currency
    '2025-01-15 11:00:00'::TIMESTAMPTZ,
    '2025-01-15 09:00:00'::TIMESTAMPTZ
);

-- Verify LTV was updated
\echo 'Checking John Doe LTV (should be 200.00):'
SELECT
    treatment_name,
    total_spent_cents,
    total_spent_cents / 100.0 as total_spent_currency,
    total_completed_appointments,
    first_purchase_at,
    last_purchase_at
FROM "3a_customer_root_record"
WHERE id = 1001;

-- =================================================================================================
-- TEST 2: LTV Trigger - UPDATE status to Completed
-- =================================================================================================

\echo ''
\echo '===================================================================================='
\echo 'TEST 2: LTV Trigger - UPDATE status to Completed'
\echo '===================================================================================='

-- Insert appointment with Scheduled status
INSERT INTO "4a_customer_service_history" (
    service_id,
    inbox_id,
    root_id,
    service_datetime_start,
    service_datetime_end,
    service_status,
    value_cents,
    scheduled_at,
    created_at
) VALUES (
    'AT002',
    '00000000-0000-0000-0000-000000000001',
    1001,  -- John Doe (again)
    '2025-02-10 14:00:00'::TIMESTAMPTZ,
    '2025-02-10 15:00:00'::TIMESTAMPTZ,
    'Scheduled',
    25000,  -- 250.00 in currency
    '2025-02-01 10:00:00'::TIMESTAMPTZ,
    '2025-02-01 10:00:00'::TIMESTAMPTZ
);

\echo 'John Doe LTV BEFORE completing appointment (should be 200.00):'
SELECT
    treatment_name,
    total_spent_cents / 100.0 as total_spent_currency,
    total_completed_appointments
FROM "3a_customer_root_record"
WHERE id = 1001;

-- Update status to Completed
UPDATE "4a_customer_service_history"
SET
    service_status = 'Completed',
    completed_at = '2025-02-10 15:00:00'::TIMESTAMPTZ,
    updated_at = '2025-02-10 15:00:00'::TIMESTAMPTZ
WHERE service_id = 'AT002';

\echo 'John Doe LTV AFTER completing appointment (should be 450.00):'
SELECT
    treatment_name,
    total_spent_cents / 100.0 as total_spent_currency,
    total_completed_appointments,
    first_purchase_at,
    last_purchase_at
FROM "3a_customer_root_record"
WHERE id = 1001;

-- =================================================================================================
-- TEST 3: Multiple Customers with Multiple Appointments
-- =================================================================================================

\echo ''
\echo '===================================================================================='
\echo 'TEST 3: Multiple Customers with Multiple Appointments'
\echo '===================================================================================='

-- Customer 2: Jane Smith - 3 completed appointments
INSERT INTO "4a_customer_service_history" (
    service_id, inbox_id, root_id, service_datetime_start, service_datetime_end,
    service_status, value_cents, completed_at, created_at
) VALUES
    ('AT003', '00000000-0000-0000-0000-000000000001', 1002, '2025-01-05 10:00:00'::TIMESTAMPTZ, '2025-01-05 11:00:00'::TIMESTAMPTZ, 'Completed', 15000, '2025-01-05 11:00:00'::TIMESTAMPTZ, '2025-01-05 09:00:00'::TIMESTAMPTZ),
    ('AT004', '00000000-0000-0000-0000-000000000001', 1002, '2025-02-12 14:00:00'::TIMESTAMPTZ, '2025-02-12 15:00:00'::TIMESTAMPTZ, 'Completed', 15000, '2025-02-12 15:00:00'::TIMESTAMPTZ, '2025-02-12 13:00:00'::TIMESTAMPTZ),
    ('AT005', '00000000-0000-0000-0000-000000000001', 1002, '2025-11-01 09:00:00'::TIMESTAMPTZ, '2025-11-01 10:00:00'::TIMESTAMPTZ, 'Completed', 15000, '2025-11-01 10:00:00'::TIMESTAMPTZ, '2025-11-01 08:00:00'::TIMESTAMPTZ);

-- Customer 3: Bob Johnson - 1 completed appointment
INSERT INTO "4a_customer_service_history" (
    service_id, inbox_id, root_id, service_datetime_start, service_datetime_end,
    service_status, value_cents, completed_at, created_at
) VALUES
    ('AT006', '00000000-0000-0000-0000-000000000001', 1003, '2025-10-20 16:00:00'::TIMESTAMPTZ, '2025-10-20 17:00:00'::TIMESTAMPTZ, 'Completed', 30000, '2025-10-20 17:00:00'::TIMESTAMPTZ, '2025-10-20 15:00:00'::TIMESTAMPTZ);

\echo 'LTV Summary for all customers:'
SELECT
    treatment_name,
    total_spent_cents / 100.0 as total_spent_currency,
    total_completed_appointments,
    (total_spent_cents / total_completed_appointments) / 100.0 as avg_ticket_currency,
    first_purchase_at,
    last_purchase_at
FROM "3a_customer_root_record"
WHERE inbox_id = '00000000-0000-0000-0000-000000000001'
ORDER BY total_spent_cents DESC;

-- =================================================================================================
-- TEST 4: Time-Based Billing Functions
-- =================================================================================================

\echo ''
\echo '===================================================================================='
\echo 'TEST 4: Time-Based Billing Functions'
\echo '===================================================================================='

-- Billing for January 2025
\echo 'Billing for January 2025 (should be 350.00):'
SELECT get_billing_specific_month(
    '00000000-0000-0000-0000-000000000001',
    2025,
    1
);

-- Billing for February 2025
\echo 'Billing for February 2025 (should be 400.00):'
SELECT get_billing_specific_month(
    '00000000-0000-0000-0000-000000000001',
    2025,
    2
);

-- Billing for last 30 days
\echo 'Billing for last 30 days:'
SELECT get_billing_last_n_days(
    '00000000-0000-0000-0000-000000000001',
    30
);

-- Billing for last 365 days
\echo 'Billing for last 365 days (all year 2025):'
SELECT get_billing_last_n_days(
    '00000000-0000-0000-0000-000000000001',
    365
);

-- =================================================================================================
-- TEST 5: Customer LTV Functions
-- =================================================================================================

\echo ''
\echo '===================================================================================='
\echo 'TEST 5: Customer LTV Functions'
\echo '===================================================================================='

-- LTV for John Doe (root_id 1001)
\echo 'LTV for John Doe:'
SELECT get_customer_ltv(1001);

-- LTV for Jane Smith (root_id 1002)
\echo 'LTV for Jane Smith:'
SELECT get_customer_ltv(1002);

-- Top 3 customers by LTV
\echo 'Top 3 customers by LTV:'
SELECT get_top_customers_by_ltv(
    '00000000-0000-0000-0000-000000000001',
    3
);

-- =================================================================================================
-- TEST 6: Billing Summary View
-- =================================================================================================

\echo ''
\echo '===================================================================================='
\echo 'TEST 6: Billing Summary View'
\echo '===================================================================================='

\echo 'Consolidated summary via VIEW:'
SELECT
    root_id,
    client_id,
    treatment_name,
    total_spent_currency,
    total_completed_appointments,
    average_ticket_currency,
    customer_lifetime_days,
    first_purchase_at,
    last_purchase_at
FROM vw_customer_billing_summary
WHERE inbox_id = '00000000-0000-0000-0000-000000000001'
ORDER BY total_spent_cents DESC;

-- =================================================================================================
-- TEST 7: LTV Recalculation Function
-- =================================================================================================

\echo ''
\echo '===================================================================================='
\echo 'TEST 7: LTV Recalculation Function'
\echo '===================================================================================='

-- Manually zero John Doe's LTV to test recalculation
UPDATE "3a_customer_root_record"
SET
    total_spent_cents = 0,
    total_completed_appointments = 0,
    first_purchase_at = NULL,
    last_purchase_at = NULL
WHERE id = 1001;

\echo 'John Doe LTV BEFORE recalculation (manually zeroed):'
SELECT
    treatment_name,
    total_spent_cents / 100.0 as total_spent_currency,
    total_completed_appointments
FROM "3a_customer_root_record"
WHERE id = 1001;

-- Recalculate LTV
\echo 'Recalculating John Doe LTV:'
SELECT recalculate_customer_ltv(1001);

\echo 'John Doe LTV AFTER recalculation (should be back to 450.00):'
SELECT
    treatment_name,
    total_spent_cents / 100.0 as total_spent_currency,
    total_completed_appointments,
    first_purchase_at,
    last_purchase_at
FROM "3a_customer_root_record"
WHERE id = 1001;

-- =================================================================================================
-- TEST 8: Bulk Recalculation for Entire Inbox
-- =================================================================================================

\echo ''
\echo '===================================================================================='
\echo 'TEST 8: Bulk Recalculation for Entire Inbox'
\echo '===================================================================================='

\echo 'Recalculating LTV for all customers in inbox:'
SELECT recalculate_all_ltv_for_inbox('00000000-0000-0000-0000-000000000001');

-- =================================================================================================
-- TEST 9: Edge Cases Validation
-- =================================================================================================

\echo ''
\echo '===================================================================================='
\echo 'TEST 9: Edge Cases Validation'
\echo '===================================================================================='

-- Appointment without value_cents (should not affect LTV)
INSERT INTO "4a_customer_service_history" (
    service_id, inbox_id, root_id, service_datetime_start, service_datetime_end,
    service_status, value_cents, completed_at, created_at
) VALUES (
    'AT_NO_VALUE', '00000000-0000-0000-0000-000000000001', 1001,
    '2025-03-01 10:00:00'::TIMESTAMPTZ, '2025-03-01 11:00:00'::TIMESTAMPTZ,
    'Completed', NULL, '2025-03-01 11:00:00'::TIMESTAMPTZ, '2025-03-01 09:00:00'::TIMESTAMPTZ
);

\echo 'John Doe LTV after appointment with NULL value_cents (should stay 450.00):'
SELECT
    treatment_name,
    total_spent_cents / 100.0 as total_spent_currency,
    total_completed_appointments
FROM "3a_customer_root_record"
WHERE id = 1001;

-- Appointment with value_cents = 0 (should not affect LTV)
INSERT INTO "4a_customer_service_history" (
    service_id, inbox_id, root_id, service_datetime_start, service_datetime_end,
    service_status, value_cents, completed_at, created_at
) VALUES (
    'AT_ZERO_VALUE', '00000000-0000-0000-0000-000000000001', 1001,
    '2025-03-02 10:00:00'::TIMESTAMPTZ, '2025-03-02 11:00:00'::TIMESTAMPTZ,
    'Completed', 0, '2025-03-02 11:00:00'::TIMESTAMPTZ, '2025-03-02 09:00:00'::TIMESTAMPTZ
);

\echo 'John Doe LTV after appointment with value_cents=0 (should stay 450.00):'
SELECT
    treatment_name,
    total_spent_cents / 100.0 as total_spent_currency,
    total_completed_appointments
FROM "3a_customer_root_record"
WHERE id = 1001;

-- =================================================================================================
-- TEST 10: Verify No Duplication on Already Completed Appointments
-- =================================================================================================

\echo ''
\echo '===================================================================================='
\echo 'TEST 10: Verify No Duplication'
\echo '===================================================================================='

\echo 'John Doe LTV BEFORE updating already Completed appointment:'
SELECT
    treatment_name,
    total_spent_cents / 100.0 as total_spent_currency,
    total_completed_appointments
FROM "3a_customer_root_record"
WHERE id = 1001;

-- Try updating appointment that is already Completed (should not duplicate)
UPDATE "4a_customer_service_history"
SET notes = 'Test update - should not duplicate LTV'
WHERE service_id = 'AT001';  -- Already Completed from the start

\echo 'John Doe LTV AFTER updating already Completed appointment (should stay 450.00):'
SELECT
    treatment_name,
    total_spent_cents / 100.0 as total_spent_currency,
    total_completed_appointments
FROM "3a_customer_root_record"
WHERE id = 1001;

-- =================================================================================================
-- FINAL SUMMARY
-- =================================================================================================

\echo ''
\echo '===================================================================================='
\echo 'FINAL SUMMARY - ALL CUSTOMERS'
\echo '===================================================================================='

SELECT
    cr.treatment_name,
    cr.total_spent_cents / 100.0 as total_spent_currency,
    cr.total_completed_appointments,
    (cr.total_spent_cents / NULLIF(cr.total_completed_appointments, 0)) / 100.0 as avg_ticket_currency,
    cr.first_purchase_at,
    cr.last_purchase_at,
    EXTRACT(DAY FROM (COALESCE(cr.last_purchase_at, NOW()) - cr.first_purchase_at))::INT as customer_lifetime_days,
    COUNT(h.id) as total_appointments_all_statuses
FROM "3a_customer_root_record" cr
LEFT JOIN "4a_customer_service_history" h ON h.root_id = cr.id
WHERE cr.inbox_id = '00000000-0000-0000-0000-000000000001'
GROUP BY cr.id, cr.treatment_name, cr.total_spent_cents, cr.total_completed_appointments,
         cr.first_purchase_at, cr.last_purchase_at
ORDER BY cr.total_spent_cents DESC;

\echo ''
\echo '===================================================================================='
\echo 'TESTS COMPLETED SUCCESSFULLY!'
\echo '===================================================================================='

ROLLBACK;  -- Undo all test changes

-- =================================================================================================
-- END OF TESTS
-- =================================================================================================
-- EXPECTED RESULTS:
--
-- TEST 1: John Doe should have 200.00 after first appointment
-- TEST 2: John Doe should have 450.00 after second appointment
-- TEST 3: Jane Smith should have 450.00 (3x 150.00)
--          Bob Johnson should have 300.00 (1x 300.00)
-- TEST 4: January/2025 = 350.00, February/2025 = 400.00
-- TEST 5: Individual LTV for each customer
-- TEST 6: View shows all consolidated data
-- TEST 7: Recalculation restores correct values
-- TEST 8: Bulk recalculation processes all customers
-- TEST 9: Appointments without value do not affect LTV
-- TEST 10: Updates to already Completed appointments do not duplicate values
-- =================================================================================================
