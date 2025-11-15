-- ================================================================
-- TESTES: Taxas de Conversão Automáticas
-- ================================================================
-- Data: 2025-11-15
-- Descrição: Valida o cálculo automático das taxas de conversão
--            baseadas nos contadores de status
-- ================================================================

BEGIN;

-- ================================================================
-- PREPARAÇÃO: Criar dados de teste
-- ================================================================

-- Criar inbox de teste
INSERT INTO "0a_inbox_whatsapp" (
    inbox_id,
    inbox_name,
    owner_wallet_id,
    client_name,
    status_workflow
) VALUES (
    '11111111-1111-1111-1111-111111111111'::UUID,
    'Clínica de Testes - Conversão',
    '99999999-9999-9999-9999-999999999999'::UUID,
    'Dr. Teste',
    '🟢'
) ON CONFLICT (inbox_id) DO NOTHING;

-- Criar contador de inbox (será criado automaticamente pelo trigger, mas vamos garantir)
INSERT INTO "0b_inbox_counters" (inbox_id)
VALUES ('11111111-1111-1111-1111-111111111111'::UUID)
ON CONFLICT (inbox_id) DO NOTHING;

-- Criar contato de teste
INSERT INTO "1a_whatsapp_user_contact" (
    wallet_id,
    inbox_id,
    push_name,
    phone_number
) VALUES (
    '22222222-2222-2222-2222-222222222222'::UUID,
    '11111111-1111-1111-1111-111111111111'::UUID,
    'Cliente Teste Conversão',
    '5511999998888'
) ON CONFLICT (wallet_id) DO NOTHING;

-- Criar ficha do cliente
INSERT INTO "3a_customer_root_record" (
    id,
    inbox_id,
    treatment_name,
    whatsapp_owner
) VALUES (
    999999,
    '11111111-1111-1111-1111-111111111111'::UUID,
    'Cliente Teste Conversão',
    '5511999998888'
) ON CONFLICT (id) DO NOTHING;

-- ================================================================
-- TESTE 1: Taxas com 0 agendamentos (evitar divisão por zero)
-- ================================================================

\echo ''
\echo '================================================================'
\echo 'TESTE 1: Taxas com 0 agendamentos (todas devem ser 0.0000)'
\echo '================================================================'

SELECT
    inbox_id,
    scheduled_count AS "Agendados",
    confirmed_count AS "Confirmados",
    confirmed_rate AS "Taxa Confirmação",
    completed_rate AS "Taxa Conclusão",
    cancelled_rate AS "Taxa Cancelamento",
    rescheduled_rate AS "Taxa Reagendamento",
    no_show_rate AS "Taxa No-Show"
FROM "0b_inbox_counters"
WHERE inbox_id = '11111111-1111-1111-1111-111111111111'::UUID;

-- ================================================================
-- TESTE 2: Criar 100 agendamentos e testar conversões
-- ================================================================

\echo ''
\echo '================================================================'
\echo 'TESTE 2: Criar 100 agendamentos com status Scheduled'
\echo '================================================================'

-- Inserir 100 agendamentos com status 'Scheduled'
INSERT INTO "4a_customer_service_history" (
    inbox_id,
    root_id,
    scheduled_by_wallet_id,
    service_datetime_start,
    service_datetime_end,
    service_status
)
SELECT
    '11111111-1111-1111-1111-111111111111'::UUID,
    999999,
    '22222222-2222-2222-2222-222222222222'::UUID,
    NOW() + (i || ' hours')::INTERVAL,
    NOW() + (i + 1 || ' hours')::INTERVAL,
    'Scheduled'
FROM generate_series(1, 100) AS i;

\echo ''
\echo 'Verificando contadores após 100 agendamentos:'
SELECT
    scheduled_count AS "Agendados",
    confirmed_count AS "Confirmados",
    completed_count AS "Completados",
    cancelled_count AS "Cancelados",
    rescheduled_count AS "Reagendados",
    no_show_count AS "Não Compareceu"
FROM "0b_inbox_counters"
WHERE inbox_id = '11111111-1111-1111-1111-111111111111'::UUID;

