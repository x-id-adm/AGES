-- ================================================================
-- TESTES: Taxas de Conversão do Funil de Atendimento
-- ================================================================
-- Data: 2025-11-15
-- Descrição: Valida o cálculo automático das taxas de conversão
--            do funil (contatos -> fichas -> agendamentos)
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
    status_workflow,
    required_data_form
) VALUES (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID,
    'Clínica de Testes - Funil',
    '99999999-9999-9999-9999-999999999999'::UUID,
    'Dr. Teste Funil',
    '🟢',
    ARRAY['3b', '3c', '3d']  -- Requer 3 campos para ficha completa
) ON CONFLICT (inbox_id) DO NOTHING;

-- Criar contador de inbox (será criado automaticamente pelo trigger, mas vamos garantir)
INSERT INTO "0b_inbox_counters" (inbox_id)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID)
ON CONFLICT (inbox_id) DO NOTHING;

-- ================================================================
-- TESTE 1: Taxas com 0 contatos (evitar divisão por zero)
-- ================================================================

\echo ''
\echo '================================================================'
\echo 'TESTE 1: Taxas com 0 contatos (todas devem ser 0.0000)'
\echo '================================================================'

SELECT
    inbox_id,
    contact_count AS "Contatos",
    form_count AS "Fichas",
    scheduling_count AS "Agendamentos",
    form_rate AS "Taxa Cadastro",
    scheduling_rate AS "Taxa Agendamento"
FROM "0b_inbox_counters"
WHERE inbox_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID;

-- ================================================================
-- TESTE 2: Criar 100 contatos
-- ================================================================

\echo ''
\echo '================================================================'
\echo 'TESTE 2: Criar 100 contatos (esperado: contact_count = 100)'
\echo '================================================================'

-- Inserir 100 contatos
DO $$
DECLARE
    i INT;
BEGIN
    FOR i IN 1..100 LOOP
        -- Inserir contato
        INSERT INTO "1a_whatsapp_user_contact" (
            wallet_id,
            inbox_id,
            push_name,
            phone_number
        ) VALUES (
            gen_random_uuid(),
            'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID,
            'Cliente Teste Funil ' || i,
            '5511' || LPAD(i::TEXT, 9, '9')
        );

        -- Incrementar contact_count manualmente (simular webhook)
        UPDATE "0b_inbox_counters"
        SET contact_count = contact_count + 1
        WHERE inbox_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID;
    END LOOP;
END $$;

\echo ''
\echo 'Verificando contadores após 100 contatos:'
SELECT
    contact_count AS "Contatos",
    form_count AS "Fichas",
    scheduling_count AS "Agendamentos",
    ROUND(form_rate * 100, 2) || '%' AS "Taxa Cadastro",
    ROUND(scheduling_rate * 100, 2) || '%' AS "Taxa Agendamento"
FROM "0b_inbox_counters"
WHERE inbox_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID;

-- ================================================================
-- TESTE 3: 75 contatos preenchem ficha (75% de taxa de cadastro)
-- ================================================================

\echo ''
\echo '================================================================'
\echo 'TESTE 3: 75 contatos preenchem ficha (esperado: 75% cadastro)'
\echo '================================================================'

-- Pegar 75 contatos aleatórios e criar fichas completas
DO $$
DECLARE
    contact_rec RECORD;
    form_id INT;
BEGIN
    FOR contact_rec IN (
        SELECT wallet_id, phone_number
        FROM "1a_whatsapp_user_contact"
        WHERE inbox_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID
        LIMIT 75
    ) LOOP
        -- Criar root record (ficha)
        INSERT INTO "3a_customer_root_record" (
            inbox_id,
            treatment_name,
            whatsapp_owner
        ) VALUES (
            'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID,
            'Cliente Teste Funil',
            contact_rec.phone_number
        ) RETURNING id INTO form_id;

        -- Preencher campos obrigatórios (3b, 3c, 3d)
        INSERT INTO "3b_customer_general_data" (root_id, full_name)
        VALUES (form_id, 'Teste Nome');

        INSERT INTO "3c_customer_contact_data" (root_id, email)
        VALUES (form_id, 'teste@example.com');

        INSERT INTO "3d_customer_address_data" (root_id, city)
        VALUES (form_id, 'São Paulo');
    END LOOP;
