-- =================================================================================================
-- FUNÇÕES PARA CONTADORES BASEADOS EM TEMPO
-- =================================================================================================
-- DESCRIÇÃO:
--   Funções para consultar contadores de agendamentos filtrados por período de tempo.
--   Permite queries como: "Quantos agendamentos foram criados nos últimos 7 dias?"
--                        "Quantos clientes cancelaram em Janeiro?"
--
-- VERSÃO: 1.0
-- DATA: 2025-11-15
-- =================================================================================================


-- =================================================================================================
-- FUNÇÃO PRINCIPAL: Contadores de Agendamentos por Período
-- =================================================================================================

-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNÇÃO: func_get_appointment_counters_by_period                                             │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   Retorna contadores de agendamentos (total e por status) para um período de tempo          │
-- │   específico, baseado em QUANDO o status foi aplicado.                                      │
-- │                                                                                             │
-- │ PARÂMETROS:                                                                                 │
-- │   p_inbox_id (UUID) - ID da inbox para filtrar                                              │
-- │   p_start_date (TIMESTAMPTZ) - Data/hora de início do período (inclusivo)                   │
-- │   p_end_date (TIMESTAMPTZ) - Data/hora de fim do período (exclusivo)                        │
-- │                                                                                             │
-- │ RETORNO:                                                                                    │
-- │   JSONB com estrutura:                                                                      │
-- │   {                                                                                         │
-- │     "total_appointments": 150,                                                              │
-- │     "scheduled_count": 45,                                                                  │
-- │     "confirmed_count": 60,                                                                  │
-- │     "completed_count": 30,                                                                  │
-- │     "cancelled_count": 10,                                                                  │
-- │     "rescheduled_count": 4,                                                                 │
-- │     "no_show_count": 1,                                                                     │
-- │     "period": {                                                                             │
-- │       "start": "2025-01-01T00:00:00Z",                                                      │
-- │       "end": "2025-02-01T00:00:00Z"                                                         │
-- │     }                                                                                       │
-- │   }                                                                                         │
-- │                                                                                             │
-- │ LÓGICA:                                                                                     │
-- │   Para cada status, conta quantos agendamentos tiveram aquele status aplicado              │
-- │   dentro do período especificado.                                                           │
-- │                                                                                             │
-- │ EXEMPLO DE USO:                                                                             │
-- │   -- Últimos 7 dias                                                                         │
-- │   SELECT func_get_appointment_counters_by_period(                                           │
-- │       'uuid-da-inbox',                                                                      │
-- │       NOW() - INTERVAL '7 days',                                                            │
-- │       NOW()                                                                                 │
-- │   );                                                                                        │
-- │                                                                                             │
-- │   -- Mês de Janeiro de 2025                                                                 │
-- │   SELECT func_get_appointment_counters_by_period(                                           │
-- │       'uuid-da-inbox',                                                                      │
-- │       '2025-01-01 00:00:00'::TIMESTAMPTZ,                                                   │
-- │       '2025-02-01 00:00:00'::TIMESTAMPTZ                                                    │
-- │   );                                                                                        │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION func_get_appointment_counters_by_period(
    p_inbox_id UUID,
    p_start_date TIMESTAMPTZ,
    p_end_date TIMESTAMPTZ
)
RETURNS JSONB AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'total_appointments', COUNT(*),
        'scheduled_count', COUNT(*) FILTER (WHERE scheduled_at >= p_start_date AND scheduled_at < p_end_date),
        'confirmed_count', COUNT(*) FILTER (WHERE confirmed_at >= p_start_date AND confirmed_at < p_end_date),
        'completed_count', COUNT(*) FILTER (WHERE completed_at >= p_start_date AND completed_at < p_end_date),
        'cancelled_count', COUNT(*) FILTER (WHERE cancelled_at >= p_start_date AND cancelled_at < p_end_date),
        'rescheduled_count', COUNT(*) FILTER (WHERE rescheduled_at >= p_start_date AND rescheduled_at < p_end_date),
        'no_show_count', COUNT(*) FILTER (WHERE no_show_at >= p_start_date AND no_show_at < p_end_date),
        'period', jsonb_build_object(
            'start', p_start_date,
            'end', p_end_date
        )
    ) INTO v_result
    FROM "4a_customer_service_history"
    WHERE inbox_id = p_inbox_id
      AND created_at >= p_start_date
      AND created_at < p_end_date;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;


