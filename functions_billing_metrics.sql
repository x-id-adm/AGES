-- =================================================================================================
-- FUNÇÕES PARA MÉTRICAS DE FATURAMENTO
-- =================================================================================================
-- DESCRIÇÃO:
--   Funções para consultar faturamento filtrado por período de tempo.
--   Permite queries como: "Quanto foi faturado hoje?"
--                        "Quanto foi faturado nos últimos 7 dias?"
--                        "Quanto foi faturado em Janeiro?"
--
-- IMPORTANTE:
--   - Apenas atendimentos com status 'Completed' são considerados no faturamento
--   - O valor é filtrado pelo timestamp 'completed_at' (quando foi marcado como completado)
--   - Valores em centavos (dividir por 100 para obter valor em reais)
--
-- VERSÃO: 1.0
-- DATA: 2025-11-15
-- =================================================================================================


-- =================================================================================================
-- FUNÇÃO PRINCIPAL: Faturamento por Período
-- =================================================================================================

-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNÇÃO: func_get_billing_by_period                                                          │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   Retorna o faturamento total e detalhado para um período de tempo específico.              │
-- │                                                                                             │
-- │ PARÂMETROS:                                                                                 │
-- │   p_inbox_id (UUID) - ID da inbox para filtrar                                              │
-- │   p_start_date (TIMESTAMPTZ) - Data/hora de início do período (inclusivo)                   │
-- │   p_end_date (TIMESTAMPTZ) - Data/hora de fim do período (exclusivo)                        │
-- │                                                                                             │
-- │ RETORNO:                                                                                    │
-- │   JSONB com estrutura:                                                                      │
-- │   {                                                                                         │
-- │     "total_billing_cents": 45000,        // R$ 450.00                                       │
-- │     "total_billing_reais": 450.00,       // Valor em reais                                  │
-- │     "completed_count": 15,               // Quantidade de atendimentos completados          │
-- │     "average_ticket_cents": 3000,        // Ticket médio em centavos (R$ 30.00)            │
-- │     "average_ticket_reais": 30.00,       // Ticket médio em reais                           │
-- │     "period": {                                                                             │
-- │       "start": "2025-01-01T00:00:00Z",                                                      │
-- │       "end": "2025-02-01T00:00:00Z"                                                         │
-- │     }                                                                                       │
-- │   }                                                                                         │
-- │                                                                                             │
-- │ LÓGICA:                                                                                     │
-- │   Soma todos os value_cents de atendimentos com status 'Completed' que foram               │
-- │   completados (completed_at) dentro do período especificado.                                │
-- │                                                                                             │
-- │ EXEMPLO DE USO:                                                                             │
-- │   -- Faturamento dos últimos 7 dias                                                         │
-- │   SELECT func_get_billing_by_period(                                                        │
-- │       'uuid-da-inbox',                                                                      │
-- │       NOW() - INTERVAL '7 days',                                                            │
-- │       NOW()                                                                                 │
-- │   );                                                                                        │
-- │                                                                                             │
-- │   -- Faturamento de Janeiro de 2025                                                         │
-- │   SELECT func_get_billing_by_period(                                                        │
-- │       'uuid-da-inbox',                                                                      │
-- │       '2025-01-01 00:00:00'::TIMESTAMPTZ,                                                   │
-- │       '2025-02-01 00:00:00'::TIMESTAMPTZ                                                    │
-- │   );                                                                                        │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION func_get_billing_by_period(
    p_inbox_id UUID,
    p_start_date TIMESTAMPTZ,
    p_end_date TIMESTAMPTZ
)
RETURNS JSONB AS $$
DECLARE
    v_total_cents BIGINT;
    v_completed_count INT;
    v_avg_ticket_cents BIGINT;
    v_result JSONB;
BEGIN
    -- Calcula o total faturado e quantidade de atendimentos completados
    SELECT
        COALESCE(SUM(value_cents), 0),
        COUNT(*)
    INTO v_total_cents, v_completed_count
    FROM "4a_customer_service_history"
    WHERE inbox_id = p_inbox_id
      AND service_status = 'Completed'
      AND completed_at >= p_start_date
      AND completed_at < p_end_date
      AND value_cents IS NOT NULL
      AND value_cents > 0;

    -- Calcula o ticket médio
    IF v_completed_count > 0 THEN
        v_avg_ticket_cents := v_total_cents / v_completed_count;
    ELSE
        v_avg_ticket_cents := 0;
    END IF;

    -- Monta o resultado em JSON
    v_result := jsonb_build_object(
        'total_billing_cents', v_total_cents,
        'total_billing_reais', ROUND(v_total_cents::NUMERIC / 100, 2),
        'completed_count', v_completed_count,
        'average_ticket_cents', v_avg_ticket_cents,
        'average_ticket_reais', ROUND(v_avg_ticket_cents::NUMERIC / 100, 2),
        'period', jsonb_build_object(
            'start', p_start_date,
            'end', p_end_date
        )
    );

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;


