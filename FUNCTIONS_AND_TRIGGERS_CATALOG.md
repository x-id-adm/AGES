# AGES PostgreSQL Functions & Triggers Catalog

## Executive Summary

- **Total SQL Files**: 11 files
- **Total Lines of SQL Code**: 5,610 lines
- **Total Functions**: 25 PostgreSQL functions
- **Total Triggers**: 20 PostgreSQL triggers (19 named + 1 dynamic)
- **Project Size**: 362 KB total

---

## 1. PROJECT FILE STRUCTURE

### Database Files Organization

```
/home/user/AGES/
├── functions.SQL                          (112 KB) - Core system functions
├── triggers.SQL                           (37 KB)  - Main triggers definitions
├── functions_billing_metrics.sql          (30 KB)  - Billing-related functions
├── functions_time_based_counters.sql      (23 KB)  - Time-based counter functions
├── trigger_update_customer_ltv.sql        (17 KB)  - LTV calculation trigger & functions
├── schema.sql                             (26 KB)  - Database schema definitions
├── test_billing_metrics.sql               (19 KB)  - Billing function tests
├── test_time_based_counters.sql           (14 KB)  - Time counter tests
├── test_funnel_rates.sql                  (13 KB)  - Funnel rate tests
├── test_conversion_rates.sql              (12 KB)  - Conversion rate tests
└── test_appointment_status_counters.sql   (8.8 KB) - Appointment status tests
```

### Directory Structure
- All SQL files are located at the project root: `/home/user/AGES/`
- No migration directories found
- All database objects are defined in SQL files with clear organization

---

## 2. ALL POSTGRESQL FUNCTIONS (25 TOTAL)

### 2.1 Core System Functions (functions.SQL - 12 functions)

| # | Function Name | Location | Line | Purpose |
|---|---|---|---|---|
| 1 | `func_upsert_contact_from_webhook()` | functions.SQL | 69 | Synchronizes webhook data with local inbox and contact tables (atomic UPSERT) |
| 2 | `func_sync_owner_to_cell_sheet()` | functions.SQL | 219 | Propagates whatsapp_owner to cell phone table for synchronization |
| 3 | `func_generate_friendly_client_id()` | functions.SQL | 288 | Generates human-friendly client IDs (e.g., CT1, CT2, CT3...) |
| 4 | `func_generate_friendly_service_id()` | functions.SQL | 328 | Generates human-friendly service appointment IDs (e.g., AT1, AT2...) |
| 5 | `func_ensure_first_is_primary()` | functions.SQL | 384 | Marks the first phone/email/etc. as primary automatically |
| 6 | `func_generate_ulid()` | functions.SQL | 432 | Generates ULID (Universally Unique Lexicographically Sortable Identifier) for message tracking |
| 7 | `func_auto_populate_message_fields()` | functions.SQL | 495 | Auto-populates message source_message_id and creates tsvector for full-text search |
| 8 | `update_updated_at_column()` | functions.SQL | 520 | Automatically updates `updated_at` timestamp on row updates |
| 9 | `func_check_complete_form()` | functions.SQL | 1126 | Validates if customer form is complete based on JSON requirements |
| 10 | `func_update_form_counter()` | functions.SQL | 1369 | Updates the form completion counter in inbox_counters |
| 11 | `func_set_status_timestamp()` | functions.SQL | 1507 | Sets status-specific timestamps when appointment status changes |
| 12 | `func_update_appointment_status_counter()` | functions.SQL | 1609 | Updates appointment status counters in inbox_counters |

### 2.2 Billing Metrics Functions (functions_billing_metrics.sql - 6 functions)

| # | Function Name | Location | Line | Purpose |
|---|---|---|---|---|
| 13 | `get_billing_by_period()` | functions_billing_metrics.sql | 69 | Returns total billing for a specific time period |
| 14 | `get_billing_today()` | functions_billing_metrics.sql | 132 | Returns billing for today |
| 15 | `get_billing_last_n_days()` | functions_billing_metrics.sql | 164 | Returns billing for last N days |
| 16 | `get_billing_specific_month()` | functions_billing_metrics.sql | 197 | Returns billing for a specific month |
| 17 | `get_customer_ltv()` | functions_billing_metrics.sql | 259 | Returns Lifetime Value metrics for a single customer |
| 18 | `get_top_customers_by_ltv()` | functions_billing_metrics.sql | 327 | Returns top N customers ranked by LTV |

