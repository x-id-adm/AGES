# Billing Metrics & LTV (Lifetime Value)

## 📊 Overview

This module implements complete billing tracking with two main features:

1. **Time-Based Billing**: How much was billed in specific periods (today, last 7 days, January, etc.)
2. **Customer-Based Billing (LTV)**: How much each customer has spent over time

**Currency-agnostic**: Works with any currency (USD, BRL, EUR, etc.) - all values stored in cents

---

## 🚀 Installation

Execute SQL files in this order:

```bash
# 1. Main schema (if not already executed)
psql -d your_database < schema.sql

# 2. Create billing functions
psql -d your_database < functions_billing_metrics.sql

# 3. Create automatic update trigger
psql -d your_database < trigger_update_customer_ltv.sql

# 4. (Optional) Run tests
psql -d your_database < test_billing_metrics.sql
```

---

## 📋 What Was Created?

### 1. New Fields in `3a_customer_root_record` Table

| Field | Type | Description |
|-------|------|-------------|
| `total_spent_cents` | BIGINT | Total amount spent by customer (in cents) |
| `total_completed_appointments` | INTEGER | Number of completed appointments |
| `first_purchase_at` | TIMESTAMPTZ | First purchase date |
| `last_purchase_at` | TIMESTAMPTZ | Last purchase date |

### 2. Time-Based Billing Functions

#### Today's Billing
```sql
SELECT get_billing_today('inbox-uuid');
```

**Returns:**
```json
{
  "total_billing_cents": 45000,
  "total_billing_currency": 450.00,
  "completed_count": 15,
  "average_ticket_cents": 3000,
  "average_ticket_currency": 30.00,
  "period": {
    "start": "2025-11-15T00:00:00Z",
    "end": "2025-11-15T14:30:00Z"
  }
}
```

#### Last N Days Billing
```sql
-- Last 7 days
SELECT get_billing_last_n_days('inbox-uuid', 7);

-- Last 30 days
SELECT get_billing_last_n_days('inbox-uuid', 30);
```

#### Specific Month Billing
```sql
-- January 2025
SELECT get_billing_specific_month('inbox-uuid', 2025, 1);

-- December 2024
SELECT get_billing_specific_month('inbox-uuid', 2024, 12);
```

#### Custom Period Billing
```sql
SELECT get_billing_by_period(
    'inbox-uuid',
    '2025-01-01 00:00:00'::TIMESTAMPTZ,
    '2025-01-31 23:59:59'::TIMESTAMPTZ
);
```

### 3. Customer LTV Functions

#### Specific Customer LTV
```sql
SELECT get_customer_ltv(123);  -- customer root_id
```

**Returns:**
```json
{
  "root_id": 123,
  "client_id": "CT456",
  "treatment_name": "John Doe",
  "total_spent_cents": 60000,
  "total_spent_currency": 600.00,
  "total_completed_appointments": 3,
  "average_ticket_cents": 20000,
  "average_ticket_currency": 200.00,
  "first_purchase_at": "2025-01-15T10:00:00Z",
  "last_purchase_at": "2025-11-10T14:30:00Z",
  "customer_lifetime_days": 299
}
```

#### Top Customers by LTV
```sql
-- Top 10 customers
SELECT get_top_customers_by_ltv('inbox-uuid', 10);

-- Top 50 customers
SELECT get_top_customers_by_ltv('inbox-uuid', 50);
```

### 4. Summary View

#### View All Customers Ordered by LTV
```sql
SELECT *
FROM vw_customer_billing_summary
WHERE inbox_id = 'inbox-uuid'
ORDER BY total_spent_cents DESC
LIMIT 20;
```

#### Filter Customers Who Spent More Than 100000 Cents
```sql
SELECT *
FROM vw_customer_billing_summary
WHERE total_spent_currency > 1000
  AND inbox_id = 'inbox-uuid'
ORDER BY total_spent_cents DESC;
```

---

## 🔄 Automatic Update (Trigger)

LTV is updated **automatically** when:

1. An appointment is created with status `'Completed'`
2. An appointment has its status changed to `'Completed'`

### How the Human Operator Works:

```sql
-- 1. Operator creates appointment
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
    'AT123',
    'inbox-uuid',
    456,  -- customer root_id
    NOW(),
    NOW() + INTERVAL '1 hour',
    'Scheduled',
    20000,  -- 200.00 in currency
    NOW(),
    NOW()
);

-- 2. When appointment finishes, operator changes status
UPDATE "4a_customer_service_history"
SET
    service_status = 'Completed',
    completed_at = NOW()
WHERE service_id = 'AT123';

-- 3. Trigger AUTOMATICALLY updates customer LTV:
--    - Adds 200.00 to total_spent_cents
--    - Increments total_completed_appointments
--    - Updates last_purchase_at
--    - If first purchase, sets first_purchase_at
```

### Important: Prevents Duplication

The trigger is smart and **DOES NOT duplicate values**:

- If you update an appointment that is ALREADY `'Completed'`, it won't add again
- If you only update other fields (notes, attachments), it doesn't affect LTV
- If `value_cents` is `NULL` or `0`, it doesn't update LTV

---

## 🛠️ Helper Functions

### Recalculate Customer LTV

If you need to recalculate a customer's LTV (to fix inconsistencies):

```sql
SELECT recalculate_customer_ltv(123);  -- customer root_id
```

### Recalculate LTV for All Customers in Inbox

```sql
SELECT recalculate_all_ltv_for_inbox('inbox-uuid');
```

**Returns:**
```json
{
  "inbox_id": "inbox-uuid",
  "customers_processed": 150,
  "total_billing_cents": 1500000,
  "total_billing_currency": 15000.00,
  "recalculated_at": "2025-11-15T14:30:00Z"
}
```

---

## 📊 Usage Examples

### Billing Dashboard

```sql
-- Today's billing
SELECT
    (result->>'total_billing_currency')::NUMERIC as today,
    (result->>'completed_count')::INT as appointments_today
FROM (
    SELECT get_billing_today('inbox-uuid') as result
) sub;

-- Last 7 days billing
SELECT
    (result->>'total_billing_currency')::NUMERIC as last_7_days,
    (result->>'average_ticket_currency')::NUMERIC as avg_ticket
FROM (
    SELECT get_billing_last_n_days('inbox-uuid', 7) as result
) sub;

-- Current month billing
SELECT
    (result->>'total_billing_currency')::NUMERIC as current_month,
    (result->>'completed_count')::INT as appointments_month
FROM (
    SELECT get_billing_specific_month(
        'inbox-uuid',
        EXTRACT(YEAR FROM NOW())::INT,
        EXTRACT(MONTH FROM NOW())::INT
    ) as result
) sub;
```

### Customer Dashboard (LTV)

```sql
-- Top 10 customers
SELECT
    (customer->>'treatment_name')::TEXT as customer,
    (customer->>'total_spent_currency')::NUMERIC as total_spent,
    (customer->>'total_completed_appointments')::INT as appointments,
    (customer->>'average_ticket_currency')::NUMERIC as avg_ticket
FROM (
    SELECT jsonb_array_elements(
        get_top_customers_by_ltv('inbox-uuid', 10)
    ) as customer
) sub;
```

### Individual Customer Analysis

```sql
-- View everything about a specific customer
SELECT
    treatment_name,
    total_spent_currency,
    total_completed_appointments,
    average_ticket_currency,
    customer_lifetime_days,
    first_purchase_at,
    last_purchase_at
FROM vw_customer_billing_summary
WHERE root_id = 123;
```

---

## 🔍 Useful Queries

### Customers with Highest LTV
```sql
SELECT
    treatment_name,
    total_spent_currency,
    total_completed_appointments,
    average_ticket_currency
FROM vw_customer_billing_summary
WHERE inbox_id = 'inbox-uuid'
ORDER BY total_spent_cents DESC
LIMIT 10;
```

### Most Frequent Customers
```sql
SELECT
    treatment_name,
    total_completed_appointments,
    total_spent_currency,
    average_ticket_currency
FROM vw_customer_billing_summary
WHERE inbox_id = 'inbox-uuid'
ORDER BY total_completed_appointments DESC
LIMIT 10;
```

