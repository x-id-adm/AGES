-- =================================================================================================
-- TESTES: MÉTRICAS DE FATURAMENTO E LTV
-- =================================================================================================
-- DESCRIÇÃO:
--   Script de testes para validar todas as funcionalidades de faturamento.
--   Testa:
--     - Funções de faturamento por tempo
--     - Funções de LTV por cliente
--     - Trigger de atualização automática de LTV
--     - Views de resumo
--
-- COMO EXECUTAR:
--   1. Certifique-se de que o schema principal está criado (schema.sql)
--   2. Execute: schema_billing_ltv.sql
--   3. Execute: functions_billing_metrics.sql
--   4. Execute: trigger_update_customer_ltv.sql
--   5. Execute este arquivo: test_billing_metrics.sql
--
-- VERSÃO: 1.0
-- DATA: 2025-11-15
-- =================================================================================================

BEGIN;

-- =================================================================================================
-- PREPARAÇÃO: Criação de dados de teste
-- =================================================================================================

-- Limpar dados de teste anteriores (se existirem)
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

-- Criar inbox de teste
INSERT INTO "0a_inbox_whatsapp" (
    inbox_id, status_workflow, inbox_name, owner_wallet_id
) VALUES (
    '00000000-0000-0000-0000-000000000001',
    '🟢',
    'TEST_BILLING_INBOX',
    '00000000-0000-0000-0000-000000000099'
);

-- Criar contador da inbox
INSERT INTO "0b_inbox_counters" (inbox_id) VALUES (
    '00000000-0000-0000-0000-000000000001'
);

-- Criar contatos de teste
INSERT INTO "1a_whatsapp_user_contact" (
    wallet_id, inbox_id, push_name, phone_number
) VALUES
    ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001', 'Cliente 1', '+5511999990001'),
    ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000001', 'Cliente 2', '+5511999990002'),
    ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000001', 'Cliente 3', '+5511999990003');

-- Criar fichas de clientes
INSERT INTO "3a_customer_root_record" (
    id, client_id, inbox_id, treatment_name, legal_name_complete, whatsapp_owner
) VALUES
    (1001, 'CT1001', '00000000-0000-0000-0000-000000000001', 'João Silva', 'João Silva Santos', '+5511999990001'),
    (1002, 'CT1002', '00000000-0000-0000-0000-000000000001', 'Maria Oliveira', 'Maria Oliveira Lima', '+5511999990002'),
    (1003, 'CT1003', '00000000-0000-0000-0000-000000000001', 'Pedro Santos', 'Pedro Santos Costa', '+5511999990003');

-- =================================================================================================
-- TESTE 1: Trigger de LTV - INSERT direto com status Completed
-- =================================================================================================

\echo ''
\echo '===================================================================================='
\echo 'TESTE 1: Trigger de LTV - INSERT com status Completed'
\echo '===================================================================================='

-- Inserir atendimento já completado (trigger deve atualizar LTV automaticamente)
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
    1001,  -- João Silva
    '2025-01-15 10:00:00'::TIMESTAMPTZ,
    '2025-01-15 11:00:00'::TIMESTAMPTZ,
    'Completed',
    20000,  -- R$ 200.00
    '2025-01-15 11:00:00'::TIMESTAMPTZ,
    '2025-01-15 09:00:00'::TIMESTAMPTZ
);

-- Verificar se o LTV foi atualizado
\echo 'Verificando LTV de João Silva (deve ter R$ 200.00):'
SELECT
    treatment_name,
    total_spent_cents,
    total_spent_cents / 100.0 as total_spent_reais,
    total_completed_appointments,
    first_purchase_at,
    last_purchase_at
FROM "3a_customer_root_record"
WHERE id = 1001;

-- =================================================================================================
-- TESTE 2: Trigger de LTV - UPDATE de status para Completed
-- =================================================================================================

\echo ''
\echo '===================================================================================='
\echo 'TESTE 2: Trigger de LTV - UPDATE de status para Completed'
\echo '===================================================================================='

-- Inserir atendimento com status Scheduled
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
    1001,  -- João Silva (novamente)
    '2025-02-10 14:00:00'::TIMESTAMPTZ,
    '2025-02-10 15:00:00'::TIMESTAMPTZ,
    'Scheduled',
    25000,  -- R$ 250.00
    '2025-02-01 10:00:00'::TIMESTAMPTZ,
    '2025-02-01 10:00:00'::TIMESTAMPTZ
);