### 2.3 Time-Based Counter Functions (functions_time_based_counters.sql - 4 functions)

| # | Function Name | Location | Line | Purpose |
|---|---|---|---|---|
| 19 | `func_get_appointment_counters_by_period()` | functions_time_based_counters.sql | 65 | Returns appointment counters by status for a time period |
| 20 | `func_get_counters_last_n_days()` | functions_time_based_counters.sql | 114 | Returns counters for last N days |
| 21 | `func_get_counters_specific_month()` | functions_time_based_counters.sql | 147 | Returns counters for a specific month |
| 22 | `func_count_status_changes()` | functions_time_based_counters.sql | 209 | Counts how many times status changes occurred in a period |

### 2.4 LTV Update & Recalculation Functions (trigger_update_customer_ltv.sql - 3 functions)

| # | Function Name | Location | Line | Purpose |
|---|---|---|---|---|
| 23 | `update_customer_ltv()` | trigger_update_customer_ltv.sql | 55 | Trigger function that updates LTV when appointments are completed |
| 24 | `recalculate_customer_ltv()` | trigger_update_customer_ltv.sql | 173 | Recalculates LTV for a specific customer from scratch |
| 25 | `recalculate_all_ltv_for_inbox()` | trigger_update_customer_ltv.sql | 246 | Recalculates LTV for all customers in an inbox |

---

## 3. ALL POSTGRESQL TRIGGERS (20 TOTAL)

### 3.1 Synchronization Triggers (1 trigger)

| # | Trigger Name | Location | Target Table | Event | Function | Purpose |
|---|---|---|---|---|---|---|
| 1 | `trig_sync_owner_to_cell` | triggers.SQL:60 | 3a_customer_root_record | AFTER INSERT OR UPDATE | `func_sync_owner_to_cell_sheet()` | Syncs WhatsApp owner to cell phone sheet |

### 3.2 ID Generation Triggers (2 triggers)

| # | Trigger Name | Location | Target Table | Event | Function | Purpose |
|---|---|---|---|---|---|---|
| 2 | `trg_generate_client_id` | triggers.SQL:84 | 3a_customer_root_record | BEFORE INSERT | `func_generate_friendly_client_id()` | Auto-generates client IDs (CT1, CT2...) |
| 3 | `trg_generate_service_id` | triggers.SQL:104 | 4a_customer_service_history | BEFORE INSERT | `func_generate_friendly_service_id()` | Auto-generates service IDs (AT1, AT2...) |

### 3.3 Automatic Timestamp Trigger (1 dynamic trigger)

| # | Trigger Name | Location | Target Table | Event | Function | Purpose |
|---|---|---|---|---|---|---|
| 4 | `trigger_update_timestamp` | triggers.SQL:148 | ALL TABLES with `updated_at` | BEFORE UPDATE | `update_updated_at_column()` | Dynamically updates `updated_at` on all tables that have the column |

**Note**: This trigger is created dynamically for every table with an `updated_at` column.

### 3.4 Primary Marker Triggers (3 triggers)

| # | Trigger Name | Location | Target Table | Event | Function | Purpose |
|---|---|---|---|---|---|---|
| 5 | `trg_first_cell_phone_is_primary` | triggers.SQL:174 | 3b_cell_phone_linked_service_sheet | BEFORE INSERT | `func_ensure_first_is_primary()` | Marks first cell phone as primary |
| 6 | `trg_first_email_is_primary` | triggers.SQL:193 | 3e_email | BEFORE INSERT | `func_ensure_first_is_primary()` | Marks first email as primary |
| 7 | `trg_first_landline_is_primary` | triggers.SQL:212 | 3f_landline_phone | BEFORE INSERT | `func_ensure_first_is_primary()` | Marks first landline as primary |

### 3.5 Message Automation Trigger (1 trigger)

