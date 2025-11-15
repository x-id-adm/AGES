-- =================================================================================================
-- TRIGGER: AUTOMATIC LTV (LIFETIME VALUE) UPDATE
-- =================================================================================================
-- DESCRIPTION:
--   Trigger that automatically updates LTV fields in table 3a_customer_root_record
--   whenever an appointment is marked as 'Completed'.
--
-- BEHAVIOR:
--   - Triggers when service_status changes to 'Completed'
--   - Updates total_spent_cents, total_completed_appointments
--   - Updates first_purchase_at (if it's the first purchase)
--   - Updates last_purchase_at
--
-- IMPORTANT:
--   - Only appointments with value_cents > 0 are considered
--   - Does not count the same appointment twice
--   - Works for both INSERT and UPDATE operations
--
-- VERSION: 1.0
-- DATE: 2025-11-15
-- =================================================================================================


-- =================================================================================================
-- TRIGGER FUNCTION
-- =================================================================================================

-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNCTION: update_customer_ltv                                                               │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PURPOSE:                                                                                    │
-- │   Function called by trigger to update customer LTV fields.                                 │
-- │                                                                                             │
-- │ LOGIC:                                                                                      │
-- │   1. Check if it's an INSERT or UPDATE                                                      │
-- │   2. If UPDATE:                                                                             │
-- │      - Check if status changed from something else to 'Completed'                           │
-- │      - If old status was already 'Completed', do nothing (avoid duplication)                │
-- │   3. If INSERT:                                                                             │
-- │      - Check if status is 'Completed'                                                       │
-- │   4. Check if value_cents is defined and > 0                                                │
-- │   5. Update fields in table 3a_customer_root_record:                                        │
-- │      - Increment total_spent_cents                                                          │
-- │      - Increment total_completed_appointments                                               │
-- │      - Update last_purchase_at                                                              │
-- │      - Set first_purchase_at if it's the first purchase                                     │
-- │                                                                                             │
-- │ PARAMETERS:                                                                                 │
-- │   NEW - New record (after INSERT/UPDATE)                                                    │
-- │   OLD - Old record (before UPDATE, NULL on INSERT)                                          │
-- │                                                                                             │
-- │ RETURN:                                                                                     │
-- │   NEW (standard for BEFORE triggers)                                                        │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION update_customer_ltv()
RETURNS TRIGGER AS $$
DECLARE
    v_should_update BOOLEAN := FALSE;
BEGIN
    -- ========================================
    -- VALIDATIONS: Determine if should update
    -- ========================================

    -- Case 1: INSERT - check if already Completed
    IF TG_OP = 'INSERT' THEN
        IF NEW.service_status = 'Completed' THEN
            v_should_update := TRUE;
        END IF;
    END IF;

    -- Case 2: UPDATE - check if changed to Completed
    IF TG_OP = 'UPDATE' THEN
        -- Only update if:
        -- 1. Status changed to 'Completed' AND
        -- 2. Previous status was different from 'Completed'
        -- (avoid counting the same appointment twice)
        IF NEW.service_status = 'Completed' AND OLD.service_status != 'Completed' THEN
            v_should_update := TRUE;
        END IF;
    END IF;

    -- Additional validation: must have valid value_cents
    IF v_should_update THEN
        IF NEW.value_cents IS NULL OR NEW.value_cents <= 0 THEN
            v_should_update := FALSE;
        END IF;
    END IF;

    -- If should not update, return without doing anything
    IF NOT v_should_update THEN
        RETURN NEW;
    END IF;

    -- ========================================
    -- LTV UPDATE
    -- ========================================

    -- Update LTV fields in customer record
    UPDATE "3a_customer_root_record"
    SET
        -- Increment total spent
        total_spent_cents = total_spent_cents + NEW.value_cents,

        -- Increment completed appointments count
        total_completed_appointments = total_completed_appointments + 1,

        -- Update last purchase date
        last_purchase_at = NEW.completed_at,

        -- Set first purchase date (if not yet set)
        first_purchase_at = CASE
            WHEN first_purchase_at IS NULL THEN NEW.completed_at
            ELSE first_purchase_at
        END,

        -- Update modification timestamp
        updated_at = NOW()

    WHERE id = NEW.root_id;

    -- Debug log (optional - comment in production if not needed)
    RAISE NOTICE 'LTV updated for root_id %: +% cents (total now: %)',
        NEW.root_id,
        NEW.value_cents,
        (SELECT total_spent_cents FROM "3a_customer_root_record" WHERE id = NEW.root_id);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- =================================================================================================
-- TRIGGER CREATION
-- =================================================================================================

-- Drop trigger if exists (to allow script re-execution)
DROP TRIGGER IF EXISTS trigger_update_customer_ltv ON "4a_customer_service_history";

-- Create trigger
CREATE TRIGGER trigger_update_customer_ltv
    AFTER INSERT OR UPDATE OF service_status
    ON "4a_customer_service_history"
    FOR EACH ROW
    EXECUTE FUNCTION update_customer_ltv();


-- =================================================================================================
-- HELPER FUNCTION: Manually Recalculate LTV
-- =================================================================================================

-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNCTION: recalculate_customer_ltv                                                          │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PURPOSE:                                                                                    │
-- │   Recalculates a customer's LTV based on all their appointments.                            │
-- │   Useful for fixing data or initializing values.                                            │
-- │                                                                                             │
-- │ PARAMETERS:                                                                                 │
-- │   p_root_id (BIGINT) - Customer record ID                                                   │
-- │                                                                                             │
-- │ RETURN:                                                                                     │
-- │   JSONB with newly calculated values                                                        │
-- │                                                                                             │
-- │ USAGE EXAMPLE:                                                                              │
-- │   -- Recalculate LTV for specific customer                                                  │
-- │   SELECT recalculate_customer_ltv(123);                                                     │
-- │                                                                                             │
-- │   -- Recalculate LTV for all customers in an inbox                                          │
-- │   SELECT recalculate_customer_ltv(id)                                                       │
-- │   FROM "3a_customer_root_record"                                                            │
-- │   WHERE inbox_id = 'inbox-uuid';                                                            │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION recalculate_customer_ltv(
    p_root_id BIGINT
)
RETURNS JSONB AS $$
DECLARE
    v_total_cents BIGINT;
    v_completed_count INT;
    v_first_purchase TIMESTAMPTZ;
    v_last_purchase TIMESTAMPTZ;
    v_result JSONB;
BEGIN
    -- Calculate aggregated values from all completed appointments
    SELECT
        COALESCE(SUM(value_cents), 0),
        COUNT(*),
        MIN(completed_at),
        MAX(completed_at)
    INTO
        v_total_cents,
        v_completed_count,
        v_first_purchase,
        v_last_purchase
    FROM "4a_customer_service_history"
    WHERE root_id = p_root_id
      AND service_status = 'Completed'
      AND value_cents IS NOT NULL
      AND value_cents > 0;

    -- Update customer record
    UPDATE "3a_customer_root_record"
    SET
        total_spent_cents = v_total_cents,
        total_completed_appointments = v_completed_count,
        first_purchase_at = v_first_purchase,
        last_purchase_at = v_last_purchase,
        updated_at = NOW()
    WHERE id = p_root_id;

    -- Return calculated values
    v_result := jsonb_build_object(
        'root_id', p_root_id,
        'total_spent_cents', v_total_cents,
        'total_spent_currency', ROUND(v_total_cents::NUMERIC / 100, 2),
        'total_completed_appointments', v_completed_count,
        'first_purchase_at', v_first_purchase,
        'last_purchase_at', v_last_purchase
    );

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;


-- =================================================================================================
-- HELPER FUNCTION: Recalculate LTV for All Customers in an Inbox
-- =================================================================================================

-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNCTION: recalculate_all_ltv_for_inbox                                                     │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PURPOSE:                                                                                    │
-- │   Recalculates LTV for all customers in an inbox.                                           │
-- │   Useful for initializing values or fixing inconsistencies in bulk.                         │
-- │                                                                                             │
-- │ PARAMETERS:                                                                                 │
-- │   p_inbox_id (UUID) - Inbox ID                                                              │
-- │                                                                                             │
-- │ RETURN:                                                                                     │
-- │   JSONB with operation statistics                                                           │
-- │                                                                                             │
-- │ USAGE EXAMPLE:                                                                              │
-- │   SELECT recalculate_all_ltv_for_inbox('inbox-uuid');                                       │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION recalculate_all_ltv_for_inbox(
    p_inbox_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_customer_count INT;
    v_total_billing BIGINT := 0;
    v_customer RECORD;
    v_result JSONB;
BEGIN
    v_customer_count := 0;

    -- Loop through all customers in inbox
    FOR v_customer IN
        SELECT id FROM "3a_customer_root_record"
        WHERE inbox_id = p_inbox_id
    LOOP
        -- Recalculate customer LTV
        PERFORM recalculate_customer_ltv(v_customer.id);
        v_customer_count := v_customer_count + 1;
    END LOOP;

    -- Calculate total inbox billing
    SELECT COALESCE(SUM(total_spent_cents), 0)
    INTO v_total_billing
    FROM "3a_customer_root_record"
    WHERE inbox_id = p_inbox_id;

    -- Return statistics
    v_result := jsonb_build_object(
        'inbox_id', p_inbox_id,
        'customers_processed', v_customer_count,
        'total_billing_cents', v_total_billing,
        'total_billing_currency', ROUND(v_total_billing::NUMERIC / 100, 2),
        'recalculated_at', NOW()
    );

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;


-- =================================================================================================
-- SUMMARY
-- =================================================================================================
-- Trigger created: trigger_update_customer_ltv
--   - Fires on: INSERT or UPDATE of service_status in table 4a_customer_service_history
--   - When: service_status changes to 'Completed' and value_cents > 0
--   - Updates: LTV fields in table 3a_customer_root_record
--
-- Helper functions created:
--   • recalculate_customer_ltv(p_root_id) - Recalculate LTV for one customer
--   • recalculate_all_ltv_for_inbox(p_inbox_id) - Recalculate LTV for all customers
-- =================================================================================================