-- =================================================================================================
-- FUNÇÕES DE CONVENIÊNCIA: Períodos Comuns
-- =================================================================================================

-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNÇÃO: func_get_counters_last_n_days                                                       │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   Retorna contadores dos últimos N dias.                                                    │
-- │                                                                                             │
-- │ EXEMPLO DE USO:                                                                             │
-- │   -- Últimos 7 dias                                                                         │
-- │   SELECT func_get_counters_last_n_days('uuid-inbox', 7);                                    │
-- │                                                                                             │
-- │   -- Últimos 30 dias                                                                        │
-- │   SELECT func_get_counters_last_n_days('uuid-inbox', 30);                                   │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION func_get_counters_last_n_days(
    p_inbox_id UUID,
    p_days INT
)
RETURNS JSONB AS $$
BEGIN
    RETURN func_get_appointment_counters_by_period(
        p_inbox_id,
        NOW() - (p_days || ' days')::INTERVAL,
        NOW()
    );
END;
$$ LANGUAGE plpgsql;


-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNÇÃO: func_get_counters_specific_month                                                    │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   Retorna contadores de um mês específico.                                                  │
-- │                                                                                             │
-- │ PARÂMETROS:                                                                                 │
-- │   p_inbox_id (UUID) - ID da inbox                                                           │
-- │   p_year (INT) - Ano (ex: 2025)                                                             │
-- │   p_month (INT) - Mês (1-12)                                                                │
-- │                                                                                             │
-- │ EXEMPLO DE USO:                                                                             │
-- │   -- Janeiro de 2025                                                                        │
-- │   SELECT func_get_counters_specific_month('uuid-inbox', 2025, 1);                           │
-- │                                                                                             │
-- │   -- Fevereiro de 2025                                                                      │
-- │   SELECT func_get_counters_specific_month('uuid-inbox', 2025, 2);                           │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION func_get_counters_specific_month(
    p_inbox_id UUID,
    p_year INT,
    p_month INT
)
RETURNS JSONB AS $$
DECLARE
    v_start_date TIMESTAMPTZ;
    v_end_date TIMESTAMPTZ;
BEGIN
    -- Primeiro dia do mês às 00:00:00
    v_start_date := make_timestamptz(p_year, p_month, 1, 0, 0, 0);

    -- Primeiro dia do mês seguinte às 00:00:00
    v_end_date := v_start_date + INTERVAL '1 month';

    RETURN func_get_appointment_counters_by_period(
        p_inbox_id,
        v_start_date,
        v_end_date
    );
END;
$$ LANGUAGE plpgsql;


-- =================================================================================================
-- FUNÇÕES ESPECÍFICAS POR STATUS
-- =================================================================================================

-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNÇÃO: func_count_status_changes                                                           │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   Conta quantos agendamentos mudaram para um status específico em um período.               │
-- │                                                                                             │
-- │ PARÂMETROS:                                                                                 │
-- │   p_inbox_id (UUID) - ID da inbox                                                           │
-- │   p_status (TEXT) - Status desejado: 'Scheduled', 'Confirmed', 'Completed',                 │
-- │                     'Cancelled', 'Rescheduled', 'No_Show'                                   │
-- │   p_start_date (TIMESTAMPTZ) - Início do período                                            │
-- │   p_end_date (TIMESTAMPTZ) - Fim do período                                                 │
-- │                                                                                             │
-- │ RETORNO:                                                                                    │
-- │   INTEGER - Quantidade de agendamentos que mudaram para aquele status no período            │
-- │                                                                                             │
-- │ EXEMPLO DE USO:                                                                             │
-- │   -- Quantos cancelaram nos últimos 7 dias?                                                 │
-- │   SELECT func_count_status_changes(                                                         │
-- │       'uuid-inbox',                                                                         │
-- │       'Cancelled',                                                                          │
-- │       NOW() - INTERVAL '7 days',                                                            │
-- │       NOW()                                                                                 │
-- │   );                                                                                        │
-- │                                                                                             │
-- │   -- Quantos foram confirmados em Janeiro?                                                  │
-- │   SELECT func_count_status_changes(                                                         │
-- │       'uuid-inbox',                                                                         │
-- │       'Confirmed',                                                                          │
-- │       '2025-01-01'::TIMESTAMPTZ,                                                            │
-- │       '2025-02-01'::TIMESTAMPTZ                                                             │
-- │   );                                                                                        │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION func_count_status_changes(
    p_inbox_id UUID,
    p_status TEXT,
    p_start_date TIMESTAMPTZ,
    p_end_date TIMESTAMPTZ
)
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER;
    v_column_name TEXT;