| # | Trigger Name | Location | Target Table | Event | Function | Purpose |
|---|---|---|---|---|---|---|
| 8 | `trg_auto_populate_message` | triggers.SQL:248 | 2b_conversation_messages | BEFORE INSERT OR UPDATE | `func_auto_populate_message_fields()` | Auto-populates message fields and generates ULIDs |

### 3.6 Form Completion Validation Triggers (9 triggers)

| # | Trigger Name | Location | Target Table | Event | Function | Purpose |
|---|---|---|---|---|---|---|
| 9 | `trg_check_form_complete_3a` | triggers.SQL:299 | 3a_customer_root_record | AFTER INSERT OR UPDATE | `func_update_form_counter()` | Validates form completion - Root customer record |
| 10 | `trg_check_form_complete_3b` | triggers.SQL:308 | 3b_cell_phone_linked_service_sheet | AFTER INSERT OR UPDATE | `func_update_form_counter()` | Validates form completion - Cell phone |
| 11 | `trg_check_form_complete_3c` | triggers.SQL:317 | 3c_gender | AFTER INSERT OR UPDATE | `func_update_form_counter()` | Validates form completion - Gender |
| 12 | `trg_check_form_complete_3d` | triggers.SQL:326 | 3d_birth_date | AFTER INSERT OR UPDATE | `func_update_form_counter()` | Validates form completion - Birth date |
| 13 | `trg_check_form_complete_3e` | triggers.SQL:335 | 3e_email | AFTER INSERT OR UPDATE | `func_update_form_counter()` | Validates form completion - Email |
| 14 | `trg_check_form_complete_3f` | triggers.SQL:344 | 3f_landline_phone | AFTER INSERT OR UPDATE | `func_update_form_counter()` | Validates form completion - Landline phone |
| 15 | `trg_check_form_complete_3g` | triggers.SQL:353 | 3g_cpf | AFTER INSERT OR UPDATE | `func_update_form_counter()` | Validates form completion - CPF |
| 16 | `trg_check_form_complete_3h` | triggers.SQL:362 | 3h_rg | AFTER INSERT OR UPDATE | `func_update_form_counter()` | Validates form completion - RG |
| 17 | `trg_check_form_complete_3i` | triggers.SQL:371 | 3i_endereco_br | AFTER INSERT OR UPDATE | `func_update_form_counter()` | Validates form completion - Address |

### 3.7 Appointment Status Triggers (2 triggers)

| # | Trigger Name | Location | Target Table | Event | Function | Purpose |
|---|---|---|---|---|---|---|
| 18 | `trg_set_status_timestamp` | triggers.SQL:402 | 4a_customer_service_history | BEFORE INSERT OR UPDATE | `func_set_status_timestamp()` | Sets status-specific timestamps |
| 19 | `trg_update_appointment_status_counter` | triggers.SQL:451 | 4a_customer_service_history | AFTER INSERT OR UPDATE | `func_update_appointment_status_counter()` | Updates status counters |

### 3.8 LTV Update Trigger (1 trigger)

| # | Trigger Name | Location | Target Table | Event | Function | Purpose |
|---|---|---|---|---|---|---|
| 20 | `trigger_update_customer_ltv` | trigger_update_customer_ltv.sql:140 | 4a_customer_service_history | AFTER INSERT OR UPDATE OF service_status | `update_customer_ltv()` | Updates customer LTV when appointment is completed |

---

## 4. FUNCTION-TO-TRIGGER MAPPING

### Functions Used by Triggers (sorted by usage frequency)

| Function Name | Used By Triggers | Count |
|---|---|---|
| `func_update_form_counter()` | trg_check_form_complete_3a, 3b, 3c, 3d, 3e, 3f, 3g, 3h, 3i | 9 |
| `func_ensure_first_is_primary()` | trg_first_cell_phone_is_primary, trg_first_email_is_primary, trg_first_landline_is_primary | 3 |
| `update_updated_at_column()` | trigger_update_timestamp (dynamic, all tables with updated_at) | 1+ (dynamic) |
| `func_sync_owner_to_cell_sheet()` | trig_sync_owner_to_cell | 1 |
| `func_generate_friendly_client_id()` | trg_generate_client_id | 1 |
| `func_generate_friendly_service_id()` | trg_generate_service_id | 1 |
| `func_auto_populate_message_fields()` | trg_auto_populate_message | 1 |
| `func_set_status_timestamp()` | trg_set_status_timestamp | 1 |
| `func_update_appointment_status_counter()` | trg_update_appointment_status_counter | 1 |
| `update_customer_ltv()` | trigger_update_customer_ltv | 1 |

