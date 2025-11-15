# AGES PostgreSQL Functions & Triggers - Documentation Index

This directory contains comprehensive documentation of all PostgreSQL functions and triggers in the AGES project.

## Documentation Files

### 1. **FUNCTIONS_AND_TRIGGERS_CATALOG.md** (23 KB)
Comprehensive reference catalog with all details.

**Contents:**
- Executive summary with statistics
- Complete file organization structure
- All 25 functions listed with:
  - Function name and location
  - Line number in source file
  - Purpose and description
- All 20 triggers listed with:
  - Trigger name and location
  - Target table
  - Event type (BEFORE/AFTER INSERT/UPDATE)
  - Associated function
  - Purpose and behavior
- Function-to-trigger mapping
- Table-to-trigger mapping
- Functions organized by category/responsibility
- Key workflows and execution flows
- Design patterns used
- Key observations and strengths

**Use this document when you need:**
- Complete details on any function or trigger
- Understanding of how components interact
- Design pattern analysis
- Full context and documentation

---

### 2. **FUNCTIONS_AND_TRIGGERS_REFERENCE.txt** (11 KB)
Quick reference guide for fast lookup.

**Contents:**
- Quick statistics
- Function quick lookup organized by filename
- Trigger quick lookup organized by type
- Most used functions
- Key table trigger summary
- Execution workflows overview
- Frequently called reporting functions
- Functions not called by triggers
- File organization summary
- Key design patterns
- Important notes

**Use this document when you need:**
- Quick lookup of a function or trigger
- Fast reference during development
- Understanding of usage patterns
- Overview of the system architecture

---

### 3. **TRIGGER_FUNCTION_RELATIONSHIPS.txt** (16 KB)
Visual diagram showing how triggers call functions.

**Contents:**
- Trigger-to-function mapping by layer:
  - Synchronization layer
  - ID generation layer
  - Timestamp management layer (dynamic)
  - Primary marking layer
  - Message automation layer
  - Form completion validation layer
  - Appointment status management layer
  - LTV calculation layer
  - Reporting & analytics layer
  - Webhook integration layer
- Function call dependency tree
- Detailed explanation of each trigger-function relationship
- Execution order and effects
- Logic flow for complex triggers

**Use this document when you need:**
- Understand trigger execution flow
- See which functions are called by which triggers
- Understand dependencies between components
- Visual representation of the system

---

## Quick Navigation

### Looking for a specific function?
1. Go to **FUNCTIONS_AND_TRIGGERS_REFERENCE.txt**
2. Use Ctrl+F to search for the function name
3. It will show the filename and line number
4. For full details, see **FUNCTIONS_AND_TRIGGERS_CATALOG.md**

### Want to understand a trigger?
1. Go to **TRIGGER_FUNCTION_RELATIONSHIPS.txt**
2. Search for the trigger name
3. See what function it calls and what it does
4. For complete details, see **FUNCTIONS_AND_TRIGGERS_CATALOG.md**

### Need to trace data flow?
1. Start in **TRIGGER_FUNCTION_RELATIONSHIPS.txt**
2. Look at the "Function Call Dependency Tree" section
3. Follow the execution path through workflows
4. Use **FUNCTIONS_AND_TRIGGERS_CATALOG.md** for detailed logic

### Working on a specific table?
1. Go to **FUNCTIONS_AND_TRIGGERS_CATALOG.md**
2. Find "Table-to-Trigger Mapping" section
3. See all triggers that fire on your table
4. Use **TRIGGER_FUNCTION_RELATIONSHIPS.txt** for execution details

---

## Quick Statistics

- **Total Functions**: 25
- **Total Triggers**: 20 (19 named + 1 dynamic)
- **Total SQL Files**: 11
- **Total Lines of SQL Code**: 5,610
- **Project Size**: 362 KB

### Functions by Category
- System/Core: 12 functions
- Billing/Revenue: 6 functions
- Analytics/Counters: 4 functions
- LTV Management: 3 functions

