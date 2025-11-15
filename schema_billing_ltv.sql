-- =================================================================================================
-- SCHEMA: CAMPOS DE FATURAMENTO E LTV (LIFETIME VALUE)
-- =================================================================================================
-- DESCRIÇÃO:
--   Adiciona campos para rastreamento de faturamento total por cliente (LTV - Lifetime Value)
--   na tabela 3a_customer_root_record.
--
-- PROPÓSITO:
--   - Rastrear quanto cada cliente já gastou ao longo do tempo
--   - Facilitar cálculo de LTV (Lifetime Value)
--   - Manter histórico de primeira e última compra
--   - Contar quantos atendimentos foram completados
--
-- VERSÃO: 1.0
-- DATA: 2025-11-15
-- =================================================================================================

BEGIN;

-- =================================================================================================
-- Adicionar campos de LTV na tabela 3a_customer_root_record
-- =================================================================================================

-- Adicionar coluna: total_spent_cents (valor total gasto em centavos)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = '3a_customer_root_record'
        AND column_name = 'total_spent_cents'
    ) THEN
        ALTER TABLE "3a_customer_root_record"
        ADD COLUMN total_spent_cents INTEGER NOT NULL DEFAULT 0 CHECK (total_spent_cents >= 0);

        RAISE NOTICE 'Coluna total_spent_cents adicionada com sucesso';
    ELSE
        RAISE NOTICE 'Coluna total_spent_cents já existe';
    END IF;
END$$;

-- Adicionar coluna: total_completed_appointments (quantidade de atendimentos finalizados)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = '3a_customer_root_record'
        AND column_name = 'total_completed_appointments'
    ) THEN
        ALTER TABLE "3a_customer_root_record"
        ADD COLUMN total_completed_appointments INTEGER NOT NULL DEFAULT 0 CHECK (total_completed_appointments >= 0);

        RAISE NOTICE 'Coluna total_completed_appointments adicionada com sucesso';
    ELSE
        RAISE NOTICE 'Coluna total_completed_appointments já existe';
    END IF;
END$$;

-- Adicionar coluna: first_purchase_at (data da primeira compra)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = '3a_customer_root_record'
        AND column_name = 'first_purchase_at'
    ) THEN
        ALTER TABLE "3a_customer_root_record"
        ADD COLUMN first_purchase_at TIMESTAMPTZ;

        RAISE NOTICE 'Coluna first_purchase_at adicionada com sucesso';
    ELSE
        RAISE NOTICE 'Coluna first_purchase_at já existe';
    END IF;
END$$;

-- Adicionar coluna: last_purchase_at (data da última compra)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = '3a_customer_root_record'
        AND column_name = 'last_purchase_at'
    ) THEN
        ALTER TABLE "3a_customer_root_record"
        ADD COLUMN last_purchase_at TIMESTAMPTZ;

        RAISE NOTICE 'Coluna last_purchase_at adicionada com sucesso';
    ELSE
        RAISE NOTICE 'Coluna last_purchase_at já existe';
    END IF;
END$$;

-- =================================================================================================
-- Criar índice para facilitar queries de LTV
-- =================================================================================================

-- Índice para ordenar clientes por valor total gasto (top clientes)
CREATE INDEX IF NOT EXISTS idx_customer_total_spent
ON "3a_customer_root_record"(total_spent_cents DESC)
WHERE total_spent_cents > 0;

-- Índice para ordenar por última compra
CREATE INDEX IF NOT EXISTS idx_customer_last_purchase
ON "3a_customer_root_record"(last_purchase_at DESC)
WHERE last_purchase_at IS NOT NULL;

-- Índice para ordenar por quantidade de atendimentos
CREATE INDEX IF NOT EXISTS idx_customer_completed_count
ON "3a_customer_root_record"(total_completed_appointments DESC)
WHERE total_completed_appointments > 0;

COMMIT;

-- =================================================================================================
-- RESUMO DAS ALTERAÇÕES
-- =================================================================================================
-- Tabela modificada: 3a_customer_root_record
--
-- Novos campos:
--   • total_spent_cents (INTEGER) - Total gasto pelo cliente em centavos
--   • total_completed_appointments (INTEGER) - Quantidade de atendimentos completados
--   • first_purchase_at (TIMESTAMPTZ) - Data da primeira compra
--   • last_purchase_at (TIMESTAMPTZ) - Data da última compra
--
-- Novos índices:
--   • idx_customer_total_spent - Para queries de top clientes por valor
--   • idx_customer_last_purchase - Para queries de clientes recentes
--   • idx_customer_completed_count - Para queries de clientes frequentes
-- =================================================================================================
