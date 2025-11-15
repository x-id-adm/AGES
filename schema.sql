-- ================================================================
-- SCHEMA COMPLETO ENUM e TABELAS
-- ================================================================
-- - EXECUÇÃO ÚNICA, ATÔMICA E IDEMPOTENTE
-- Este script pode ser executado múltiplas vezes sem erros
-- Todas as operações são idempotentes e atômicas
-- ================================================================

BEGIN;

-- ================================================================
-- ENUM: workflow_status
-- ================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'workflow_status') THEN
        CREATE TYPE workflow_status AS ENUM (
            '⚪',  -- Inativo/Neutro
            '⚫',  -- Bloqueado/Desabilitado
            '🧪',  -- Em Teste/Experimental
            '🟢',  -- Ativo/Operacional
            '🟡',  -- Atenção/Aguardando
            '🔴',  -- Erro/Problema
            '🚫'   -- Proibido/Suspenso
        );
    END IF;
END$$;

-- ================================================================
-- ENUM: message_sender_type
-- ================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_sender_type') THEN
        CREATE TYPE message_sender_type AS ENUM (
            'contact',     -- O contato final (cliente no WhatsApp)
            'ai_agent',    -- Agente de IA
            'human_agent', -- Atendente humano
            'system'       -- Mensagem do sistema
        );
    END IF;
END$$;

