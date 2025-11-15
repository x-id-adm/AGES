-- =================================================================================================
-- MIGRATION: Adicionar Timestamps de Status aos Agendamentos
-- =================================================================================================
-- DESCRIÇÃO:
--   Adiciona colunas para rastrear QUANDO cada status foi aplicado a um agendamento.
--   Permite queries do tipo: "Quantos clientes cancelaram em Janeiro?"
--
-- VERSÃO: 1.0
-- DATA: 2025-11-15
-- =================================================================================================

BEGIN;

-- =================================================================================================
-- 1. ADICIONAR COLUNAS DE TIMESTAMP POR STATUS
-- =================================================================================================

ALTER TABLE "4a_customer_service_history" ADD COLUMN IF NOT EXISTS
    scheduled_at TIMESTAMPTZ,    -- Quando foi agendado (status: Scheduled)
    confirmed_at TIMESTAMPTZ,    -- Quando foi confirmado (status: Confirmed)
    cancelled_at TIMESTAMPTZ,    -- Quando foi cancelado (status: Cancelled)
    completed_at TIMESTAMPTZ,    -- Quando foi completado (status: Completed)
    rescheduled_at TIMESTAMPTZ,  -- Quando foi reagendado (status: Rescheduled)
    no_show_at TIMESTAMPTZ;      -- Quando foi marcado como faltou (status: No_Show)

-- =================================================================================================
-- 2. CRIAR ÍNDICES PARA PERFORMANCE EM QUERIES POR PERÍODO
-- =================================================================================================

CREATE INDEX IF NOT EXISTS idx_appointment_scheduled_at   ON "4a_customer_service_history"(scheduled_at)   WHERE scheduled_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_appointment_confirmed_at   ON "4a_customer_service_history"(confirmed_at)   WHERE confirmed_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_appointment_cancelled_at   ON "4a_customer_service_history"(cancelled_at)   WHERE cancelled_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_appointment_completed_at   ON "4a_customer_service_history"(completed_at)   WHERE completed_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_appointment_rescheduled_at ON "4a_customer_service_history"(rescheduled_at) WHERE rescheduled_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_appointment_no_show_at     ON "4a_customer_service_history"(no_show_at)     WHERE no_show_at IS NOT NULL;

-- =================================================================================================
-- 3. POPULAR DADOS HISTÓRICOS (MIGRAÇÃO DE DADOS EXISTENTES)
-- =================================================================================================
-- Para registros já existentes, vamos usar o campo created_at como estimativa inicial
-- Isso garante que dados históricos sejam consultáveis

UPDATE "4a_customer_service_history"
SET
    scheduled_at = CASE WHEN service_status = 'Scheduled' THEN created_at ELSE NULL END,
    confirmed_at = CASE WHEN service_status = 'Confirmed' THEN created_at ELSE NULL END,
    cancelled_at = CASE WHEN service_status = 'Cancelled' THEN created_at ELSE NULL END,
    completed_at = CASE WHEN service_status = 'Completed' THEN created_at ELSE NULL END,
    rescheduled_at = CASE WHEN service_status = 'Rescheduled' THEN created_at ELSE NULL END,
    no_show_at = CASE WHEN service_status = 'No_Show' THEN created_at ELSE NULL END
WHERE
    scheduled_at IS NULL
    AND confirmed_at IS NULL
    AND cancelled_at IS NULL
    AND completed_at IS NULL
    AND rescheduled_at IS NULL
    AND no_show_at IS NULL;

COMMIT;

-- =================================================================================================
-- FIM DA MIGRATION
-- =================================================================================================
-- Para verificar se foi aplicada com sucesso:
--   SELECT column_name, data_type
--   FROM information_schema.columns
--   WHERE table_name = '4a_customer_service_history'
--   AND column_name LIKE '%_at';
-- =================================================================================================