### Functions NOT Used by Triggers

These functions are typically called manually or from application code:

| Function Name | File | Purpose | Usage Type |
|---|---|---|---|
| `func_upsert_contact_from_webhook()` | functions.SQL | Webhook data synchronization | Application/API call |
| `func_check_complete_form()` | functions.SQL | Form validation check | Application/API call |
| `get_billing_by_period()` | functions_billing_metrics.sql | Query billing data | Application/Reporting |
| `get_billing_today()` | functions_billing_metrics.sql | Query today's billing | Application/Reporting |
| `get_billing_last_n_days()` | functions_billing_metrics.sql | Query recent billing | Application/Reporting |
| `get_billing_specific_month()` | functions_billing_metrics.sql | Query monthly billing | Application/Reporting |
| `get_customer_ltv()` | functions_billing_metrics.sql | Query customer LTV | Application/Reporting |
| `get_top_customers_by_ltv()` | functions_billing_metrics.sql | Ranking query | Application/Reporting |
| `func_generate_ulid()` | functions.SQL | ULID generation | Called by func_auto_populate_message_fields() |
| `func_get_appointment_counters_by_period()` | functions_time_based_counters.sql | Query counters | Application/Reporting |
| `func_get_counters_last_n_days()` | functions_time_based_counters.sql | Query counters | Application/Reporting |
| `func_get_counters_specific_month()` | functions_time_based_counters.sql | Query counters | Application/Reporting |
| `func_count_status_changes()` | functions_time_based_counters.sql | Query status changes | Application/Reporting |
| `recalculate_customer_ltv()` | trigger_update_customer_ltv.sql | Manual LTV recalculation | Application/Admin call |
| `recalculate_all_ltv_for_inbox()` | trigger_update_customer_ltv.sql | Batch LTV recalculation | Application/Admin call |

---

## 5. TABLE-TO-TRIGGER MAPPING

### Tables with Triggers (by table)

| Table Name | Number of Triggers | Triggers | Purpose |
|---|---|---|---|
| `3a_customer_root_record` | 3 | trig_sync_owner_to_cell, trg_generate_client_id, trg_check_form_complete_3a, trigger_update_timestamp* | Core customer record management |
| `4a_customer_service_history` | 4 | trg_generate_service_id, trg_set_status_timestamp, trg_update_appointment_status_counter, trigger_update_customer_ltv, trigger_update_timestamp* | Service/appointment tracking & LTV updates |
| `3b_cell_phone_linked_service_sheet` | 2 | trg_first_cell_phone_is_primary, trg_check_form_complete_3b, trigger_update_timestamp* | Phone management |
| `3c_gender` | 1 | trg_check_form_complete_3c, trigger_update_timestamp* | Gender information |
| `3d_birth_date` | 1 | trg_check_form_complete_3d, trigger_update_timestamp* | Birth date information |
| `3e_email` | 2 | trg_first_email_is_primary, trg_check_form_complete_3e, trigger_update_timestamp* | Email management |
| `3f_landline_phone` | 2 | trg_first_landline_is_primary, trg_check_form_complete_3f, trigger_update_timestamp* | Landline management |
| `3g_cpf` | 1 | trg_check_form_complete_3g, trigger_update_timestamp* | CPF information |
| `3h_rg` | 1 | trg_check_form_complete_3h, trigger_update_timestamp* | RG information |
| `3i_endereco_br` | 1 | trg_check_form_complete_3i, trigger_update_timestamp* | Address information |
| `2b_conversation_messages` | 2 | trg_auto_populate_message, trigger_update_timestamp* | Message handling |
| `0a_inbox_whatsapp` | 1 | trigger_update_timestamp* | Inbox management |
| `1a_whatsapp_user_contact` | 1 | trigger_update_timestamp* | Contact management |

