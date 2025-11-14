-- ================================================================
-- TESTES: Contadores de Status de Atendimentos
-- ================================================================
-- Data: 2025-11-14
-- Descrição: Script de testes e exemplos de uso dos contadores
--            automáticos de status de atendimentos
-- ================================================================

-- ================================================================
-- PASSO 1: Criar dados de teste
-- ================================================================

-- Criar uma inbox de teste (se não existir)
INSERT INTO "0a_inbox_whatsapp" (
    inbox_id,
    owner_wallet_id,
    client_name,
    inbox_name
)
VALUES (
    '00000000-0000-0000-0000-000000000001'::UUID,
    '00000000-0000-0000-0000-000000000002'::UUID,
    'Clínica Teste',
    'Inbox Teste Contadores'
)
ON CONFLICT (inbox_id) DO NOTHING;

-- Criar um contato de teste
INSERT INTO "1a_whatsapp_user_contact" (
    wallet_id,
    inbox_id,
    push_name,
    phone_number
)
VALUES (
    '00000000-0000-0000-0000-000000000003'::UUID,
    '00000000-0000-0000-0000-000000000001'::UUID,
    'João da Silva',
    '+5511999999999'
)
ON CONFLICT (wallet_id) DO NOTHING;

-- Criar uma ficha de cliente
INSERT INTO "3a_customer_root_record" (
    inbox_id,
    treatment_name,
    whatsapp_owner
)
VALUES (
    '00000000-0000-0000-0000-000000000001'::UUID,
    'João da Silva',
    '+5511999999999'
)
ON CONFLICT DO NOTHING
RETURNING id;

-- ================================================================
-- PASSO 2: Ver estado inicial dos contadores
-- ================================================================

SELECT
    inbox_id,
    scheduled_count,
    confirmed_count,
    completed_count,
    cancelled_count,
    rescheduled_count,
    no_show_count
FROM "0b_inbox_counters"
WHERE inbox_id = '00000000-0000-0000-0000-000000000001'::UUID;

-- Resultado esperado: todos os contadores = 0 (ou linha não existe ainda)

-- ================================================================
-- PASSO 3: Criar atendimentos com diferentes status
-- ================================================================

-- 3.1 Criar atendimento com status 'Scheduled'
INSERT INTO "4a_customer_service_history" (
    inbox_id,
    root_id,
    service_datetime_start,
    service_datetime_end,
    service_status,
    service_type
)
VALUES (
    '00000000-0000-0000-0000-000000000001'::UUID,
    (SELECT id FROM "3a_customer_root_record" WHERE whatsapp_owner = '+5511999999999' LIMIT 1),
    NOW() + INTERVAL '1 day',
    NOW() + INTERVAL '1 day 1 hour',
    'Scheduled',
    'Consulta'
);

-- 3.2 Ver contadores após inserção
SELECT
    inbox_id,
    scheduled_count,     -- Deve ser 1
    confirmed_count,     -- Deve ser 0
    completed_count,     -- Deve ser 0
    cancelled_count,     -- Deve ser 0
    rescheduled_count,   -- Deve ser 0
    no_show_count        -- Deve ser 0
FROM "0b_inbox_counters"
WHERE inbox_id = '00000000-0000-0000-0000-000000000001'::UUID;

-- 3.3 Criar mais atendimentos com status diferentes
INSERT INTO "4a_customer_service_history" (
    inbox_id,
    root_id,
    service_datetime_start,
    service_datetime_end,
    service_status,
    service_type
)
VALUES
    -- Atendimento confirmado
    (
        '00000000-0000-0000-0000-000000000001'::UUID,
        (SELECT id FROM "3a_customer_root_record" WHERE whatsapp_owner = '+5511999999999' LIMIT 1),
        NOW() + INTERVAL '2 days',
        NOW() + INTERVAL '2 days 1 hour',
        'Confirmed',
        'Retorno'
    ),
    -- Atendimento completado
    (
        '00000000-0000-0000-0000-000000000001'::UUID,
        (SELECT id FROM "3a_customer_root_record" WHERE whatsapp_owner = '+5511999999999' LIMIT 1),
        NOW() - INTERVAL '1 day',
        NOW() - INTERVAL '1 day' + INTERVAL '1 hour',
        'Completed',
        'Consulta'
    );

-- 3.4 Ver contadores após inserções
SELECT
    inbox_id,
    scheduled_count,     -- Deve ser 1
    confirmed_count,     -- Deve ser 1
    completed_count,     -- Deve ser 1
    cancelled_count,     -- Deve ser 0
    rescheduled_count,   -- Deve ser 0
    no_show_count        -- Deve ser 0
FROM "0b_inbox_counters"
WHERE inbox_id = '00000000-0000-0000-0000-000000000001'::UUID;

-- ================================================================
-- PASSO 4: Testar mudanças de status (UPDATE)
-- ================================================================

-- 4.1 Mudar status de 'Scheduled' para 'Confirmed'
UPDATE "4a_customer_service_history"
SET service_status = 'Confirmed'
WHERE inbox_id = '00000000-0000-0000-0000-000000000001'::UUID
  AND service_status = 'Scheduled'