-- ================================================================
-- NÍVEL 0 - Inbox do Prestador
-- ================================================================
CREATE TABLE IF NOT EXISTS "0a_inbox_whatsapp" (
    inbox_id           UUID PRIMARY KEY NOT NULL,
    status_workflow    workflow_status NOT NULL DEFAULT '🟢',
    inbox_name         TEXT,
    avatar_inbox_url   TEXT,

    -- Cliente dono da Inbox
    client_name        TEXT,
    login_identity     TEXT,
    owner_wallet_id    UUID NOT NULL,

    -- Agente de IA Cockpit
    avatar_agent_url   TEXT,
    name_agent         TEXT,
    bio_agent          TEXT,

    -- Consumo de execuções da Inbox
    monthly_limit      BIGINT NOT NULL DEFAULT 0,
    credits_used       BIGINT NOT NULL DEFAULT 0,
    remaining_credits  BIGINT NOT NULL DEFAULT 0,

    -- Configurações dos dados Obrigatórios para considerar uma Ficha completa
    required_data_form JSONB,

    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS "0b_inbox_counters" (
    inbox_id          UUID PRIMARY KEY NOT NULL REFERENCES "0a_inbox_whatsapp"(inbox_id) ON DELETE CASCADE,

    -- Conta o número de contatos que iniciaram uma conversa na neste INBOX
    contact_count     INT NOT NULL DEFAULT 0,

    -- Conta o numero de contatos que fizeram a Ficha Completa
    -- com os dados de cadastro requeridos em "required_data_form"
    form_count        INT NOT NULL DEFAULT 0,

    -- Conta o numero de agendamentos totais realizados
    scheduling_count  INT NOT NULL DEFAULT 0,

    -- Contadores de status de atendimentos
    scheduled_count   INT NOT NULL DEFAULT 0,  -- Status mudado pelo Agente de IA
    confirmed_count   INT NOT NULL DEFAULT 0,  -- Status mudado pelo Agente de IA
    completed_count   INT NOT NULL DEFAULT 0,  -- Status mudado pelo Humano
    cancelled_count   INT NOT NULL DEFAULT 0,  -- Status mudado pelo Humano/IA
    rescheduled_count INT NOT NULL DEFAULT 0,  -- Status mudado pelo Humano
    no_show_count     INT NOT NULL DEFAULT 0,  -- Status mudado pelo Humano

    -- Taxas de conversão calculadas automaticamente (em tempo real)
    -- Formato: 0.9310 = 93.10% (confirmados/agendados)
    confirmed_rate    DECIMAL(5,4) GENERATED ALWAYS AS (
        CASE WHEN scheduled_count > 0 THEN ROUND(confirmed_count::DECIMAL / scheduled_count, 4) ELSE 0 END
    ) STORED,
    completed_rate    DECIMAL(5,4) GENERATED ALWAYS AS (
        CASE WHEN scheduled_count > 0 THEN ROUND(completed_count::DECIMAL / scheduled_count, 4) ELSE 0 END
    ) STORED,
    cancelled_rate    DECIMAL(5,4) GENERATED ALWAYS AS (
        CASE WHEN scheduled_count > 0 THEN ROUND(cancelled_count::DECIMAL / scheduled_count, 4) ELSE 0 END
    ) STORED,
    rescheduled_rate  DECIMAL(5,4) GENERATED ALWAYS AS (
        CASE WHEN scheduled_count > 0 THEN ROUND(rescheduled_count::DECIMAL / scheduled_count, 4) ELSE 0 END
    ) STORED,
    no_show_rate      DECIMAL(5,4) GENERATED ALWAYS AS (
        CASE WHEN scheduled_count > 0 THEN ROUND(no_show_count::DECIMAL / scheduled_count, 4) ELSE 0 END
    ) STORED,

    -- Taxas de conversão do funil de atendimento (contatos -> fichas -> agendamentos)
    -- Formato: 0.7500 = 75.00% (fichas/contatos)
    form_rate         DECIMAL(5,4) GENERATED ALWAYS AS (
        CASE WHEN contact_count > 0 THEN ROUND(form_count::DECIMAL / contact_count, 4) ELSE 0 END
    ) STORED,
    scheduling_rate   DECIMAL(5,4) GENERATED ALWAYS AS (
        CASE WHEN contact_count > 0 THEN ROUND(scheduling_count::DECIMAL / contact_count, 4) ELSE 0 END
    ) STORED
);

-- ================================================================
-- NÍVEL 1 - Contato de WhatsApp (wallet_id como PK)
-- ================================================================
CREATE TABLE IF NOT EXISTS "1a_whatsapp_user_contact" (
    wallet_id             UUID PRIMARY KEY NOT NULL,
    inbox_id              UUID NOT NULL REFERENCES "0a_inbox_whatsapp"(inbox_id) ON DELETE CASCADE,
    status_contact        workflow_status NOT NULL DEFAULT '🟢',
    status_agent          workflow_status NOT NULL DEFAULT '🟢',
    push_name             TEXT,
    latest_avatar_url     TEXT,
    phone_number          TEXT,
    country_flag_emoji    TEXT,
    country_code          VARCHAR(2),
    area_code             VARCHAR(5),
    contact_message_count BIGINT NOT NULL DEFAULT 0,
    ai_engagement         BIGINT NOT NULL DEFAULT 0,
    human_engagement      BIGINT NOT NULL DEFAULT 0,
    engagement_score      FLOAT NOT NULL DEFAULT 0.0,
    last_interaction_at   TIMESTAMPTZ,
    source_device         TEXT,
    energy_daily_credit   BIGINT NOT NULL DEFAULT 0,
    energy_current_balance BIGINT NOT NULL DEFAULT 0,
    tags                  JSONB NOT NULL DEFAULT '[]'::jsonb,
    condensed_memory      JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Índices para performance
CREATE INDEX IF NOT EXISTS idx_contact_inbox            ON "1a_whatsapp_user_contact"(inbox_id);
CREATE INDEX IF NOT EXISTS idx_contact_phone            ON "1a_whatsapp_user_contact"(phone_number) WHERE phone_number IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_contact_last_interaction ON "1a_whatsapp_user_contact"(last_interaction_at DESC);

-- ================================================================
-- NÍVEL 2 - Mensagens
-- ================================================================
CREATE TABLE IF NOT EXISTS "2a_temporary_messages" (
    id           BIGSERIAL PRIMARY KEY,
    wallet_id    UUID NOT NULL REFERENCES "1a_whatsapp_user_contact"(wallet_id) ON DELETE CASCADE,
    inbox_id     UUID NOT NULL REFERENCES "0a_inbox_whatsapp"(inbox_id) ON DELETE CASCADE,
    message      TEXT,
    message_id   TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_temp_msg_wallet     ON "2a_temporary_messages"(wallet_id);
CREATE INDEX IF NOT EXISTS idx_temp_msg_inbox      ON "2a_temporary_messages"(inbox_id);
CREATE INDEX IF NOT EXISTS idx_temp_msg_created    ON "2a_temporary_messages"(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_temp_msg_message_id ON "2a_temporary_messages"(message_id) WHERE message_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS "2b_conversation_messages" (
    id                 BIGSERIAL PRIMARY KEY,
    -- CAMPO ADICIONADO PARA O ID AMIGÁVEL --
    client_id           TEXT GENERATED ALWAYS AS ('CT' || id::text) STORED,
    wallet_id           UUID NOT NULL REFERENCES "1a_whatsapp_user_contact"(wallet_id) ON DELETE CASCADE,
    inbox_id            UUID NOT NULL REFERENCES "0a_inbox_whatsapp"(inbox_id) ON DELETE CASCADE,
    source_message_id   TEXT NOT NULL,
    message_timestamp   TIMESTAMPTZ NOT NULL,
    sender_type         message_sender_type NOT NULL,
    message_content     TEXT,
    lang                TEXT NOT NULL DEFAULT 'portuguese',
    message_content_tsv TSVECTOR,
    source_device       TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (inbox_id, source_message_id)
);

CREATE INDEX IF NOT EXISTS idx_conv_msg_wallet      ON "2b_conversation_messages"(wallet_id);
CREATE INDEX IF NOT EXISTS idx_conv_msg_inbox       ON "2b_conversation_messages"(inbox_id);
CREATE INDEX IF NOT EXISTS idx_conv_msg_timestamp   ON "2b_conversation_messages"(message_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_conv_msg_created     ON "2b_conversation_messages"(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_conv_msg_sender_type ON "2b_conversation_messages"(sender_type);
CREATE INDEX IF NOT EXISTS idx_conv_msg_source_id   ON "2b_conversation_messages"(source_message_id);
CREATE INDEX IF NOT EXISTS idx_conv_msg_tsv         ON "2b_conversation_messages" USING GIN(message_content_tsv);

-- ================================================================
-- NÍVEL 3 - Ficha de Cliente (Schema Corrigido)
-- ================================================================

-- 3a. Tabela Raiz da Ficha (Onde o gatilho será disparado)
CREATE TABLE IF NOT EXISTS "3a_customer_root_record" (
    id                  BIGSERIAL PRIMARY KEY,
    client_id           TEXT,
    inbox_id            UUID NOT NULL REFERENCES "0a_inbox_whatsapp"(inbox_id) ON DELETE CASCADE,
    treatment_name      TEXT NOT NULL,
    legal_name_complete TEXT,
    whatsapp_owner      TEXT NOT NULL, -- O N8N preenche este campo

    -- Espelho de todos os campos da ficha
    identity_data       JSONB NOT NULL DEFAULT '{}'::jsonb,

    -- Controle de formulário completo (baseado em required_data_form da inbox)
    is_form_complete    BOOLEAN NOT NULL DEFAULT FALSE,

    -- LTV (Lifetime Value) - Billing metrics
    total_spent_cents            BIGINT NOT NULL DEFAULT 0 CHECK (total_spent_cents >= 0),
    total_completed_appointments INTEGER NOT NULL DEFAULT 0 CHECK (total_completed_appointments >= 0),
    first_purchase_at            TIMESTAMPTZ,
    last_purchase_at             TIMESTAMPTZ,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_customer_inbox    ON "3a_customer_root_record"(inbox_id);
CREATE INDEX IF NOT EXISTS idx_customer_whatsapp ON "3a_customer_root_record"(whatsapp_owner) WHERE whatsapp_owner IS NOT NULL;

-- Indexes for LTV queries
CREATE INDEX IF NOT EXISTS idx_customer_total_spent ON "3a_customer_root_record"(total_spent_cents DESC) WHERE total_spent_cents > 0;
CREATE INDEX IF NOT EXISTS idx_customer_last_purchase ON "3a_customer_root_record"(last_purchase_at DESC) WHERE last_purchase_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_customer_completed_count ON "3a_customer_root_record"(total_completed_appointments DESC) WHERE total_completed_appointments > 0;

-- 3b. Guarda os telefones celular do cliente (1-para-N)
CREATE TABLE IF NOT EXISTS "3b_cell_phone_linked_service_sheet" (
    id          BIGSERIAL PRIMARY KEY,
    root_id     BIGINT NOT NULL REFERENCES "3a_customer_root_record"(id) ON DELETE CASCADE,
    wallet_id   UUID NOT NULL REFERENCES "1a_whatsapp_user_contact"(wallet_id) ON DELETE CASCADE,
    cell_phone  TEXT NOT NULL, -- Campo que será duplicado do 'whatsapp_owner'
    role        TEXT NOT NULL DEFAULT 'secundario' CHECK (role IN ('primario', 'secundario')),
    is_whatsapp BOOLEAN NOT NULL DEFAULT TRUE,
    verified    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(root_id, wallet_id) -- A chave única agora é o 'root_id' + 'wallet_id'
);
CREATE INDEX IF NOT EXISTS idx_cell_phone_root   ON "3b_cell_phone_linked_service_sheet"(root_id);
CREATE INDEX IF NOT EXISTS idx_cell_phone_wallet ON "3b_cell_phone_linked_service_sheet"(wallet_id);

-- 3c. Genero do cliente (1-para-1)
CREATE TABLE IF NOT EXISTS "3c_gender" (
    id         BIGSERIAL PRIMARY KEY,
    root_id    BIGINT NOT NULL REFERENCES "3a_customer_root_record"(id) ON DELETE CASCADE,
    gender     TEXT CHECK (gender IN ('masculino', 'feminino', 'outro', 'prefere_nao_dizer')),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(root_id)
);

-- 3d. Data de nascimento do cliente (1-para-1)
CREATE TABLE IF NOT EXISTS "3d_birth_date" (
    id         BIGSERIAL PRIMARY KEY,
    root_id    BIGINT NOT NULL REFERENCES "3a_customer_root_record"(id) ON DELETE CASCADE,
    birth_date DATE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(root_id)
);

-- 3e. Guarda o(s) emails(s) do cliente (1-para-N)
CREATE TABLE IF NOT EXISTS "3e_email" (
    id          BIGSERIAL PRIMARY KEY,
    root_id     BIGINT NOT NULL REFERENCES "3a_customer_root_record"(id) ON DELETE CASCADE,
    email       TEXT NOT NULL,
    label       TEXT,
    is_primary  BOOLEAN NOT NULL DEFAULT FALSE,
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(root_id, email)
);

CREATE INDEX IF NOT EXISTS idx_email_root    ON "3e_email"(root_id);
CREATE INDEX IF NOT EXISTS idx_email_address ON "3e_email"(email);

-- 3f. Guarda Telefone Fixo do Cliente (1-para-N)
CREATE TABLE IF NOT EXISTS "3f_landline_phone" (
    id           BIGSERIAL PRIMARY KEY,
    root_id      BIGINT NOT NULL REFERENCES "3a_customer_root_record"(id) ON DELETE CASCADE,
    phone_number TEXT NOT NULL,
    label        TEXT,
    is_primary   BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(root_id, phone_number)
);

-- 3g. Grava o CPF do cliente (1-para-1)
CREATE TABLE IF NOT EXISTS "3g_cpf" (
    id         BIGSERIAL PRIMARY KEY,
    root_id    BIGINT NOT NULL REFERENCES "3a_customer_root_record"(id) ON DELETE CASCADE,
    inbox_id   UUID NOT NULL REFERENCES "0a_inbox_whatsapp"(inbox_id) ON DELETE CASCADE,
    cpf        TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(root_id),
    UNIQUE(inbox_id, cpf)
);

CREATE INDEX IF NOT EXISTS idx_cpf_inbox ON "3g_cpf"(inbox_id);

-- 3h. RG do cliente (1-para-1)
CREATE TABLE IF NOT EXISTS "3h_rg" (
    id               BIGSERIAL PRIMARY KEY,
    root_id          BIGINT NOT NULL REFERENCES "3a_customer_root_record"(id) ON DELETE CASCADE,
    inbox_id         UUID NOT NULL REFERENCES "0a_inbox_whatsapp"(inbox_id) ON DELETE CASCADE,
    rg_numero        TEXT NOT NULL,
    rg_orgao_emissor TEXT,
    rg_uf_emissor    CHAR(2),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(root_id),
    UNIQUE(inbox_id, rg_numero)
);

CREATE INDEX IF NOT EXISTS idx_rg_inbox ON "3h_rg"(inbox_id);

-- 3i. Endereços do cliente (1-para-N)
CREATE TABLE IF NOT EXISTS "3i_endereco_br" (
    id          BIGSERIAL PRIMARY KEY,
    root_id     BIGINT NOT NULL REFERENCES "3a_customer_root_record"(id) ON DELETE CASCADE,
    cep         TEXT,
    logradouro  TEXT,
    numero      TEXT,
    complemento TEXT,
    bairro      TEXT,
    cidade      TEXT,
    estado      TEXT,
    pais        TEXT NOT NULL DEFAULT 'Brasil',
    tipo        TEXT DEFAULT 'Residencial' CHECK (tipo IN ('Residencial', 'Comercial', 'Hotel')),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- CORRIGIDO: Nome da tabela de "3i_endereco" para "3i_endereco_br"
CREATE INDEX IF NOT EXISTS idx_endereco_root ON "3i_endereco_br"(root_id);
CREATE INDEX IF NOT EXISTS idx_endereco_cep  ON "3i_endereco_br"(cep) WHERE cep IS NOT NULL;

-- 3j. Veículos do cliente (1-para-N)
CREATE TABLE IF NOT EXISTS "3j_veiculos_br" (
    id                  BIGSERIAL PRIMARY KEY,
    root_id             BIGINT NOT NULL REFERENCES "3a_customer_root_record"(id) ON DELETE CASCADE,

    -- Identificação Principal
    placa               TEXT NOT NULL,              -- Ex: "ABC1D23" (Mercosul) ou "ABC-1234" (antiga)
    renavam             TEXT,                       -- Código RENAVAM (11 dígitos)
    chassi              TEXT,                       -- Número do chassi/VIN

    -- Classificação do Veículo
    tipo_veiculo        TEXT NOT NULL DEFAULT 'carro' CHECK (tipo_veiculo IN (
                            'moto', 'carro', 'camionete', 'suv', 'van',
                            'caminhao', 'onibus', 'triciclo', 'quadriciclo', 'outro'
                        )),

    -- Dados do Veículo
    marca               TEXT,                       -- Ex: "Volkswagen", "Honda"
    modelo              TEXT NOT NULL,              -- Ex: "Gol", "Civic", "CG 160"
    versao              TEXT,                       -- Ex: "1.0 Turbo TSI", "EX-L"
    ano_fabricacao      INTEGER CHECK (ano_fabricacao >= 1900 AND ano_fabricacao <= 2100),
    ano_modelo          INTEGER CHECK (ano_modelo >= 1900 AND ano_modelo <= 2100),
    cor                 TEXT,                       -- Ex: "Prata", "Preto", "Branco"
    combustivel         TEXT CHECK (combustivel IN (
                            'gasolina', 'etanol', 'flex', 'diesel', 'gnv', 'eletrico', 'hibrido'
                        )),

    -- Informações Adicionais
    quilometragem       INTEGER CHECK (quilometragem >= 0),  -- KM atual (útil para oficinas)
    apelido             TEXT,                       -- Nome carinhoso: "Carro da esposa", "Moto do trabalho"
    observacoes         TEXT,                       -- Notas livres

    -- Sistema de Segurança (URLs de fotos)
    url_foto_entrada    TEXT,                       -- Link para foto de entrada
    urls_adicionais     JSONB DEFAULT '[]'::jsonb,  -- Array de URLs extras [{"url": "...", "descricao": "..."}]

    -- Status e Controle
    is_principal        BOOLEAN NOT NULL DEFAULT FALSE,  -- Veículo principal do cliente
    is_ativo            BOOLEAN NOT NULL DEFAULT TRUE,   -- Se ainda é do cliente

    -- Auditoria
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Constraints
    UNIQUE(root_id, placa)  -- Um cliente não pode ter a mesma placa duas vezes
);

-- Índices para performance
CREATE INDEX IF NOT EXISTS idx_veiculos_root_id ON "3j_veiculos_br"(root_id);
CREATE INDEX IF NOT EXISTS idx_veiculos_placa   ON "3j_veiculos_br"(placa);
CREATE INDEX IF NOT EXISTS idx_veiculos_tipo    ON "3j_veiculos_br"(tipo_veiculo);
CREATE INDEX IF NOT EXISTS idx_veiculos_modelo  ON "3j_veiculos_br"(modelo);

-- ================================================================
-- NÍVEL 4 - Histórico de Agendamentos
-- ================================================================
CREATE TABLE IF NOT EXISTS "4a_customer_service_history" (
    id BIGSERIAL PRIMARY KEY,
    service_id TEXT,
    inbox_id UUID  NOT NULL REFERENCES "0a_inbox_whatsapp"(inbox_id) ON DELETE CASCADE,

    -- CORRIGIDO: Referência para "3a_customer_root_record"
    root_id BIGINT NOT NULL REFERENCES "3a_customer_root_record"(id) ON DELETE CASCADE,

    -- CORRIGIDO: Tipo para UUID e referência para (wallet_id)
    scheduled_by_wallet_id  UUID REFERENCES "1a_whatsapp_user_contact"(wallet_id) ON DELETE SET NULL,

    -- Dados do Serviço Agendado
    service_datetime_start  TIMESTAMPTZ NOT NULL,
    service_datetime_end    TIMESTAMPTZ NOT NULL,
    service_status          TEXT DEFAULT 'Scheduled' CHECK (service_status  IN ('Scheduled', 'Confirmed', 'Completed', 'Cancelled', 'Rescheduled', 'No_Show')),
    service_type            TEXT,
    is_online               BOOLEAN NOT NULL DEFAULT FALSE,
    calendar_name           TEXT,  -- nome do calendário (geralmente o nome do profissinal, exemplo: "Dra Alessandra Ribeiro")
    location_event          TEXT,  -- local onde o serviço será prestado (online, endereço da clinica ou endereço do cliente quando for a domicilio)

    -- Campos Financeiros e Fiscais
    value_cents         INTEGER CHECK (value_cents >= 0),
    payment_method      TEXT,
    requires_invoice    BOOLEAN NOT NULL DEFAULT FALSE,
    invoice_status      TEXT DEFAULT 'Nao_Necessario' CHECK (invoice_status IN ('Nao_Necessario', 'Pendente', 'Emitida', 'Enviada_Cliente', 'Falha')),

    -- Observações e Anexos
    notes               TEXT,
    follow_up_date      TIMESTAMPTZ,
    attachments         JSONB,

    -- Timestamps de Mudanças de Status (para contadores temporais)
    scheduled_at        TIMESTAMPTZ,  -- Quando recebeu status 'Scheduled'
    confirmed_at        TIMESTAMPTZ,  -- Quando recebeu status 'Confirmed'
    completed_at        TIMESTAMPTZ,  -- Quando recebeu status 'Completed'
    cancelled_at        TIMESTAMPTZ,  -- Quando recebeu status 'Cancelled'
    rescheduled_at      TIMESTAMPTZ,  -- Quando recebeu status 'Rescheduled'
    no_show_at          TIMESTAMPTZ,  -- Quando recebeu status 'No_Show'

    -- Campos de Auditoria
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Índices para performance em queries por período
CREATE INDEX IF NOT EXISTS idx_appointment_scheduled_at   ON "4a_customer_service_history"(scheduled_at)   WHERE scheduled_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_appointment_confirmed_at   ON "4a_customer_service_history"(confirmed_at)   WHERE confirmed_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_appointment_cancelled_at   ON "4a_customer_service_history"(cancelled_at)   WHERE cancelled_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_appointment_completed_at   ON "4a_customer_service_history"(completed_at)   WHERE completed_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_appointment_rescheduled_at ON "4a_customer_service_history"(rescheduled_at) WHERE rescheduled_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_appointment_no_show_at     ON "4a_customer_service_history"(no_show_at)     WHERE no_show_at IS NOT NULL;

COMMIT;