*`trigger_update_timestamp` is dynamically applied to all tables with `updated_at` column

---

## 6. FUNCTION CATEGORIES BY RESPONSIBILITY

### 6.1 Data Synchronization (3 functions)
- `func_upsert_contact_from_webhook()` - Webhook data sync
- `func_sync_owner_to_cell_sheet()` - Owner to cell phone sync
- Called by: 1 trigger + application code

### 6.2 ID Generation (2 functions)
- `func_generate_friendly_client_id()` - Client ID generation
- `func_generate_friendly_service_id()` - Service ID generation
- Called by: 2 triggers

### 6.3 Message & ID Utilities (2 functions)
- `func_generate_ulid()` - ULID generation for tracking
- `func_auto_populate_message_fields()` - Message field automation
- Called by: 1 trigger + functions

### 6.4 Timestamp Management (1 function)
- `update_updated_at_column()` - Auto timestamp updates
- Called by: 1 dynamic trigger (applies to 10+ tables)

### 6.5 Form & Data Validation (3 functions)
- `func_check_complete_form()` - Form completeness validation
- `func_update_form_counter()` - Form counter updates
- `func_ensure_first_is_primary()` - Primary record marking
- Called by: 9 triggers + application code

### 6.6 Appointment Status Management (2 functions)
- `func_set_status_timestamp()` - Status timestamp setting
- `func_update_appointment_status_counter()` - Counter updates
- Called by: 2 triggers

### 6.7 Billing & Revenue (6 functions)
- `get_billing_by_period()` - Period-based billing query
- `get_billing_today()` - Today's billing
- `get_billing_last_n_days()` - Recent billing query
- `get_billing_specific_month()` - Monthly billing query
- `get_customer_ltv()` - Customer lifetime value
- `get_top_customers_by_ltv()` - Customer ranking by LTV
- Called by: Application code (reporting/analytics)

### 6.8 Time-Based Analytics (4 functions)
- `func_get_appointment_counters_by_period()` - Appointment counters
- `func_get_counters_last_n_days()` - Recent counters
- `func_get_counters_specific_month()` - Monthly counters
- `func_count_status_changes()` - Status change counting
- Called by: Application code (analytics)

### 6.9 LTV Management (3 functions)
- `update_customer_ltv()` - Automatic LTV updates (trigger)
- `recalculate_customer_ltv()` - Manual LTV recalculation
- `recalculate_all_ltv_for_inbox()` - Batch LTV recalculation
- Called by: 1 trigger + application code (admin functions)

---

## 7. EXECUTION FLOW: KEY WORKFLOWS

### 7.1 Customer Registration Flow
```
Customer Insert → [trg_generate_client_id] → func_generate_friendly_client_id()
                ↓
              Record saved with CT{N} ID
                ↓
              [trigger_update_timestamp] → update_updated_at_column()
```

### 7.2 Appointment Creation & Status Updates
```
Service Insert → [trg_generate_service_id] → func_generate_friendly_service_id()
              ↓
              [trg_set_status_timestamp] → func_set_status_timestamp()
              ↓
              [trg_update_appointment_status_counter] → func_update_appointment_status_counter()
              ↓
              [trigger_update_timestamp] → update_updated_at_column()
              
When Status = 'Completed':
              ↓
              [trigger_update_customer_ltv] → update_customer_ltv()
              ↓
              Updates: total_spent_cents, total_completed_appointments, 
                       first_purchase_at, last_purchase_at
```

### 7.3 Form Completion Tracking
```
Any Level-3 Table Update → [trg_check_form_complete_*]
                          ↓
                    func_update_form_counter()
                          ↓
                    Validates form based on required_data_form JSON
                          ↓
                    Updates form_count in 0b_inbox_counters
                    Updates is_form_complete flag in 3a_customer_root_record
```