-- ================================================================
-- TESTE 3: Confirmar 85 agendamentos (85% de taxa de confirmação)
-- ================================================================

\echo ''
\echo '================================================================'
\echo 'TESTE 3: Confirmar 85 agendamentos (esperado: 85% confirmação)'
\echo '================================================================'

UPDATE "4a_customer_service_history"
SET service_status = 'Confirmed'
WHERE inbox_id = '11111111-1111-1111-1111-111111111111'::UUID
  AND service_status = 'Scheduled'
  AND id IN (
    SELECT id
    FROM "4a_customer_service_history"
    WHERE inbox_id = '11111111-1111-1111-1111-111111111111'::UUID
      AND service_status = 'Scheduled'
    LIMIT 85
);

\echo ''
\echo 'Verificando contadores e taxas:'
SELECT
    scheduled_count AS "Agendados",
    confirmed_count AS "Confirmados",
    ROUND(confirmed_rate * 100, 2) || '%' AS "Taxa Confirmação (%)",
    confirmed_rate AS "Taxa Confirmação (decimal)"
FROM "0b_inbox_counters"
WHERE inbox_id = '11111111-1111-1111-1111-111111111111'::UUID;

-- ================================================================
-- TESTE 4: Completar 75 dos confirmados (75% de taxa de conclusão)
-- ================================================================

\echo ''
\echo '================================================================'
\echo 'TESTE 4: Completar 75 agendamentos (esperado: 75% conclusão)'
\echo '================================================================'

UPDATE "4a_customer_service_history"
SET service_status = 'Completed'
WHERE inbox_id = '11111111-1111-1111-1111-111111111111'::UUID
  AND service_status = 'Confirmed'
  AND id IN (
    SELECT id
    FROM "4a_customer_service_history"
    WHERE inbox_id = '11111111-1111-1111-1111-111111111111'::UUID
      AND service_status = 'Confirmed'
    LIMIT 75
);

\echo ''
\echo 'Verificando contadores e taxas:'
SELECT
    scheduled_count AS "Agendados",
    confirmed_count AS "Confirmados",
    completed_count AS "Completados",
    ROUND(confirmed_rate * 100, 2) || '%' AS "Taxa Confirmação",
    ROUND(completed_rate * 100, 2) || '%' AS "Taxa Conclusão",
    confirmed_rate AS "Taxa Confirmação (decimal)",
    completed_rate AS "Taxa Conclusão (decimal)"
FROM "0b_inbox_counters"
WHERE inbox_id = '11111111-1111-1111-1111-111111111111'::UUID;

-- ================================================================
-- TESTE 5: Cancelar 10, Reagendar 5, No-Show 10
-- ================================================================

\echo ''
\echo '================================================================'
\echo 'TESTE 5: Cancelar 10, Reagendar 5, No-Show 10'
\echo '================================================================'

-- Cancelar 10 dos agendados restantes
UPDATE "4a_customer_service_history"
SET service_status = 'Cancelled'
WHERE inbox_id = '11111111-1111-1111-1111-111111111111'::UUID
  AND service_status = 'Scheduled'
  AND id IN (
    SELECT id
    FROM "4a_customer_service_history"
    WHERE inbox_id = '11111111-1111-1111-1111-111111111111'::UUID
      AND service_status = 'Scheduled'
    LIMIT 10
);

-- Reagendar 5 dos confirmados restantes
UPDATE "4a_customer_service_history"
SET service_status = 'Rescheduled'
WHERE inbox_id = '11111111-1111-1111-1111-111111111111'::UUID
  AND service_status = 'Confirmed'
  AND id IN (
    SELECT id
    FROM "4a_customer_service_history"
    WHERE inbox_id = '11111111-1111-1111-1111-111111111111'::UUID
      AND service_status = 'Confirmed'
    LIMIT 5
);

-- Marcar 5 dos confirmados restantes como No-Show
UPDATE "4a_customer_service_history"
SET service_status = 'No_Show'
WHERE inbox_id = '11111111-1111-1111-1111-111111111111'::UUID
  AND service_status = 'Confirmed'
  AND id IN (
    SELECT id
    FROM "4a_customer_service_history"
    WHERE inbox_id = '11111111-1111-1111-1111-111111111111'::UUID
      AND service_status = 'Confirmed'
    LIMIT 5
);