### Triggers by Type
- Synchronization: 1
- ID Generation: 2
- Timestamp Management: 1 dynamic (applied to 10+ tables)
- Primary Marking: 3
- Message Automation: 1
- Form Validation: 9
- Status Management: 2
- LTV Updates: 1

---

## File Locations

### Function Definition Files
- `/home/user/AGES/functions.SQL` (112 KB) - Core system functions
- `/home/user/AGES/functions_billing_metrics.sql` (30 KB) - Billing functions
- `/home/user/AGES/functions_time_based_counters.sql` (23 KB) - Analytics functions

### Trigger Definition Files
- `/home/user/AGES/triggers.SQL` (37 KB) - Main triggers
- `/home/user/AGES/trigger_update_customer_ltv.sql` (17 KB) - LTV triggers

### Schema & Configuration
- `/home/user/AGES/schema.sql` (26 KB) - Table definitions

### Test Files
- `/home/user/AGES/test_*.sql` (5 files, 79 KB total) - Unit tests

---

## Key Concepts

### Trigger + Function Pattern
Each trigger is defined separately from its logic function, allowing:
- Clean separation of concerns
- Reusable functions across multiple triggers
- Easier maintenance and testing

**Example:**
```
Trigger: trg_generate_client_id
Function: func_generate_friendly_client_id()
```

### Dynamic Triggers
The `trigger_update_timestamp` is created DYNAMICALLY for every table with an `updated_at` column:
- Not a single static trigger
- Applied to 10+ tables automatically
- Automatically applies to new tables if they add `updated_at` column

### Reusable Functions
Some functions are used by multiple triggers:
- `func_update_form_counter()` - Used by 9 different triggers
- `func_ensure_first_is_primary()` - Used by 3 different triggers
- `update_updated_at_column()` - Used by dynamic trigger on all tables

### Automatic vs. Manual Functions
- **Automatic** (called by triggers):
  - ID generation
  - Timestamp updates
  - Form validation
  - Status tracking
  - LTV calculation
  
- **Manual** (called from application code):
  - Webhook integration
  - Reporting and analytics
  - Admin operations (LTV recalculation)

---

## Data Flow Overview

```
┌─────────────────┐
│  External Data  │
│   (Webhooks)    │
└────────┬────────┘
         │
         v
┌─────────────────────────────────┐
│ func_upsert_contact_from_webhook │ [Manual call]
└────────┬────────────────────────┘
         │
         v
┌─────────────────────────────────┐
│   Database Triggers Fire        │ [Automatic]
│  (Insert/Update Operations)     │
└────────┬────────────────────────┘
         │
         ├─> [ID Generation Triggers]
         │   └─> Generate CT{N}, AT{N} IDs
         │
         ├─> [Status Management Triggers]
         │   └─> Set timestamps, update counters
         │
         ├─> [Form Validation Triggers]
         │   └─> Check form completeness
         │
         ├─> [LTV Triggers]
         │   └─> Update customer lifetime value
         │
         └─> [Timestamp Triggers]
             └─> Auto-update 'updated_at'
         
         v
┌─────────────────────────────────┐
│  Application Reporting Queries  │ [Manual call]
│  (Analytics, Billing, etc.)     │
└─────────────────────────────────┘
```

---

## Usage Examples

### Find functions used by a specific trigger
1. Open **FUNCTIONS_AND_TRIGGERS_CATALOG.md**
2. Search for the trigger name in section "3. ALL POSTGRESQL TRIGGERS"
3. The "Function" column shows which function it calls

### Find all triggers on a specific table
1. Open **FUNCTIONS_AND_TRIGGERS_CATALOG.md**
2. Go to section "5. TABLE-TO-TRIGGER MAPPING"
3. Find your table name