### 7.4 Message Creation
```
Message Insert → [trg_auto_populate_message] → func_auto_populate_message_fields()
              ↓
              If internal message: func_generate_ulid()
              ↓
              Convert content to tsvector for full-text search
              ↓
              [trigger_update_timestamp] → update_updated_at_column()
```

---

## 8. SUMMARY STATISTICS

### Functions by Category
- **System/Core**: 12 functions
- **Billing/Revenue**: 6 functions
- **Analytics/Counters**: 4 functions
- **LTV Management**: 3 functions
- **Total**: 25 functions

### Triggers by Type
- **Synchronization**: 1 trigger
- **ID Generation**: 2 triggers
- **Timestamp Management**: 1 trigger (dynamic, applied to 10+ tables)
- **Primary Marking**: 3 triggers
- **Message Automation**: 1 trigger
- **Form Validation**: 9 triggers
- **Status Management**: 2 triggers
- **LTV Updates**: 1 trigger
- **Total**: 20 triggers

### Code Distribution
| File Type | Count | Total Size | Avg Size |
|---|---|---|---|
| Function Definition Files | 3 | 165 KB | 55 KB |
| Trigger Definition Files | 2 | 54 KB | 27 KB |
| Schema Files | 1 | 26 KB | 26 KB |
| Test Files | 5 | 79 KB | 16 KB |
| **TOTAL** | **11** | **324 KB** | **29 KB** |

---

## 9. KEY OBSERVATIONS

### Strengths
1. **Well-documented**: Extensive comments and documentation in Spanish/Portuguese
2. **Modular organization**: Functions separated by responsibility into dedicated files
3. **Clear naming conventions**: Functions prefixed with purpose (get_, func_, trg_)
4. **Atomic operations**: UPSERT operations ensure data consistency
5. **Automated workflows**: Extensive use of triggers for automatic updates
6. **Scalable design**: Dynamic triggers that adapt to schema changes

### Design Patterns Used
1. **Trigger + Function Pattern**: Triggers call dedicated functions for logic separation
2. **Automatic Timestamp Management**: All tables auto-update `updated_at`
3. **Counter Pattern**: Maintains denormalized counters for performance
4. **JSONB Configuration**: Uses JSON for flexible configuration (form requirements)
5. **Dynamic SQL**: Uses `information_schema` for dynamic trigger creation

### Data Flow
```
Webhooks → func_upsert_contact_from_webhook()
        ↓
    [Triggers Fire on Insert/Update]
        ↓
    [Functions update related tables]
        ↓
    [Counters and timestamps auto-updated]
        ↓
    [Analytics queries can aggregate via get_* functions]
```

---

## 10. FILE LOCATIONS - COMPLETE REFERENCE

### Core Database Functions
- **Path**: `/home/user/AGES/functions.SQL`
- **Size**: 112 KB
- **Lines**: ~1,700
- **Functions**: 12 core system functions

### Main Triggers
- **Path**: `/home/user/AGES/triggers.SQL`
- **Size**: 37 KB
- **Lines**: 457
- **Triggers**: 18 named triggers + 1 dynamic trigger

### LTV Management
- **Path**: `/home/user/AGES/trigger_update_customer_ltv.sql`
- **Size**: 17 KB
- **Lines**: 299
- **Functions**: 3 (update_customer_ltv, recalculate_customer_ltv, recalculate_all_ltv_for_inbox)
- **Triggers**: 1 (trigger_update_customer_ltv)

### Billing Metrics
- **Path**: `/home/user/AGES/functions_billing_metrics.sql`
- **Size**: 30 KB
- **Lines**: 446
- **Functions**: 6 (billing queries and LTV queries)

### Time-Based Counters
- **Path**: `/home/user/AGES/functions_time_based_counters.sql`
- **Size**: 23 KB
- **Lines**: 305
- **Functions**: 4 (appointment counter queries)

### Schema Definition
- **Path**: `/home/user/AGES/schema.sql`
- **Size**: 26 KB
- **Lines**: 511
- **Content**: Table definitions and constraints

### Test Files
- **Path**: `/home/user/AGES/test_*.sql`
- **Count**: 5 test files
- **Total Size**: 79 KB
- **Purpose**: Unit tests for functions and triggers

