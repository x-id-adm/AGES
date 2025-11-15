-- =================================================================================================
-- TRIGGER: ATUALIZAÇÃO AUTOMÁTICA DE LTV (LIFETIME VALUE)
-- =================================================================================================
-- DESCRIÇÃO:
--   Trigger que atualiza automaticamente os campos de LTV na tabela 3a_customer_root_record
--   sempre que um atendimento é marcado como 'Completed'.
--
-- COMPORTAMENTO:
--   - Dispara quando service_status muda para 'Completed'
--   - Atualiza total_spent_cents, total_completed_appointments
--   - Atualiza first_purchase_at (se for a primeira compra)
--   - Atualiza last_purchase_at
--
-- IMPORTANTE:
--   - Apenas atendimentos com value_cents > 0 são considerados
--   - Não conta o mesmo atendimento duas vezes
--   - Funciona tanto para INSERT quanto para UPDATE
--
-- VERSÃO: 1.0
-- DATA: 2025-11-15
-- =================================================================================================


-- =================================================================================================
-- FUNÇÃO DO TRIGGER
-- =================================================================================================

-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNÇÃO: update_customer_ltv                                                                 │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   Função que é chamada pelo trigger para atualizar os campos de LTV do cliente.             │
-- │                                                                                             │
-- │ LÓGICA:                                                                                     │
-- │   1. Verifica se é um INSERT ou UPDATE                                                      │
-- │   2. Se for UPDATE:                                                                         │
-- │      - Verifica se o status mudou de algo diferente para 'Completed'                        │
-- │      - Se o status antigo já era 'Completed', não faz nada (evita duplicação)               │
-- │   3. Se for INSERT:                                                                         │
-- │      - Verifica se o status é 'Completed'                                                   │
-- │   4. Verifica se value_cents está definido e > 0                                            │
-- │   5. Atualiza os campos na tabela 3a_customer_root_record:                                  │
-- │      - Incrementa total_spent_cents                                                         │
-- │      - Incrementa total_completed_appointments                                              │
-- │      - Atualiza last_purchase_at                                                            │
-- │      - Define first_purchase_at se for a primeira compra                                    │
-- │                                                                                             │
-- │ PARÂMETROS:                                                                                 │
-- │   NEW - Registro novo (após INSERT/UPDATE)                                                  │
-- │   OLD - Registro antigo (antes do UPDATE, NULL em INSERT)                                   │
-- │                                                                                             │
-- │ RETORNO:                                                                                    │
-- │   NEW (padrão para triggers BEFORE)                                                         │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION update_customer_ltv()
RETURNS TRIGGER AS $$
DECLARE
    v_should_update BOOLEAN := FALSE;
BEGIN
    -- ========================================
    -- VALIDAÇÕES: Determinar se deve atualizar
    -- ========================================

    -- Caso 1: INSERT - verifica se já está como Completed
    IF TG_OP = 'INSERT' THEN
        IF NEW.service_status = 'Completed' THEN
            v_should_update := TRUE;
        END IF;
    END IF;

    -- Caso 2: UPDATE - verifica se mudou para Completed
    IF TG_OP = 'UPDATE' THEN
        -- Só atualiza se:
        -- 1. Status mudou para 'Completed' E
        -- 2. Status anterior era diferente de 'Completed'
        -- (evita contar duas vezes o mesmo atendimento)
        IF NEW.service_status = 'Completed' AND OLD.service_status != 'Completed' THEN
            v_should_update := TRUE;
        END IF;
    END IF;

    -- Validação adicional: deve ter value_cents válido
    IF v_should_update THEN
        IF NEW.value_cents IS NULL OR NEW.value_cents <= 0 THEN
            v_should_update := FALSE;
        END IF;
    END IF;

    -- Se não deve atualizar, retorna sem fazer nada
    IF NOT v_should_update THEN
        RETURN NEW;
    END IF;

    -- ========================================
    -- ATUALIZAÇÃO DO LTV
    -- ========================================

    -- Atualiza os campos de LTV na ficha do cliente
    UPDATE "3a_customer_root_record"
    SET
        -- Incrementa o total gasto
        total_spent_cents = total_spent_cents + NEW.value_cents,

        -- Incrementa a quantidade de atendimentos completados
        total_completed_appointments = total_completed_appointments + 1,

        -- Atualiza a data da última compra
        last_purchase_at = NEW.completed_at,

        -- Define a data da primeira compra (se ainda não foi definida)
        first_purchase_at = CASE
            WHEN first_purchase_at IS NULL THEN NEW.completed_at
            ELSE first_purchase_at
        END,

        -- Atualiza o timestamp de modificação
        updated_at = NOW()

    WHERE id = NEW.root_id;

    -- Log de debug (opcional - comentar em produção se não necessário)
    RAISE NOTICE 'LTV atualizado para root_id %: +% centavos (total agora: %)',
        NEW.root_id,
        NEW.value_cents,
        (SELECT total_spent_cents FROM "3a_customer_root_record" WHERE id = NEW.root_id);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- =================================================================================================