END $$;

\echo ''
\echo 'Verificando contadores após 75 fichas completas:'
SELECT
    contact_count AS "Contatos",
    form_count AS "Fichas",
    scheduling_count AS "Agendamentos",
    ROUND(form_rate * 100, 2) || '%' AS "Taxa Cadastro (%)",
    form_rate AS "Taxa Cadastro (decimal)"
FROM "0b_inbox_counters"
WHERE inbox_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID;

-- ================================================================
-- TESTE 4: 60 contatos fazem agendamento (60% de taxa de agendamento)
-- ================================================================

\echo ''
\echo '================================================================'
\echo 'TESTE 4: 60 contatos fazem agendamento (esperado: 60% agendamento)'
\echo '================================================================'

-- Pegar 60 fichas e criar agendamentos
DO $$
DECLARE
    form_rec RECORD;
    contact_wallet UUID;
BEGIN
    FOR form_rec IN (
        SELECT id, whatsapp_owner
        FROM "3a_customer_root_record"
        WHERE inbox_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID
        LIMIT 60
    ) LOOP
        -- Buscar wallet_id do contato
        SELECT wallet_id INTO contact_wallet
        FROM "1a_whatsapp_user_contact"
        WHERE phone_number = form_rec.whatsapp_owner
        LIMIT 1;

        -- Criar agendamento
        INSERT INTO "4a_customer_service_history" (
            inbox_id,
            root_id,
            scheduled_by_wallet_id,
            service_datetime_start,
            service_datetime_end,
            service_status
        ) VALUES (
            'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID,
            form_rec.id,
            contact_wallet,
            NOW() + INTERVAL '1 day',
            NOW() + INTERVAL '1 day 1 hour',
            'Scheduled'
        );

        -- Incrementar scheduling_count manualmente
        UPDATE "0b_inbox_counters"
        SET scheduling_count = scheduling_count + 1
        WHERE inbox_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID;
    END LOOP;
END $$;

\echo ''
\echo 'Verificando contadores após 60 agendamentos:'
SELECT
    contact_count AS "Contatos",
    form_count AS "Fichas",
    scheduling_count AS "Agendamentos",
    ROUND(form_rate * 100, 2) || '%' AS "Taxa Cadastro",
    ROUND(scheduling_rate * 100, 2) || '%' AS "Taxa Agendamento (%)",
    scheduling_rate AS "Taxa Agendamento (decimal)"
FROM "0b_inbox_counters"
WHERE inbox_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID;

-- ================================================================
-- TESTE 5: Visualização do Funil Completo
-- ================================================================

\echo ''
\echo '================================================================'
\echo 'TESTE 5: RELATÓRIO FINAL - Funil Completo de Atendimento'
\echo '================================================================'

SELECT
    '📊 FUNIL DE ATENDIMENTO' AS "Seção";

\echo ''
\echo 'Contadores Absolutos:'
SELECT
    contact_count AS "1️⃣ Contatos",
    form_count AS "2️⃣ Fichas Completas",
    scheduling_count AS "3️⃣ Agendamentos"
FROM "0b_inbox_counters"
WHERE inbox_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID;

\echo ''
\echo 'Taxas de Conversão (Percentual):'
SELECT
    ROUND(form_rate * 100, 2) || '%' AS "Taxa Cadastro (Ficha)",
    ROUND(scheduling_rate * 100, 2) || '%' AS "Taxa Agendamento"
FROM "0b_inbox_counters"
WHERE inbox_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID;

\echo ''
\echo 'Taxas de Conversão (Decimal):'
SELECT
    form_rate AS "Taxa Cadastro",
    scheduling_rate AS "Taxa Agendamento"