\echo 'LTV de João Silva ANTES de completar o atendimento (deve ter R$ 200.00):'
SELECT
    treatment_name,
    total_spent_cents / 100.0 as total_spent_reais,
    total_completed_appointments
FROM "3a_customer_root_record"
WHERE id = 1001;

-- Atualizar status para Completed
UPDATE "4a_customer_service_history"
SET
    service_status = 'Completed',
    completed_at = '2025-02-10 15:00:00'::TIMESTAMPTZ,
    updated_at = '2025-02-10 15:00:00'::TIMESTAMPTZ
WHERE service_id = 'AT002';

\echo 'LTV de João Silva DEPOIS de completar o atendimento (deve ter R$ 450.00):'
SELECT
    treatment_name,
    total_spent_cents / 100.0 as total_spent_reais,
    total_completed_appointments,
    first_purchase_at,
    last_purchase_at
FROM "3a_customer_root_record"
WHERE id = 1001;

-- =================================================================================================
-- TESTE 3: Múltiplos clientes com múltiplos atendimentos
-- =================================================================================================

\echo ''
\echo '===================================================================================='
\echo 'TESTE 3: Múltiplos clientes com múltiplos atendimentos'
\echo '===================================================================================='

-- Cliente 2: Maria Oliveira - 3 atendimentos completados
INSERT INTO "4a_customer_service_history" (
    service_id, inbox_id, root_id, service_datetime_start, service_datetime_end,
    service_status, value_cents, completed_at, created_at
) VALUES
    ('AT003', '00000000-0000-0000-0000-000000000001', 1002, '2025-01-05 10:00:00'::TIMESTAMPTZ, '2025-01-05 11:00:00'::TIMESTAMPTZ, 'Completed', 15000, '2025-01-05 11:00:00'::TIMESTAMPTZ, '2025-01-05 09:00:00'::TIMESTAMPTZ),
    ('AT004', '00000000-0000-0000-0000-000000000001', 1002, '2025-02-12 14:00:00'::TIMESTAMPTZ, '2025-02-12 15:00:00'::TIMESTAMPTZ, 'Completed', 15000, '2025-02-12 15:00:00'::TIMESTAMPTZ, '2025-02-12 13:00:00'::TIMESTAMPTZ),
    ('AT005', '00000000-0000-0000-0000-000000000001', 1002, '2025-11-01 09:00:00'::TIMESTAMPTZ, '2025-11-01 10:00:00'::TIMESTAMPTZ, 'Completed', 15000, '2025-11-01 10:00:00'::TIMESTAMPTZ, '2025-11-01 08:00:00'::TIMESTAMPTZ);

-- Cliente 3: Pedro Santos - 1 atendimento completado
INSERT INTO "4a_customer_service_history" (
    service_id, inbox_id, root_id, service_datetime_start, service_datetime_end,
    service_status, value_cents, completed_at, created_at
) VALUES
    ('AT006', '00000000-0000-0000-0000-000000000001', 1003, '2025-10-20 16:00:00'::TIMESTAMPTZ, '2025-10-20 17:00:00'::TIMESTAMPTZ, 'Completed', 30000, '2025-10-20 17:00:00'::TIMESTAMPTZ, '2025-10-20 15:00:00'::TIMESTAMPTZ);

\echo 'Resumo de LTV de todos os clientes:'
SELECT
    treatment_name,
    total_spent_cents / 100.0 as total_spent_reais,
    total_completed_appointments,
    (total_spent_cents / total_completed_appointments) / 100.0 as avg_ticket_reais,
    first_purchase_at,
    last_purchase_at
FROM "3a_customer_root_record"
WHERE inbox_id = '00000000-0000-0000-0000-000000000001'
ORDER BY total_spent_cents DESC;

-- =================================================================================================
-- TESTE 4: Funções de Faturamento por Tempo
-- =================================================================================================

\echo ''
\echo '===================================================================================='
\echo 'TESTE 4: Funções de Faturamento por Tempo'
\echo '===================================================================================='

-- Faturamento de Janeiro de 2025
\echo 'Faturamento de Janeiro de 2025 (deve ser R$ 350.00):'
SELECT func_get_billing_specific_month(
    '00000000-0000-0000-0000-000000000001',
    2025,
    1
);