-- =================================================================================================
-- FUNÇÕES DE CONVENIÊNCIA: Períodos Comuns
-- =================================================================================================

-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNÇÃO: func_get_billing_today                                                              │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   Retorna o faturamento do dia atual (de 00:00:00 até agora).                               │
-- │                                                                                             │
-- │ EXEMPLO DE USO:                                                                             │
-- │   SELECT func_get_billing_today('uuid-inbox');                                              │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION func_get_billing_today(
    p_inbox_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_today_start TIMESTAMPTZ;
BEGIN
    -- Início do dia de hoje (00:00:00)
    v_today_start := date_trunc('day', NOW());

    RETURN func_get_billing_by_period(
        p_inbox_id,
        v_today_start,
        NOW()
    );
END;
$$ LANGUAGE plpgsql;


-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNÇÃO: func_get_billing_last_n_days                                                        │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   Retorna o faturamento dos últimos N dias.                                                 │
-- │                                                                                             │
-- │ EXEMPLO DE USO:                                                                             │
-- │   -- Últimos 7 dias                                                                         │
-- │   SELECT func_get_billing_last_n_days('uuid-inbox', 7);                                     │
-- │                                                                                             │
-- │   -- Últimos 30 dias                                                                        │
-- │   SELECT func_get_billing_last_n_days('uuid-inbox', 30);                                    │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION func_get_billing_last_n_days(
    p_inbox_id UUID,
    p_days INT
)
RETURNS JSONB AS $$
BEGIN
    RETURN func_get_billing_by_period(
        p_inbox_id,
        NOW() - (p_days || ' days')::INTERVAL,
        NOW()
    );
END;
$$ LANGUAGE plpgsql;


-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNÇÃO: func_get_billing_specific_month                                                     │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   Retorna o faturamento de um mês específico.                                               │
-- │                                                                                             │
-- │ PARÂMETROS:                                                                                 │
-- │   p_inbox_id (UUID) - ID da inbox                                                           │
-- │   p_year (INT) - Ano (ex: 2025)                                                             │
-- │   p_month (INT) - Mês (1-12)                                                                │
-- │                                                                                             │
-- │ EXEMPLO DE USO:                                                                             │
-- │   -- Janeiro de 2025                                                                        │
-- │   SELECT func_get_billing_specific_month('uuid-inbox', 2025, 1);                            │
-- │                                                                                             │
-- │   -- Dezembro de 2024                                                                       │
-- │   SELECT func_get_billing_specific_month('uuid-inbox', 2024, 12);                           │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION func_get_billing_specific_month(
    p_inbox_id UUID,
    p_year INT,
    p_month INT
)
RETURNS JSONB AS $$
DECLARE
    v_start_date TIMESTAMPTZ;
    v_end_date TIMESTAMPTZ;
BEGIN
    -- Validação do mês
    IF p_month < 1 OR p_month > 12 THEN
        RAISE EXCEPTION 'Mês inválido: %. Deve estar entre 1 e 12.', p_month;
    END IF;

    -- Primeiro dia do mês às 00:00:00
    v_start_date := make_timestamptz(p_year, p_month, 1, 0, 0, 0);

    -- Primeiro dia do mês seguinte às 00:00:00
    v_end_date := v_start_date + INTERVAL '1 month';

    RETURN func_get_billing_by_period(
        p_inbox_id,
        v_start_date,
        v_end_date
    );
END;
$$ LANGUAGE plpgsql;


-- =================================================================================================
-- FUNÇÕES DE LTV (LIFETIME VALUE) POR CLIENTE
-- =================================================================================================

-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNÇÃO: func_get_customer_ltv                                                               │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   Retorna o LTV (Lifetime Value) de um cliente específico.                                  │
-- │                                                                                             │
-- │ PARÂMETROS:                                                                                 │
-- │   p_root_id (BIGINT) - ID da ficha do cliente (3a_customer_root_record)                     │
-- │                                                                                             │
-- │ RETORNO:                                                                                    │
-- │   JSONB com estrutura:                                                                      │
-- │   {                                                                                         │
-- │     "root_id": 123,                                                                         │
-- │     "client_id": "CT456",                                                                   │
-- │     "treatment_name": "João Silva",                                                         │
-- │     "total_spent_cents": 60000,          // R$ 600.00                                       │
-- │     "total_spent_reais": 600.00,                                                            │
-- │     "total_completed_appointments": 3,                                                      │
-- │     "average_ticket_cents": 20000,       // R$ 200.00                                       │
-- │     "average_ticket_reais": 200.00,                                                         │
-- │     "first_purchase_at": "2025-01-15T10:00:00Z",                                            │
-- │     "last_purchase_at": "2025-11-10T14:30:00Z",                                             │
-- │     "customer_lifetime_days": 299        // Dias desde a primeira compra                    │
-- │   }                                                                                         │
-- │                                                                                             │
-- │ EXEMPLO DE USO:                                                                             │
-- │   SELECT func_get_customer_ltv(123);                                                        │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION func_get_customer_ltv(
    p_root_id BIGINT
)
RETURNS JSONB AS $$
DECLARE
    v_result JSONB;
    v_total_cents BIGINT;
    v_completed_count INT;
    v_avg_ticket_cents BIGINT;
    v_lifetime_days INT;
BEGIN
    -- Busca dados do cliente
    SELECT
        jsonb_build_object(
            'root_id', cr.id,
            'client_id', cr.client_id,
            'treatment_name', cr.treatment_name,
            'total_spent_cents', cr.total_spent_cents,
            'total_spent_reais', ROUND(cr.total_spent_cents::NUMERIC / 100, 2),
            'total_completed_appointments', cr.total_completed_appointments,
            'average_ticket_cents', CASE
                WHEN cr.total_completed_appointments > 0
                THEN cr.total_spent_cents / cr.total_completed_appointments
                ELSE 0
            END,
            'average_ticket_reais', CASE
                WHEN cr.total_completed_appointments > 0
                THEN ROUND((cr.total_spent_cents::NUMERIC / cr.total_completed_appointments) / 100, 2)
                ELSE 0
            END,
            'first_purchase_at', cr.first_purchase_at,
            'last_purchase_at', cr.last_purchase_at,
            'customer_lifetime_days', CASE
                WHEN cr.first_purchase_at IS NOT NULL
                THEN EXTRACT(DAY FROM (COALESCE(cr.last_purchase_at, NOW()) - cr.first_purchase_at))::INT
                ELSE 0
            END
        )
    INTO v_result
    FROM "3a_customer_root_record" cr
    WHERE cr.id = p_root_id;

    -- Se não encontrou o cliente
    IF v_result IS NULL THEN
        RAISE EXCEPTION 'Cliente com root_id % não encontrado', p_root_id;
    END IF;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;


-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNÇÃO: func_get_top_customers_by_ltv                                                       │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   Retorna os top N clientes ordenados por LTV (maior para menor).                           │
-- │                                                                                             │
-- │ PARÂMETROS:                                                                                 │
-- │   p_inbox_id (UUID) - ID da inbox para filtrar                                              │
-- │   p_limit (INT) - Quantidade de clientes a retornar (default: 10)                           │
-- │                                                                                             │
-- │ RETORNO:                                                                                    │
-- │   JSONB array com os top clientes ordenados por total_spent_cents                           │
-- │                                                                                             │
-- │ EXEMPLO DE USO:                                                                             │
-- │   -- Top 10 clientes                                                                        │
-- │   SELECT func_get_top_customers_by_ltv('uuid-inbox', 10);                                   │
-- │                                                                                             │
-- │   -- Top 50 clientes                                                                        │
-- │   SELECT func_get_top_customers_by_ltv('uuid-inbox', 50);                                   │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION func_get_top_customers_by_ltv(
    p_inbox_id UUID,
    p_limit INT DEFAULT 10
)
RETURNS JSONB AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_agg(customer_data)
    INTO v_result
    FROM (
        SELECT jsonb_build_object(
            'root_id', cr.id,
            'client_id', cr.client_id,
            'treatment_name', cr.treatment_name,
            'total_spent_cents', cr.total_spent_cents,
            'total_spent_reais', ROUND(cr.total_spent_cents::NUMERIC / 100, 2),
            'total_completed_appointments', cr.total_completed_appointments,
            'average_ticket_cents', CASE
                WHEN cr.total_completed_appointments > 0
                THEN cr.total_spent_cents / cr.total_completed_appointments
                ELSE 0
            END,
            'average_ticket_reais', CASE
                WHEN cr.total_completed_appointments > 0
                THEN ROUND((cr.total_spent_cents::NUMERIC / cr.total_completed_appointments) / 100, 2)
                ELSE 0
            END,
            'last_purchase_at', cr.last_purchase_at
        ) as customer_data
        FROM "3a_customer_root_record" cr
        WHERE cr.inbox_id = p_inbox_id
          AND cr.total_spent_cents > 0
        ORDER BY cr.total_spent_cents DESC
        LIMIT p_limit
    ) top_customers;

    RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql;


-- =================================================================================================
-- VIEW DE CONVENIÊNCIA: Visão Consolidada de Faturamento por Cliente
-- =================================================================================================

-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ VIEW: vw_customer_billing_summary                                                           │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   View que mostra um resumo consolidado de faturamento por cliente.                         │
-- │                                                                                             │
-- │ COLUNAS:                                                                                    │
-- │   • root_id, client_id, treatment_name                                                      │
-- │   • total_spent_cents, total_spent_reais                                                    │
-- │   • total_completed_appointments                                                            │
-- │   • average_ticket_cents, average_ticket_reais                                              │
-- │   • first_purchase_at, last_purchase_at                                                     │
-- │   • customer_lifetime_days                                                                  │
-- │                                                                                             │
-- │ EXEMPLO DE USO:                                                                             │
-- │   -- Ver todos os clientes ordenados por LTV                                                │
-- │   SELECT * FROM vw_customer_billing_summary                                                 │
-- │   ORDER BY total_spent_cents DESC                                                           │
-- │   LIMIT 20;                                                                                 │
-- │                                                                                             │
-- │   -- Ver clientes que gastaram mais de R$ 1000                                              │
-- │   SELECT * FROM vw_customer_billing_summary                                                 │
-- │   WHERE total_spent_reais > 1000                                                            │
-- │   ORDER BY total_spent_cents DESC;                                                          │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE VIEW vw_customer_billing_summary AS
SELECT
    cr.id as root_id,
    cr.client_id,
    cr.inbox_id,
    cr.treatment_name,
    cr.total_spent_cents,
    ROUND(cr.total_spent_cents::NUMERIC / 100, 2) as total_spent_reais,
    cr.total_completed_appointments,
    CASE
        WHEN cr.total_completed_appointments > 0
        THEN cr.total_spent_cents / cr.total_completed_appointments
        ELSE 0
    END as average_ticket_cents,
    CASE
        WHEN cr.total_completed_appointments > 0
        THEN ROUND((cr.total_spent_cents::NUMERIC / cr.total_completed_appointments) / 100, 2)
        ELSE 0
    END as average_ticket_reais,
    cr.first_purchase_at,
    cr.last_purchase_at,
    CASE
        WHEN cr.first_purchase_at IS NOT NULL
        THEN EXTRACT(DAY FROM (COALESCE(cr.last_purchase_at, NOW()) - cr.first_purchase_at))::INT
        ELSE 0
    END as customer_lifetime_days,
    cr.created_at,
    cr.updated_at
FROM "3a_customer_root_record" cr
WHERE cr.total_spent_cents > 0
ORDER BY cr.total_spent_cents DESC;


-- =================================================================================================
-- FIM DAS FUNÇÕES
-- =================================================================================================
-- Para testar as funções:
--
-- FATURAMENTO POR TEMPO:
--   SELECT func_get_billing_today('your-inbox-uuid');
--   SELECT func_get_billing_last_n_days('your-inbox-uuid', 7);
--   SELECT func_get_billing_last_n_days('your-inbox-uuid', 30);
--   SELECT func_get_billing_specific_month('your-inbox-uuid', 2025, 1);
--
-- LTV POR CLIENTE:
--   SELECT func_get_customer_ltv(123);
--   SELECT func_get_top_customers_by_ltv('your-inbox-uuid', 10);
--   SELECT * FROM vw_customer_billing_summary LIMIT 20;
-- =================================================================================================