-- CRIAÇÃO DO TRIGGER
-- =================================================================================================

-- Remove o trigger se já existir (para permitir re-execução do script)
DROP TRIGGER IF EXISTS trigger_update_customer_ltv ON "4a_customer_service_history";

-- Cria o trigger
CREATE TRIGGER trigger_update_customer_ltv
    AFTER INSERT OR UPDATE OF service_status
    ON "4a_customer_service_history"
    FOR EACH ROW
    EXECUTE FUNCTION update_customer_ltv();


-- =================================================================================================
-- FUNÇÃO AUXILIAR: Recalcular LTV Manualmente
-- =================================================================================================

-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNÇÃO: recalculate_customer_ltv                                                            │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   Recalcula o LTV de um cliente específico baseado em todos os seus atendimentos.           │
-- │   Útil para corrigir dados ou inicializar valores.                                          │
-- │                                                                                             │
-- │ PARÂMETROS:                                                                                 │
-- │   p_root_id (BIGINT) - ID da ficha do cliente                                               │
-- │                                                                                             │
-- │ RETORNO:                                                                                    │
-- │   JSONB com os novos valores calculados                                                     │
-- │                                                                                             │
-- │ EXEMPLO DE USO:                                                                             │
-- │   -- Recalcular LTV de um cliente específico                                                │
-- │   SELECT recalculate_customer_ltv(123);                                                     │
-- │                                                                                             │
-- │   -- Recalcular LTV de todos os clientes de uma inbox                                       │
-- │   SELECT recalculate_customer_ltv(id)                                                       │
-- │   FROM "3a_customer_root_record"                                                            │
-- │   WHERE inbox_id = 'uuid-inbox';                                                            │
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
    -- Calcula valores agregados de todos os atendimentos completados
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

    -- Atualiza a ficha do cliente
    UPDATE "3a_customer_root_record"
    SET
        total_spent_cents = v_total_cents,
        total_completed_appointments = v_completed_count,
        first_purchase_at = v_first_purchase,
        last_purchase_at = v_last_purchase,
        updated_at = NOW()
    WHERE id = p_root_id;

    -- Retorna os valores calculados
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
-- FUNÇÃO AUXILIAR: Recalcular LTV de Todos os Clientes de uma Inbox
-- =================================================================================================

-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNÇÃO: recalculate_all_ltv_for_inbox                                                       │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   Recalcula o LTV de todos os clientes de uma inbox.                                        │
-- │   Útil para inicializar valores ou corrigir inconsistências em massa.                       │
-- │                                                                                             │
-- │ PARÂMETROS:                                                                                 │
-- │   p_inbox_id (UUID) - ID da inbox                                                           │
-- │                                                                                             │
-- │ RETORNO:                                                                                    │
-- │   JSONB com estatísticas da operação                                                        │
-- │                                                                                             │
-- │ EXEMPLO DE USO:                                                                             │
-- │   SELECT recalculate_all_ltv_for_inbox('uuid-inbox');                                       │
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

    -- Loop por todos os clientes da inbox
    FOR v_customer IN
        SELECT id FROM "3a_customer_root_record"
        WHERE inbox_id = p_inbox_id
    LOOP
        -- Recalcula o LTV do cliente
        PERFORM recalculate_customer_ltv(v_customer.id);
        v_customer_count := v_customer_count + 1;
    END LOOP;

    -- Calcula o faturamento total da inbox
    SELECT COALESCE(SUM(total_spent_cents), 0)
    INTO v_total_billing
    FROM "3a_customer_root_record"
    WHERE inbox_id = p_inbox_id;

    -- Retorna estatísticas
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
-- RESUMO
-- =================================================================================================
-- Trigger criado: trigger_update_customer_ltv
--   - Dispara em: INSERT ou UPDATE de service_status na tabela 4a_customer_service_history
--   - Quando: service_status muda para 'Completed' e value_cents > 0
--   - Atualiza: Campos de LTV na tabela 3a_customer_root_record
--
-- Funções auxiliares criadas:
--   • recalculate_customer_ltv(p_root_id) - Recalcula LTV de um cliente
--   • recalculate_all_ltv_for_inbox(p_inbox_id) - Recalcula LTV de todos os clientes
-- =================================================================================================