BEGIN
    -- Mapeia o status para o nome da coluna correspondente
    v_column_name := CASE p_status
        WHEN 'Scheduled' THEN 'scheduled_at'
        WHEN 'Confirmed' THEN 'confirmed_at'
        WHEN 'Completed' THEN 'completed_at'
        WHEN 'Cancelled' THEN 'cancelled_at'
        WHEN 'Rescheduled' THEN 'rescheduled_at'
        WHEN 'No_Show' THEN 'no_show_at'
        ELSE NULL
    END;

    -- Se o status não for válido, retorna 0
    IF v_column_name IS NULL THEN
        RAISE WARNING 'Status inválido: %. Valores válidos: Scheduled, Confirmed, Completed, Cancelled, Rescheduled, No_Show', p_status;
        RETURN 0;
    END IF;

    -- Conta quantos registros têm o timestamp do status dentro do período
    EXECUTE format('
        SELECT COUNT(*)
        FROM "4a_customer_service_history"
        WHERE inbox_id = $1
          AND %I >= $2
          AND %I < $3
    ', v_column_name, v_column_name)
    INTO v_count
    USING p_inbox_id, p_start_date, p_end_date;

    RETURN COALESCE(v_count, 0);
END;
$$ LANGUAGE plpgsql;


-- =================================================================================================
-- VIEWS DE CONVENIÊNCIA
-- =================================================================================================

-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ VIEW: vw_appointment_status_timeline                                                        │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   View que mostra todos os agendamentos com seus timestamps de status de forma organizada.  │
-- │                                                                                             │
-- │ COLUNAS:                                                                                    │
-- │   • service_id, inbox_id, root_id                                                           │
-- │   • service_status (status atual)                                                           │
-- │   • Todos os timestamps (_at)                                                               │
-- │   • created_at (quando foi criado)                                                          │
-- │                                                                                             │
-- │ EXEMPLO DE USO:                                                                             │
-- │   -- Ver histórico de um agendamento específico                                             │
-- │   SELECT * FROM vw_appointment_status_timeline WHERE service_id = 'AT123';                  │
-- │                                                                                             │
-- │   -- Ver todos cancelamentos de Fevereiro                                                   │
-- │   SELECT service_id, cancelled_at                                                           │
-- │   FROM vw_appointment_status_timeline                                                       │
-- │   WHERE cancelled_at >= '2025-02-01'                                                        │
-- │     AND cancelled_at < '2025-03-01';                                                        │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE VIEW vw_appointment_status_timeline AS
SELECT
    service_id,
    inbox_id,
    root_id,
    service_status,
    scheduled_at,
    confirmed_at,
    completed_at,
    cancelled_at,
    rescheduled_at,
    no_show_at,
    created_at,
    updated_at
FROM "4a_customer_service_history"
ORDER BY created_at DESC;


-- =================================================================================================
-- FIM DAS FUNÇÕES
-- =================================================================================================
-- Para testar as funções:
--   SELECT func_get_counters_last_n_days('your-inbox-uuid', 7);
--   SELECT func_get_counters_specific_month('your-inbox-uuid', 2025, 2);
--   SELECT func_count_status_changes('your-inbox-uuid', 'Cancelled', NOW() - INTERVAL '30 days', NOW());
--   SELECT * FROM vw_appointment_status_timeline LIMIT 10;
-- =================================================================================================