FROM "0b_inbox_counters"
WHERE inbox_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID;

-- ================================================================
-- TESTE 6: Validação Matemática
-- ================================================================

\echo ''
\echo '================================================================'
\echo 'TESTE 6: Validação Matemática do Funil'
\echo '================================================================'

SELECT
    '✅ Validação: form_count <= contact_count' AS "Regra",
    CASE
        WHEN form_count <= contact_count THEN '✅ OK'
        ELSE '❌ ERRO'
    END AS "Status"
FROM "0b_inbox_counters"
WHERE inbox_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID

UNION ALL

SELECT
    '✅ Validação: scheduling_count <= contact_count' AS "Regra",
    CASE
        WHEN scheduling_count <= contact_count THEN '✅ OK'
        ELSE '❌ ERRO'
    END AS "Status"
FROM "0b_inbox_counters"
WHERE inbox_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID

UNION ALL

SELECT
    '✅ Validação: form_rate <= 1.0' AS "Regra",
    CASE
        WHEN form_rate <= 1.0 THEN '✅ OK'
        ELSE '❌ ERRO'
    END AS "Status"
FROM "0b_inbox_counters"
WHERE inbox_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID

UNION ALL

SELECT
    '✅ Validação: scheduling_rate <= 1.0' AS "Regra",
    CASE
        WHEN scheduling_rate <= 1.0 THEN '✅ OK'
        ELSE '❌ ERRO'
    END AS "Status"
FROM "0b_inbox_counters"
WHERE inbox_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID;

-- ================================================================
-- TESTE 7: Visualização Combinada (Funil + Status)
-- ================================================================

\echo ''
\echo '================================================================'
\echo 'TESTE 7: Visão Completa - Funil + Taxas de Status'
\echo '================================================================'

SELECT
    '📈 FUNIL COMPLETO' AS "Tipo",
    contact_count AS "Contatos",
    ROUND(form_rate * 100, 2) || '%' AS "→ Fichas",
    ROUND(scheduling_rate * 100, 2) || '%' AS "→ Agendamentos",
    ROUND(confirmed_rate * 100, 2) || '%' AS "→ Confirmados",
    ROUND(completed_rate * 100, 2) || '%' AS "→ Concluídos"
FROM "0b_inbox_counters"
WHERE inbox_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID;

-- ================================================================
-- LIMPEZA: Remover dados de teste
-- ================================================================

\echo ''
\echo '================================================================'
\echo 'LIMPEZA: Removendo dados de teste'
\echo '================================================================'

DELETE FROM "4a_customer_service_history"
WHERE inbox_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID;

DELETE FROM "3d_customer_address_data"
WHERE root_id IN (
    SELECT id FROM "3a_customer_root_record"
    WHERE inbox_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID
);

DELETE FROM "3c_customer_contact_data"
WHERE root_id IN (
    SELECT id FROM "3a_customer_root_record"
    WHERE inbox_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID
);

DELETE FROM "3b_customer_general_data"
WHERE root_id IN (
    SELECT id FROM "3a_customer_root_record"
    WHERE inbox_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID
);

DELETE FROM "3a_customer_root_record"
WHERE inbox_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID;

DELETE FROM "1a_whatsapp_user_contact"
WHERE inbox_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID;

DELETE FROM "0b_inbox_counters"
WHERE inbox_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID;

DELETE FROM "0a_inbox_whatsapp"
WHERE inbox_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID;

\echo '✅ Dados de teste removidos com sucesso!'

COMMIT;

\echo ''
\echo '================================================================'
\echo '✅ TODOS OS TESTES DO FUNIL CONCLUÍDOS!'
\echo '================================================================'
\echo ''
\echo 'Resumo esperado:'
\echo '- 100 contatos criados'
\echo '- 75 fichas completas (75% taxa de cadastro)'
\echo '- 60 agendamentos (60% taxa de agendamento)'
\echo '================================================================'
