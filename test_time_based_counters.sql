-- =================================================================================================
-- TESTES: Contadores Baseados em Tempo
-- =================================================================================================
-- DESCRIÇÃO:
--   Arquivo de testes para validar as funções de contadores por período.
--   Demonstra casos de uso reais e esperados.
--
-- COMO USAR:
--   1. Execute a migration: migration_add_status_timestamps.sql
--   2. Execute as funções: functions_time_based_counters.sql
--   3. Execute este arquivo de testes
--
-- VERSÃO: 1.0
-- DATA: 2025-11-15
-- =================================================================================================

BEGIN;

-- =================================================================================================
-- SETUP: Criar dados de teste
-- =================================================================================================

-- Limpar dados de teste anteriores (se existirem)
DO $$
DECLARE
    v_test_inbox_id UUID := 'a0000000-0000-0000-0000-000000000001';
BEGIN
    DELETE FROM "4a_customer_service_history" WHERE inbox_id = v_test_inbox_id;
    DELETE FROM "3a_customer_root_record" WHERE inbox_id = v_test_inbox_id;
    DELETE FROM "0b_inbox_counters" WHERE inbox_id = v_test_inbox_id;
    DELETE FROM "0a_inbox_whatsapp" WHERE inbox_id = v_test_inbox_id;

    RAISE NOTICE 'Dados de teste anteriores removidos';
END $$;


-- Criar inbox de teste
INSERT INTO "0a_inbox_whatsapp" (
    inbox_id,
    client_name,
    inbox_name,
    owner_wallet_id
) VALUES (
    'a0000000-0000-0000-0000-000000000001',
    'Cliente Teste',
    'Inbox Teste',
    'b0000000-0000-0000-0000-000000000001'
) ON CONFLICT (inbox_id) DO NOTHING;


-- Criar cliente de teste
INSERT INTO "3a_customer_root_record" (
    id,
    inbox_id,
    treatment_name,
    whatsapp_owner
) VALUES (
    9999999,
    'a0000000-0000-0000-0000-000000000001',
    'Cliente de Teste',
    '+5511999999999'
) ON CONFLICT (id) DO NOTHING;


-- =================================================================================================
-- TESTE 1: Agendamentos dos últimos 7 dias
-- =================================================================================================
\echo ''
\echo '========================================='
\echo 'TESTE 1: Agendamentos dos últimos 7 dias'
\echo '========================================='

-- Inserir agendamentos de teste com datas variadas
INSERT INTO "4a_customer_service_history" (
    inbox_id,
    root_id,
    service_datetime_start,
    service_datetime_end,
    service_status,
    created_at
) VALUES
    -- Há 2 dias - Scheduled
    ('a0000000-0000-0000-0000-000000000001', 9999999, NOW() + INTERVAL '1 day', NOW() + INTERVAL '1 day 1 hour', 'Scheduled', NOW() - INTERVAL '2 days'),
    -- Há 3 dias - Confirmed
    ('a0000000-0000-0000-0000-000000000001', 9999999, NOW() + INTERVAL '2 days', NOW() + INTERVAL '2 days 1 hour', 'Confirmed', NOW() - INTERVAL '3 days'),
    -- Há 5 dias - Completed
    ('a0000000-0000-0000-0000-000000000001', 9999999, NOW() - INTERVAL '5 days', NOW() - INTERVAL '5 days' + INTERVAL '1 hour', 'Completed', NOW() - INTERVAL '5 days'),
    -- Há 6 dias - Cancelled
    ('a0000000-0000-0000-0000-000000000001', 9999999, NOW() + INTERVAL '3 days', NOW() + INTERVAL '3 days 1 hour', 'Cancelled', NOW() - INTERVAL '6 days'),
    -- Há 10 dias - Não deve aparecer (fora do período)
    ('a0000000-0000-0000-0000-000000000001', 9999999, NOW() - INTERVAL '10 days', NOW() - INTERVAL '10 days' + INTERVAL '1 hour', 'Completed', NOW() - INTERVAL '10 days');

-- Consultar últimos 7 dias
SELECT func_get_counters_last_n_days('a0000000-0000-0000-0000-000000000001', 7) AS resultado;

\echo 'Esperado: total_appointments: 4 (não deve contar o de 10 dias atrás)'
\echo 'scheduled_count: 1, confirmed_count: 1, completed_count: 1, cancelled_count: 1'


-- =================================================================================================
-- TESTE 2: Agendamentos de um mês específico (Janeiro 2025)
-- =================================================================================================
\echo ''
\echo '================================================='
\echo 'TESTE 2: Agendamentos de Janeiro 2025'
\echo '================================================='