-- Faturamento de Fevereiro de 2025
\echo 'Faturamento de Fevereiro de 2025 (deve ser R$ 400.00):'
SELECT func_get_billing_specific_month(
    '00000000-0000-0000-0000-000000000001',
    2025,
    2
);

-- Faturamento dos últimos 30 dias (a partir de hoje)
\echo 'Faturamento dos últimos 30 dias:'
SELECT func_get_billing_last_n_days(
    '00000000-0000-0000-0000-000000000001',
    30
);

-- Faturamento dos últimos 365 dias (todo ano de 2025)
\echo 'Faturamento dos últimos 365 dias:'
SELECT func_get_billing_last_n_days(
    '00000000-0000-0000-0000-000000000001',
    365
);

-- =================================================================================================
-- TESTE 5: Funções de LTV por Cliente
-- =================================================================================================

\echo ''
\echo '===================================================================================='
\echo 'TESTE 5: Funções de LTV por Cliente'
\echo '===================================================================================='

-- LTV de João Silva (root_id 1001)
\echo 'LTV de João Silva:'
SELECT func_get_customer_ltv(1001);

-- LTV de Maria Oliveira (root_id 1002)
\echo 'LTV de Maria Oliveira:'
SELECT func_get_customer_ltv(1002);

-- Top 3 clientes por LTV
\echo 'Top 3 clientes por LTV:'
SELECT func_get_top_customers_by_ltv(
    '00000000-0000-0000-0000-000000000001',
    3
);

-- =================================================================================================
-- TESTE 6: View de Resumo de Faturamento
-- =================================================================================================

\echo ''
\echo '===================================================================================='
\echo 'TESTE 6: View de Resumo de Faturamento'
\echo '===================================================================================='

\echo 'Resumo consolidado via VIEW:'
SELECT
    root_id,
    client_id,
    treatment_name,
    total_spent_reais,
    total_completed_appointments,
    average_ticket_reais,
    customer_lifetime_days,
    first_purchase_at,
    last_purchase_at
FROM vw_customer_billing_summary
WHERE inbox_id = '00000000-0000-0000-0000-000000000001'
ORDER BY total_spent_cents DESC;

-- =================================================================================================
-- TESTE 7: Função de Recálculo de LTV
-- =================================================================================================

\echo ''
\echo '===================================================================================='
\echo 'TESTE 7: Função de Recálculo de LTV'
\echo '===================================================================================='

-- Zerar manualmente o LTV de João Silva para testar recálculo
UPDATE "3a_customer_root_record"
SET
    total_spent_cents = 0,
    total_completed_appointments = 0,
    first_purchase_at = NULL,
    last_purchase_at = NULL
WHERE id = 1001;

\echo 'LTV de João Silva ANTES do recálculo (zerado manualmente):'
SELECT
    treatment_name,
    total_spent_cents / 100.0 as total_spent_reais,
    total_completed_appointments
FROM "3a_customer_root_record"
WHERE id = 1001;

-- Recalcular LTV
\echo 'Recalculando LTV de João Silva:'
SELECT func_recalculate_customer_ltv(1001);

\echo 'LTV de João Silva DEPOIS do recálculo (deve voltar a R$ 450.00):'
SELECT
    treatment_name,
    total_spent_cents / 100.0 as total_spent_reais,
    total_completed_appointments,
    first_purchase_at,
    last_purchase_at
FROM "3a_customer_root_record"
WHERE id = 1001;

-- =================================================================================================
-- TESTE 8: Recálculo em massa de toda a inbox
-- =================================================================================================

\echo ''
\echo '===================================================================================='
\echo 'TESTE 8: Recálculo em massa de toda a inbox'
\echo '===================================================================================='

\echo 'Recalculando LTV de todos os clientes da inbox:'
SELECT func_recalculate_all_ltv_for_inbox('00000000-0000-0000-0000-000000000001');

-- =================================================================================================
-- TESTE 9: Validação de edge cases
-- =================================================================================================

\echo ''
\echo '===================================================================================='
\echo 'TESTE 9: Validação de Edge Cases'
\echo '===================================================================================='

-- Atendimento sem value_cents (não deve afetar LTV)
INSERT INTO "4a_customer_service_history" (
    service_id, inbox_id, root_id, service_datetime_start, service_datetime_end,
    service_status, value_cents, completed_at, created_at
) VALUES (
    'AT_NO_VALUE', '00000000-0000-0000-0000-000000000001', 1001,
    '2025-03-01 10:00:00'::TIMESTAMPTZ, '2025-03-01 11:00:00'::TIMESTAMPTZ,
    'Completed', NULL, '2025-03-01 11:00:00'::TIMESTAMPTZ, '2025-03-01 09:00:00'::TIMESTAMPTZ
);