### Customers with Highest Average Ticket
```sql
SELECT
    treatment_name,
    average_ticket_currency,
    total_completed_appointments,
    total_spent_currency
FROM vw_customer_billing_summary
WHERE inbox_id = 'inbox-uuid'
  AND total_completed_appointments >= 3  -- At least 3 appointments
ORDER BY average_ticket_cents DESC
LIMIT 10;
```

### Month-by-Month Billing Comparison
```sql
SELECT
    to_char(make_date(2025, month, 1), 'Month YYYY') as period,
    (get_billing_specific_month('inbox-uuid', 2025, month)->>'total_billing_currency')::NUMERIC as billing,
    (get_billing_specific_month('inbox-uuid', 2025, month)->>'completed_count')::INT as appointments
FROM generate_series(1, 12) as month
ORDER BY month;
```

---

## 🎯 Use Cases

### 1. How much am I billing today?
```sql
SELECT get_billing_today('inbox-uuid');
```

### 2. How much did I bill in the last 7 days?
```sql
SELECT get_billing_last_n_days('inbox-uuid', 7);
```

### 3. How much did I bill in January?
```sql
SELECT get_billing_specific_month('inbox-uuid', 2025, 1);
```

### 4. Who are my top 10 customers?
```sql
SELECT get_top_customers_by_ltv('inbox-uuid', 10);
```

### 5. How much has a specific customer spent?
```sql
SELECT get_customer_ltv(123);  -- customer root_id
```

### 6. List customers who spent more than 50000 cents (500 in currency)
```sql
SELECT
    treatment_name,
    total_spent_currency,
    total_completed_appointments
FROM vw_customer_billing_summary
WHERE total_spent_currency > 500
  AND inbox_id = 'inbox-uuid'
ORDER BY total_spent_currency DESC;
```

---

## ⚙️ Technical Details

### Values in Cents

All monetary values are stored in **cents** (INTEGER) to avoid rounding issues:

- 100.00 in currency = 10000 cents
- 50.50 in currency = 5050 cents
- 1234.56 in currency = 123456 cents

Functions return both cents and currency values for convenience.

### Performance

- **Indexes created** to optimize LTV and customer ranking queries
- **Calculated fields** are stored (not recalculated on every query)
- **Optimized trigger** to avoid unnecessary processing

### Security

- All functions validate input parameters
- Transactions used to ensure consistency
- No risk of value duplication

---

## 🧪 Tests

Run the test file to validate all functionalities:

```bash
psql -d your_database < test_billing_metrics.sql
```

Tests cover:
- ✅ LTV trigger on INSERT
- ✅ LTV trigger on UPDATE
- ✅ Multiple customers and appointments
- ✅ Time-based billing functions
- ✅ Customer LTV functions
- ✅ Summary view
- ✅ LTV recalculation
- ✅ Edge cases (null values, zeros, duplication)

---

## 📝 Important Notes

1. **Only `'Completed'` appointments** are considered in billing
2. **The `value_cents` field** must be filled by operator when completing appointment
3. **Trigger is automatic** - no need to manually update LTV
4. **Values in cents** avoid rounding issues
5. **Recalculating LTV** is safe and can be done anytime
6. **Currency-agnostic** - works with any currency system

---

## 🆘 Troubleshooting

### LTV not being updated

Check if:
1. Trigger is created: `\d+ "4a_customer_service_history"`
2. Status was changed to `'Completed'`
3. Field `value_cents` has a value > 0
4. Field `completed_at` was filled

### Recalculate LTV for all customers

```sql
SELECT recalculate_all_ltv_for_inbox('inbox-uuid');
```

### View trigger logs

Trigger emits logs with `RAISE NOTICE`. To view:

```sql
SET client_min_messages TO NOTICE;
```

---

## 📚 Files

- `schema.sql` - Main schema with LTV fields
- `functions_billing_metrics.sql` - Billing and LTV functions
- `trigger_update_customer_ltv.sql` - Automatic update trigger
- `test_billing_metrics.sql` - Complete tests

---

**Version:** 1.0
**Date:** 2025-11-15
**System:** AGES