-- Inserir agendamentos em Janeiro
INSERT INTO "4a_customer_service_history" (
    inbox_id,
    root_id,
    service_datetime_start,
    service_datetime_end,
    service_status,
    created_at
) VALUES
    -- 05/Janeiro/2025
    ('a0000000-0000-0000-0000-000000000001', 9999999, '2025-01-05 10:00:00', '2025-01-05 11:00:00', 'Scheduled', '2025-01-05 09:00:00'),
    -- 15/Janeiro/2025
    ('a0000000-0000-0000-0000-000000000001', 9999999, '2025-01-15 14:00:00', '2025-01-15 15:00:00', 'Confirmed', '2025-01-15 10:00:00'),
    -- 20/Janeiro/2025
    ('a0000000-0000-0000-0000-000000000001', 9999999, '2025-01-20 16:00:00', '2025-01-20 17:00:00', 'Completed', '2025-01-20 18:00:00'),
    -- 25/Janeiro/2025
    ('a0000000-0000-0000-0000-000000000001', 9999999, '2025-01-25 09:00:00', '2025-01-25 10:00:00', 'Cancelled', '2025-01-25 08:00:00'),
    -- 05/Fevereiro/2025 - Não deve aparecer
    ('a0000000-0000-0000-0000-000000000001', 9999999, '2025-02-05 10:00:00', '2025-02-05 11:00:00', 'Scheduled', '2025-02-05 09:00:00');

-- Consultar Janeiro 2025
SELECT func_get_counters_specific_month('a0000000-0000-0000-0000-000000000001', 2025, 1) AS resultado;

\echo 'Esperado: total_appointments: 4 (não deve contar Fevereiro)'
\echo 'scheduled_count: 1, confirmed_count: 1, completed_count: 1, cancelled_count: 1'


-- =================================================================================================
-- TESTE 3: Contagem específica por status
-- =================================================================================================
\echo ''
\echo '================================================='
\echo 'TESTE 3: Quantos cancelaram nos últimos 30 dias?'
\echo '================================================='

-- Inserir mais cancelamentos
INSERT INTO "4a_customer_service_history" (
    inbox_id,
    root_id,
    service_datetime_start,
    service_datetime_end,
    service_status,
    created_at
) VALUES
    -- Há 10 dias - Cancelled
    ('a0000000-0000-0000-0000-000000000001', 9999999, NOW() + INTERVAL '5 days', NOW() + INTERVAL '5 days 1 hour', 'Cancelled', NOW() - INTERVAL '10 days'),
    -- Há 15 dias - Cancelled
    ('a0000000-0000-0000-0000-000000000001', 9999999, NOW() + INTERVAL '6 days', NOW() + INTERVAL '6 days 1 hour', 'Cancelled', NOW() - INTERVAL '15 days'),
    -- Há 20 dias - Cancelled
    ('a0000000-0000-0000-0000-000000000001', 9999999, NOW() + INTERVAL '7 days', NOW() + INTERVAL '7 days 1 hour', 'Cancelled', NOW() - INTERVAL '20 days');

-- Contar cancelamentos dos últimos 30 dias
SELECT func_count_status_changes(
    'a0000000-0000-0000-0000-000000000001',
    'Cancelled',
    NOW() - INTERVAL '30 days',
    NOW()
) AS cancelamentos_ultimos_30_dias;

\echo 'Esperado: 4 cancelamentos (6 dias + 10 dias + 15 dias + 20 dias atrás)'


-- =================================================================================================
-- TESTE 4: Mudança de status ao longo do tempo
-- =================================================================================================
\echo ''
\echo '==========================================================='
\echo 'TESTE 4: Agendamento que mudou de status (histórico completo)'
\echo '==========================================================='

-- Inserir um agendamento e simular mudanças de status
DO $$
DECLARE
    v_service_id BIGINT;
BEGIN
    -- 1. Criar agendamento inicial (Scheduled)
    INSERT INTO "4a_customer_service_history" (
        inbox_id,
        root_id,
        service_datetime_start,
        service_datetime_end,
        service_status,
        created_at
    ) VALUES (
        'a0000000-0000-0000-0000-000000000001',
        9999999,
        NOW() + INTERVAL '7 days',
        NOW() + INTERVAL '7 days 1 hour',
        'Scheduled',
        NOW() - INTERVAL '7 days'
    ) RETURNING id INTO v_service_id;

    RAISE NOTICE 'Agendamento criado: ID=%', v_service_id;

    -- 2. Simular mudança para Confirmed (5 dias atrás)
    UPDATE "4a_customer_service_history"
    SET service_status = 'Confirmed',
        updated_at = NOW() - INTERVAL '5 days'
    WHERE id = v_service_id;

    -- Forçar atualização do timestamp (normalmente feito pelo trigger)
    UPDATE "4a_customer_service_history"
    SET confirmed_at = NOW() - INTERVAL '5 days'
    WHERE id = v_service_id;

    RAISE NOTICE 'Status mudado para Confirmed há 5 dias';

    -- 3. Simular mudança para Cancelled (2 dias atrás)
    UPDATE "4a_customer_service_history"
    SET service_status = 'Cancelled',
        updated_at = NOW() - INTERVAL '2 days'
    WHERE id = v_service_id;

    -- Forçar atualização do timestamp
    UPDATE "4a_customer_service_history"
    SET cancelled_at = NOW() - INTERVAL '2 days'
    WHERE id = v_service_id;

    RAISE NOTICE 'Status mudado para Cancelled há 2 dias';

    -- Mostrar timeline completa
    RAISE NOTICE '';
    RAISE NOTICE '=== TIMELINE DO AGENDAMENTO ===';

    -- Buscar e exibir
    PERFORM
        CASE
            WHEN scheduled_at IS NOT NULL THEN RAISE NOTICE '✓ Agendado em: %', scheduled_at;
            ELSE NULL
        END,
        CASE
            WHEN confirmed_at IS NOT NULL THEN RAISE NOTICE '✓ Confirmado em: %', confirmed_at;
            ELSE NULL
        END,
        CASE
            WHEN cancelled_at IS NOT NULL THEN RAISE NOTICE '✗ Cancelado em: %', cancelled_at;
            ELSE NULL
        END
    FROM "4a_customer_service_history"
    WHERE id = v_service_id;