\echo 'LTV de João Silva após inserir atendimento sem value_cents (deve permanecer R$ 450.00):'
SELECT
    treatment_name,
    total_spent_cents / 100.0 as total_spent_reais,
    total_completed_appointments
FROM "3a_customer_root_record"
WHERE id = 1001;

-- Atendimento com value_cents = 0 (não deve afetar LTV)
INSERT INTO "4a_customer_service_history" (
    service_id, inbox_id, root_id, service_datetime_start, service_datetime_end,
    service_status, value_cents, completed_at, created_at
) VALUES (
    'AT_ZERO_VALUE', '00000000-0000-0000-0000-000000000001', 1001,
    '2025-03-02 10:00:00'::TIMESTAMPTZ, '2025-03-02 11:00:00'::TIMESTAMPTZ,
    'Completed', 0, '2025-03-02 11:00:00'::TIMESTAMPTZ, '2025-03-02 09:00:00'::TIMESTAMPTZ
);

\echo 'LTV de João Silva após inserir atendimento com value_cents=0 (deve permanecer R$ 450.00):'
SELECT
    treatment_name,
    total_spent_cents / 100.0 as total_spent_reais,
    total_completed_appointments
FROM "3a_customer_root_record"
WHERE id = 1001;

-- =================================================================================================
-- TESTE 10: Verificação de que não duplica ao atualizar atendimento já Completed
-- =================================================================================================

\echo ''
\echo '===================================================================================='
\echo 'TESTE 10: Verificação de não duplicação'
\echo '===================================================================================='

\echo 'LTV de João Silva ANTES de atualizar atendimento já Completed:'
SELECT
    treatment_name,
    total_spent_cents / 100.0 as total_spent_reais,
    total_completed_appointments
FROM "3a_customer_root_record"
WHERE id = 1001;

-- Tentar atualizar um atendimento que já está como Completed (não deve duplicar)
UPDATE "4a_customer_service_history"
SET notes = 'Atualização de teste - não deve duplicar LTV'
WHERE service_id = 'AT001';  -- Já está Completed desde o início

\echo 'LTV de João Silva DEPOIS de atualizar atendimento já Completed (deve permanecer R$ 450.00):'
SELECT
    treatment_name,
    total_spent_cents / 100.0 as total_spent_reais,
    total_completed_appointments
FROM "3a_customer_root_record"
WHERE id = 1001;

-- =================================================================================================
-- RESUMO FINAL DOS TESTES
-- =================================================================================================

\echo ''
\echo '===================================================================================='
\echo 'RESUMO FINAL - TODOS OS CLIENTES'
\echo '===================================================================================='

SELECT
    cr.treatment_name,
    cr.total_spent_cents / 100.0 as total_spent_reais,
    cr.total_completed_appointments,
    (cr.total_spent_cents / NULLIF(cr.total_completed_appointments, 0)) / 100.0 as avg_ticket_reais,
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
\echo 'TESTES CONCLUÍDOS COM SUCESSO!'
\echo '===================================================================================='

ROLLBACK;  -- Desfaz todas as alterações de teste

-- =================================================================================================
-- FIM DOS TESTES
-- =================================================================================================
-- RESULTADOS ESPERADOS:
--
-- TESTE 1: João Silva deve ter R$ 200.00 após primeiro atendimento
-- TESTE 2: João Silva deve ter R$ 450.00 após segundo atendimento
-- TESTE 3: Maria Oliveira deve ter R$ 150.00 (3x R$ 50.00)
--          Pedro Santos deve ter R$ 300.00 (1x R$ 300.00)
-- TESTE 4: Janeiro/2025 = R$ 350.00, Fevereiro/2025 = R$ 400.00
-- TESTE 5: LTV individualizado para cada cliente
-- TESTE 6: View mostra todos os dados consolidados
-- TESTE 7: Recálculo restaura valores corretos
-- TESTE 8: Recálculo em massa processa todos os clientes
-- TESTE 9: Atendimentos sem valor não afetam LTV
-- TESTE 10: Atualizações de atendimentos já Completed não duplicam valores
-- =================================================================================================