LIMIT 1;

-- 4.2 Ver contadores após mudança
SELECT
    inbox_id,
    scheduled_count,     -- Deve ser 0 (decrementou)
    confirmed_count,     -- Deve ser 2 (incrementou)
    completed_count,     -- Deve ser 1
    cancelled_count,     -- Deve ser 0
    rescheduled_count,   -- Deve ser 0
    no_show_count        -- Deve ser 0
FROM "0b_inbox_counters"
WHERE inbox_id = '00000000-0000-0000-0000-000000000001'::UUID;

-- 4.3 Mudar um atendimento para 'No_Show'
UPDATE "4a_customer_service_history"
SET service_status = 'No_Show'
WHERE inbox_id = '00000000-0000-0000-0000-000000000001'::UUID
  AND service_status = 'Confirmed'
LIMIT 1;

-- 4.4 Ver contadores após mudança
SELECT
    inbox_id,
    scheduled_count,     -- Deve ser 0
    confirmed_count,     -- Deve ser 1 (decrementou)
    completed_count,     -- Deve ser 1
    cancelled_count,     -- Deve ser 0
    rescheduled_count,   -- Deve ser 0
    no_show_count        -- Deve ser 1 (incrementou)
FROM "0b_inbox_counters"
WHERE inbox_id = '00000000-0000-0000-0000-000000000001'::UUID;

-- ================================================================
-- PASSO 5: Queries úteis para visualização
-- ================================================================

-- 5.1 Ver todos os atendimentos com seus status
SELECT
    service_id,
    service_status,
    service_type,
    service_datetime_start,
    created_at
FROM "4a_customer_service_history"
WHERE inbox_id = '00000000-0000-0000-0000-000000000001'::UUID
ORDER BY created_at DESC;

-- 5.2 Ver resumo completo dos contadores da inbox
SELECT
    i.inbox_name,
    c.contact_count AS "Total Contatos",
    c.form_count AS "Fichas Completas",
    c.scheduling_count AS "Total Agendamentos",
    c.scheduled_count AS "⏰ Agendados",
    c.confirmed_count AS "✅ Confirmados",
    c.completed_count AS "✔️ Completados",
    c.cancelled_count AS "❌ Cancelados",
    c.rescheduled_count AS "🔄 Reagendados",
    c.no_show_count AS "❓ Não Compareceu"
FROM "0b_inbox_counters" c
JOIN "0a_inbox_whatsapp" i ON i.inbox_id = c.inbox_id
WHERE c.inbox_id = '00000000-0000-0000-0000-000000000001'::UUID;

-- 5.3 Ver distribuição de status em todas as inboxes
SELECT
    i.inbox_name,
    c.scheduled_count + c.confirmed_count + c.completed_count +
    c.cancelled_count + c.rescheduled_count + c.no_show_count AS "Total",
    c.scheduled_count AS "Agendados",
    c.confirmed_count AS "Confirmados",
    c.completed_count AS "Completados",
    c.cancelled_count AS "Cancelados",
    c.rescheduled_count AS "Reagendados",
    c.no_show_count AS "No-Show"
FROM "0b_inbox_counters" c
JOIN "0a_inbox_whatsapp" i ON i.inbox_id = c.inbox_id
ORDER BY i.inbox_name;

-- ================================================================
-- PASSO 6: Limpeza (opcional)
-- ================================================================

-- Remover dados de teste (descomente se quiser limpar)
-- DELETE FROM "4a_customer_service_history"
-- WHERE inbox_id = '00000000-0000-0000-0000-000000000001'::UUID;
--
-- DELETE FROM "3a_customer_root_record"
-- WHERE inbox_id = '00000000-0000-0000-0000-000000000001'::UUID;
--
-- DELETE FROM "1a_whatsapp_user_contact"
-- WHERE inbox_id = '00000000-0000-0000-0000-000000000001'::UUID;
--
-- DELETE FROM "0a_inbox_whatsapp"
-- WHERE inbox_id = '00000000-0000-0000-0000-000000000001'::UUID;

-- ================================================================
-- OBSERVAÇÕES IMPORTANTES
-- ================================================================

-- 1. Os contadores são atualizados AUTOMATICAMENTE pelos triggers
-- 2. Não é necessário atualizar manualmente os contadores
-- 3. Os contadores são específicos por inbox
-- 4. Mudanças de status são rastreadas corretamente (decremento + incremento)
-- 5. Proteção contra valores negativos implementada com GREATEST()
-- 6. Status suportados:
--    • Scheduled (Agendado - mudado pelo Agente de IA)
--    • Confirmed (Confirmado - mudado pelo Agente de IA)
--    • Completed (Completado - mudado pelo Humano)
--    • Cancelled (Cancelado - mudado pelo Humano/IA)
--    • Rescheduled (Reagendado - mudado pelo Humano)
--    • No_Show (Não Compareceu - mudado pelo Humano)

-- ================================================================