END $$;


-- =================================================================================================
-- TESTE 5: View de timeline
-- =================================================================================================
\echo ''
\echo '================================================='
\echo 'TESTE 5: Visualizar timeline de todos agendamentos'
\echo '================================================='

SELECT
    service_id,
    service_status,
    scheduled_at,
    confirmed_at,
    completed_at,
    cancelled_at,
    rescheduled_at,
    no_show_at
FROM vw_appointment_status_timeline
WHERE inbox_id = 'a0000000-0000-0000-0000-000000000001'
ORDER BY created_at DESC
LIMIT 10;


-- =================================================================================================
-- TESTE 6: Queries avançadas com múltiplos filtros
-- =================================================================================================
\echo ''
\echo '================================================='
\echo 'TESTE 6: Queries avançadas'
\echo '================================================='

-- Quantos agendamentos foram confirmados E completados em Janeiro 2025?
\echo '6.1) Agendamentos confirmados E completados em Janeiro 2025:'
SELECT COUNT(*) AS count_confirmados_e_completados
FROM "4a_customer_service_history"
WHERE inbox_id = 'a0000000-0000-0000-0000-000000000001'
  AND confirmed_at >= '2025-01-01'
  AND confirmed_at < '2025-02-01'
  AND completed_at >= '2025-01-01'
  AND completed_at < '2025-02-01';

-- Taxa de cancelamento dos últimos 30 dias
\echo ''
\echo '6.2) Taxa de cancelamento dos últimos 30 dias:'
SELECT
    COUNT(*) FILTER (WHERE cancelled_at >= NOW() - INTERVAL '30 days') AS cancelados,
    COUNT(*) AS total,
    ROUND(
        COUNT(*) FILTER (WHERE cancelled_at >= NOW() - INTERVAL '30 days')::DECIMAL / NULLIF(COUNT(*), 0) * 100,
        2
    ) AS taxa_cancelamento_pct
FROM "4a_customer_service_history"
WHERE inbox_id = 'a0000000-0000-0000-0000-000000000001'
  AND created_at >= NOW() - INTERVAL '30 days';

-- Top 5 dias com mais agendamentos
\echo ''
\echo '6.3) Top 5 dias com mais agendamentos criados:'
SELECT
    DATE(created_at) AS dia,
    COUNT(*) AS total_agendamentos,
    COUNT(*) FILTER (WHERE service_status = 'Scheduled') AS scheduled,
    COUNT(*) FILTER (WHERE service_status = 'Confirmed') AS confirmed,
    COUNT(*) FILTER (WHERE service_status = 'Cancelled') AS cancelled
FROM "4a_customer_service_history"
WHERE inbox_id = 'a0000000-0000-0000-0000-000000000001'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY DATE(created_at)
ORDER BY total_agendamentos DESC
LIMIT 5;


-- =================================================================================================
-- LIMPEZA (OPCIONAL)
-- =================================================================================================
\echo ''
\echo '================================================='
\echo 'TESTES CONCLUÍDOS!'
\echo '================================================='
\echo ''
\echo 'Para limpar dados de teste, execute:'
\echo "  DELETE FROM 4a_customer_service_history WHERE inbox_id = 'a0000000-0000-0000-0000-000000000001';"
\echo "  DELETE FROM 3a_customer_root_record WHERE inbox_id = 'a0000000-0000-0000-0000-000000000001';"
\echo "  DELETE FROM 0b_inbox_counters WHERE inbox_id = 'a0000000-0000-0000-0000-000000000001';"
\echo "  DELETE FROM 0a_inbox_whatsapp WHERE inbox_id = 'a0000000-0000-0000-0000-000000000001';"
\echo ''

COMMIT;

-- =================================================================================================
-- FIM DOS TESTES
-- =================================================================================================