### Understand what happens when you insert a customer
1. Open **TRIGGER_FUNCTION_RELATIONSHIPS.txt**
2. Find "APPLICATION CODE (entry points)" section
3. Look for "INSERT 3a_customer_root_record"
4. Follow the execution flow

### Check if a function is automatic (triggered) or manual
1. Open **FUNCTIONS_AND_TRIGGERS_REFERENCE.txt**
2. Go to "MOST USED FUNCTIONS (called by triggers)" section
3. Functions listed there are automatic
4. Functions in "FUNCTIONS NOT CALLED BY TRIGGERS" are manual

---

## Document Maintenance

These documents are auto-generated based on the actual SQL code in:
- `/home/user/AGES/functions.SQL`
- `/home/user/AGES/triggers.SQL`
- `/home/user/AGES/functions_billing_metrics.sql`
- `/home/user/AGES/functions_time_based_counters.sql`
- `/home/user/AGES/trigger_update_customer_ltv.sql`

If you add new functions or triggers, please regenerate these documents to keep them in sync.

---

## Additional Resources

### Related Documentation
- `DATABASE_DOCUMENTATION.md` - Database schema details
- `MANUAL_METRICAS_FATURAMENTO.md` - Billing metrics manual
- `CONTADORES_TEMPORAIS.md` - Time-based counters documentation
- `TAXAS_CONVERSAO.md` - Conversion rates documentation

### In-Code Documentation
Each function and trigger in the SQL files has extensive inline documentation explaining:
- Purpose and behavior
- Parameters and return values
- Examples of usage
- Important notes and gotchas

---

## Quick Search Cheat Sheet

**To find:** | **Go to file:** | **Section:**
---|---|---
A specific function | FUNCTIONS_AND_TRIGGERS_REFERENCE.txt | "FUNCTION QUICK LOOKUP"
A specific trigger | FUNCTIONS_AND_TRIGGERS_REFERENCE.txt | "TRIGGER QUICK LOOKUP"
What triggers a function calls | TRIGGER_FUNCTION_RELATIONSHIPS.txt | By layer name
What functions use a trigger | FUNCTIONS_AND_TRIGGERS_CATALOG.md | "4. FUNCTION-TO-TRIGGER MAPPING"
All triggers on a table | FUNCTIONS_AND_TRIGGERS_CATALOG.md | "5. TABLE-TO-TRIGGER MAPPING"
How data flows through system | TRIGGER_FUNCTION_RELATIONSHIPS.txt | "FUNCTION CALL DEPENDENCY TREE"
Function execution order | FUNCTIONS_AND_TRIGGERS_CATALOG.md | "7. EXECUTION FLOW: KEY WORKFLOWS"
Design patterns used | FUNCTIONS_AND_TRIGGERS_CATALOG.md | "9. KEY OBSERVATIONS"

---

## Questions & Answers

**Q: How many functions are there?**
A: 25 total. 12 system/core, 6 billing, 4 analytics, 3 LTV.

**Q: How many triggers are there?**
A: 20 total. 19 named triggers + 1 dynamic trigger applied to 10+ tables.

**Q: Which function is used the most?**
A: `func_update_form_counter()` - called by 9 different triggers.

**Q: Are all functions called by triggers?**
A: No. 10 functions are called by triggers. 15 functions are called from application code (reporting, webhooks, admin operations).

**Q: Can the timestamp trigger be modified?**
A: It's created dynamically, so it adjusts automatically when tables change. Don't modify it directly.

**Q: How do I manually recalculate LTV?**
A: Use `SELECT recalculate_customer_ltv(root_id)` for a single customer or `SELECT recalculate_all_ltv_for_inbox(inbox_id)` for all customers in an inbox.

**Q: Which table has the most triggers?**
A: `4a_customer_service_history` has 5 potential triggers (generate_service_id, set_status_timestamp, update_status_counter, update_customer_ltv, update_timestamp).

---

Generated: 2025-11-15
Last Updated: 2025-11-15