-- ================================================================
-- TESTE 6: Visualização Final com Todas as Taxas
-- ================================================================

\echo ''
\echo '================================================================'
\echo 'TESTE 6: RELATÓRIO FINAL - Todas as Taxas de Conversão'
\echo '================================================================'

SELECT
    '📊 CONTADORES ABSOLUTOS' AS "Seção";

SELECT
    scheduled_count AS "Total Agendados",
    confirmed_count AS "Confirmados",
    completed_count AS "Completados",
    cancelled_count AS "Cancelados",
    rescheduled_count AS "Reagendados",
    no_show_count AS "Não Compareceu"
FROM "0b_inbox_counters"
WHERE inbox_id = '11111111-1111-1111-1111-111111111111'::UUID;

\echo ''
SELECT
    '📈 TAXAS DE CONVERSÃO (PERCENTUAL)' AS "Seção";

SELECT
    ROUND(confirmed_rate * 100, 2) || '%' AS "Taxa Confirmação",
    ROUND(completed_rate * 100, 2) || '%' AS "Taxa Conclusão",
    ROUND(cancelled_rate * 100, 2) || '%' AS "Taxa Cancelamento",
    ROUND(rescheduled_rate * 100, 2) || '%' AS "Taxa Reagendamento",
    ROUND(no_show_rate * 100, 2) || '%' AS "Taxa No-Show"
FROM "0b_inbox_counters"
WHERE inbox_id = '11111111-1111-1111-1111-111111111111'::UUID;

\echo ''
SELECT
    '🔢 TAXAS DE CONVERSÃO (DECIMAL)' AS "Seção";

SELECT
    confirmed_rate AS "Taxa Confirmação",
    completed_rate AS "Taxa Conclusão",
    cancelled_rate AS "Taxa Cancelamento",
    rescheduled_rate AS "Taxa Reagendamento",
    no_show_rate AS "Taxa No-Show"
FROM "0b_inbox_counters"
WHERE inbox_id = '11111111-1111-1111-1111-111111111111'::UUID;

-- ================================================================
-- TESTE 7: Validação Matemática
-- ================================================================

\echo ''
\echo '================================================================'
\echo 'TESTE 7: Validação Matemática (soma deve ser próxima de 100%)'
\echo '================================================================'

SELECT
    ROUND((confirmed_rate + completed_rate + cancelled_rate + rescheduled_rate + no_show_rate) * 100, 2) || '%' AS "Soma das Taxas",
    CASE
        WHEN (confirmed_rate + completed_rate + cancelled_rate + rescheduled_rate + no_show_rate) <= 1.0001
        THEN '✅ Validação OK'
        ELSE '❌ Erro na soma'
    END AS "Status Validação"
FROM "0b_inbox_counters"
WHERE inbox_id = '11111111-1111-1111-1111-111111111111'::UUID;

-- ================================================================
-- LIMPEZA: Remover dados de teste
-- ================================================================

\echo ''
\echo '================================================================'
\echo 'LIMPEZA: Removendo dados de teste'
\echo '================================================================'

DELETE FROM "4a_customer_service_history"
WHERE inbox_id = '11111111-1111-1111-1111-111111111111'::UUID;

DELETE FROM "3a_customer_root_record"
WHERE id = 999999;

DELETE FROM "1a_whatsapp_user_contact"
WHERE wallet_id = '22222222-2222-2222-2222-222222222222'::UUID;

DELETE FROM "0b_inbox_counters"
WHERE inbox_id = '11111111-1111-1111-1111-111111111111'::UUID;

DELETE FROM "0a_inbox_whatsapp"
WHERE inbox_id = '11111111-1111-1111-1111-111111111111'::UUID;

\echo '✅ Dados de teste removidos com sucesso!'

COMMIT;

\echo ''
\echo '================================================================'
\echo '✅ TODOS OS TESTES CONCLUÍDOS!'
\echo '================================================================'
