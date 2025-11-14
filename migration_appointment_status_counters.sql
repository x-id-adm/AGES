-- ================================================================
-- MIGRAÇÃO: Adicionar contadores de status de atendimentos
-- ================================================================
-- Data: 2025-11-14
-- Descrição: Adiciona contadores automáticos para cada status
--            de atendimento na tabela 0b_inbox_counters
-- ================================================================

BEGIN;

-- Adicionar novos campos de contadores para status de atendimentos
ALTER TABLE "0b_inbox_counters"
    ADD COLUMN IF NOT EXISTS scheduled_count   INT NOT NULL DEFAULT 0,  -- Status mudado pelo Agente de IA
    ADD COLUMN IF NOT EXISTS confirmed_count   INT NOT NULL DEFAULT 0,  -- Status mudado pelo Agente de IA
    ADD COLUMN IF NOT EXISTS completed_count   INT NOT NULL DEFAULT 0,  -- Status mudado pelo Humano
    ADD COLUMN IF NOT EXISTS cancelled_count   INT NOT NULL DEFAULT 0,  -- Status mudado pelo Humano/IA
    ADD COLUMN IF NOT EXISTS rescheduled_count INT NOT NULL DEFAULT 0,  -- Status mudado pelo Humano
    ADD COLUMN IF NOT EXISTS no_show_count     INT NOT NULL DEFAULT 0;  -- Status mudado pelo Humano

COMMIT;

-- ================================================================
-- VERIFICAÇÃO: Para verificar se os campos foram criados:
-- ================================================================
-- SELECT column_name, data_type, column_default
-- FROM information_schema.columns
-- WHERE table_name = '0b_inbox_counters'
-- ORDER BY ordinal_position;
-- ================================================================
