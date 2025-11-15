BEGIN;
DO $do_block$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'workflow_status') THEN
        CREATE TYPE workflow_status AS ENUM (
            '⚪',  -- *Coringa: Inativo/Neutro
            '⚫',  -- *Coringa: Bloqueado/Desabilitado
            '🧪',  -- *Coringa: Em Teste/Experimental
            '🟢',  -- *Coringa: Ativo/Operacional
            '🟡',  -- *Coringa: Atenção/Aguardando
            '🔴',  -- *Coringa: Erro/Problema
            '🚫'   -- *Coringa: Proibido/Suspenso
        );
    END IF;
END$do_block$;
DO $do_block$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_sender_type') THEN
        CREATE TYPE message_sender_type AS ENUM (
            'contact',     -- O contato final (cliente no WhatsApp)
            'ai_agent',    -- Agente de IA
            'human_agent', -- Atendente humano
            'system'       -- Mensagem do sistema
        );
    END IF;
END$do_block$;
CREATE TABLE IF NOT EXISTS "0a_inbox_whatsapp" (
    inbox_id           UUID PRIMARY KEY NOT NULL,
    status_workflow    workflow_status NOT NULL DEFAULT '🟢',
    inbox_name         TEXT,
    avatar_inbox_url   TEXT,
    client_name        TEXT,
    login_identity     TEXT,
    owner_wallet_id    UUID NOT NULL,
    avatar_agent_url   TEXT,
    name_agent         TEXT,
    bio_agent          TEXT,
    monthly_limit      BIGINT NOT NULL DEFAULT 0,
    credits_used       BIGINT NOT NULL DEFAULT 0,
    remaining_credits  BIGINT NOT NULL DEFAULT 0,
    required_data_form JSONB,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS "0b_inbox_counters" (
    inbox_id          UUID PRIMARY KEY NOT NULL REFERENCES "0a_inbox_whatsapp"(inbox_id) ON DELETE CASCADE,
    contact_count     INT NOT NULL DEFAULT 0,
    form_count        INT NOT NULL DEFAULT 0,
    scheduling_count  INT NOT NULL DEFAULT 0,
    scheduled_count   INT NOT NULL DEFAULT 0,  -- Status mudado pelo Agente de IA
    confirmed_count   INT NOT NULL DEFAULT 0,  -- Status mudado pelo Agente de IA
    completed_count   INT NOT NULL DEFAULT 0,  -- Status mudado pelo Humano
    cancelled_count   INT NOT NULL DEFAULT 0,  -- Status mudado pelo Humano/IA
    rescheduled_count INT NOT NULL DEFAULT 0,  -- Status mudado pelo Humano
    no_show_count     INT NOT NULL DEFAULT 0,  -- Status mudado pelo Humano
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
    form_rate         DECIMAL(5,4) GENERATED ALWAYS AS (
        CASE WHEN contact_count > 0 THEN ROUND(form_count::DECIMAL / contact_count, 4) ELSE 0 END
    ) STORED,
    scheduling_rate   DECIMAL(5,4) GENERATED ALWAYS AS (
        CASE WHEN contact_count > 0 THEN ROUND(scheduling_count::DECIMAL / contact_count, 4) ELSE 0 END
    ) STORED
);
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
CREATE INDEX IF NOT EXISTS idx_contact_inbox            ON "1a_whatsapp_user_contact"(inbox_id);
CREATE INDEX IF NOT EXISTS idx_contact_phone            ON "1a_whatsapp_user_contact"(phone_number) WHERE phone_number IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_contact_last_interaction ON "1a_whatsapp_user_contact"(last_interaction_at DESC);
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
CREATE TABLE IF NOT EXISTS "3a_customer_root_record" (
    id                  BIGSERIAL PRIMARY KEY,
    client_id           TEXT,
    inbox_id            UUID NOT NULL REFERENCES "0a_inbox_whatsapp"(inbox_id) ON DELETE CASCADE,
    treatment_name      TEXT NOT NULL,
    legal_name_complete TEXT,
    whatsapp_owner      TEXT NOT NULL, -- O N8N preenche este campo
    identity_data       JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_form_complete    BOOLEAN NOT NULL DEFAULT FALSE,
    total_spent_cents            BIGINT NOT NULL DEFAULT 0 CHECK (total_spent_cents >= 0),
    total_completed_appointments INTEGER NOT NULL DEFAULT 0 CHECK (total_completed_appointments >= 0),
    first_purchase_at            TIMESTAMPTZ,
    last_purchase_at             TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_customer_inbox    ON "3a_customer_root_record"(inbox_id);
CREATE INDEX IF NOT EXISTS idx_customer_whatsapp ON "3a_customer_root_record"(whatsapp_owner) WHERE whatsapp_owner IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_customer_total_spent ON "3a_customer_root_record"(total_spent_cents DESC) WHERE total_spent_cents > 0;
CREATE INDEX IF NOT EXISTS idx_customer_last_purchase ON "3a_customer_root_record"(last_purchase_at DESC) WHERE last_purchase_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_customer_completed_count ON "3a_customer_root_record"(total_completed_appointments DESC) WHERE total_completed_appointments > 0;
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
CREATE TABLE IF NOT EXISTS "3c_gender" (
    id         BIGSERIAL PRIMARY KEY,
    root_id    BIGINT NOT NULL REFERENCES "3a_customer_root_record"(id) ON DELETE CASCADE,
    gender     TEXT CHECK (gender IN ('masculino', 'feminino', 'outro', 'prefere_nao_dizer')),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(root_id)
);
CREATE TABLE IF NOT EXISTS "3d_birth_date" (
    id         BIGSERIAL PRIMARY KEY,
    root_id    BIGINT NOT NULL REFERENCES "3a_customer_root_record"(id) ON DELETE CASCADE,
    birth_date DATE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(root_id)
);
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
CREATE TABLE IF NOT EXISTS "3f_landline_phone" (
    id           BIGSERIAL PRIMARY KEY,
    root_id      BIGINT NOT NULL REFERENCES "3a_customer_root_record"(id) ON DELETE CASCADE,
    phone_number TEXT NOT NULL,
    label        TEXT,
    is_primary   BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(root_id, phone_number)
);
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
CREATE INDEX IF NOT EXISTS idx_endereco_root ON "3i_endereco_br"(root_id);
CREATE INDEX IF NOT EXISTS idx_endereco_cep  ON "3i_endereco_br"(cep) WHERE cep IS NOT NULL;
CREATE TABLE IF NOT EXISTS "3j_veiculos_br" (
    id                  BIGSERIAL PRIMARY KEY,
    root_id             BIGINT NOT NULL REFERENCES "3a_customer_root_record"(id) ON DELETE CASCADE,
    placa               TEXT NOT NULL,              -- Ex: "ABC1D23" (Mercosul) ou "ABC-1234" (antiga)
    renavam             TEXT,                       -- Código RENAVAM (11 dígitos)
    chassi              TEXT,                       -- Número do chassi/VIN
    tipo_veiculo        TEXT NOT NULL DEFAULT 'carro' CHECK (tipo_veiculo IN (
                            'moto', 'carro', 'camionete', 'suv', 'van',
                            'caminhao', 'onibus', 'triciclo', 'quadriciclo', 'outro'
                        )),
    marca               TEXT,                       -- Ex: "Volkswagen", "Honda"
    modelo              TEXT NOT NULL,              -- Ex: "Gol", "Civic", "CG 160"
    versao              TEXT,                       -- Ex: "1.0 Turbo TSI", "EX-L"
    ano_fabricacao      INTEGER CHECK (ano_fabricacao >= 1900 AND ano_fabricacao <= 2100),
    ano_modelo          INTEGER CHECK (ano_modelo >= 1900 AND ano_modelo <= 2100),
    cor                 TEXT,                       -- Ex: "Prata", "Preto", "Branco"
    combustivel         TEXT CHECK (combustivel IN (
                            'gasolina', 'etanol', 'flex', 'diesel', 'gnv', 'eletrico', 'hibrido'
                        )),
    quilometragem       INTEGER CHECK (quilometragem >= 0),  -- KM atual (útil para oficinas)
    apelido             TEXT,                       -- Nome carinhoso: "Carro da esposa", "Moto do trabalho"
    observacoes         TEXT,                       -- Notas livres
    url_foto_entrada    TEXT,                       -- Link para foto de entrada
    urls_adicionais     JSONB DEFAULT '[]'::jsonb,  -- Array de URLs extras [{"url": "...", "descricao": "..."}]
    is_principal        BOOLEAN NOT NULL DEFAULT FALSE,  -- Veículo principal do cliente
    is_ativo            BOOLEAN NOT NULL DEFAULT TRUE,   -- Se ainda é do cliente
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(root_id, placa)  -- Um cliente não pode ter a mesma placa duas vezes
);
CREATE INDEX IF NOT EXISTS idx_veiculos_root_id ON "3j_veiculos_br"(root_id);
CREATE INDEX IF NOT EXISTS idx_veiculos_placa   ON "3j_veiculos_br"(placa);
CREATE INDEX IF NOT EXISTS idx_veiculos_tipo    ON "3j_veiculos_br"(tipo_veiculo);
CREATE INDEX IF NOT EXISTS idx_veiculos_modelo  ON "3j_veiculos_br"(modelo);
CREATE TABLE IF NOT EXISTS "3k_social_media" (
    id                  BIGSERIAL PRIMARY KEY,
    root_id             BIGINT NOT NULL REFERENCES "3a_customer_root_record"(id) ON DELETE CASCADE,
    social_network      TEXT NOT NULL CHECK (social_network IN (
                            'instagram', 'facebook', 'tiktok', 'twitter_x', 'linkedin',
                            'youtube', 'pinterest', 'snapchat', 'telegram', 'whatsapp_business',
                            'threads', 'bluesky', 'discord', 'twitch', 'spotify',
                            'github', 'behance', 'dribbble', 'medium', 'other'
                        )),
    icon_url            TEXT,                       -- URL customizada para ícone (opcional, sistema pode ter padrão)
    profile_url         TEXT NOT NULL,              -- Link completo para o perfil (ex: "https://instagram.com/usuario")
    username            TEXT,                       -- Nome de usuário na rede (ex: "@usuario" ou "usuario")
    display_name        TEXT,                       -- Nome que aparece no perfil (pode ser diferente do username)
    followers           INTEGER CHECK (followers >= 0),  -- Número de seguidores (se público)
    platform_verified   BOOLEAN DEFAULT FALSE,           -- Se tem selo de verificação da plataforma (✓)
    reliability         TEXT NOT NULL DEFAULT 'unverified' CHECK (reliability IN (
                            'unverified',          -- ⚪ Não verificado - pode estar incorreto
                            'auto_discovered',     -- 🔍 Encontrado por busca automática - precisa confirmação
                            'customer_informed',   -- 💬 Cliente informou mas não confirmou
                            'team_verified',       -- 👁️ Equipe verificou manualmente
                            'customer_confirmed'   -- ✅ Cliente confirmou que é dele
                        )),
    reliability_note    TEXT,                       -- Ex: "Perfil abandonado desde 2020", "Cliente confirmou via chat"
    is_primary          BOOLEAN NOT NULL DEFAULT FALSE,  -- Rede social principal/preferida do cliente
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,   -- Se o perfil ainda está ativo
    verified_at         TIMESTAMPTZ,                -- Data da última verificação
    verified_by         TEXT,                       -- Quem verificou (usuário ou sistema)
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(root_id, social_network, username)  -- Um cliente não pode ter duplicata de rede+username
);
CREATE INDEX IF NOT EXISTS idx_social_media_root_id     ON "3k_social_media"(root_id);
CREATE INDEX IF NOT EXISTS idx_social_media_network     ON "3k_social_media"(social_network);
CREATE INDEX IF NOT EXISTS idx_social_media_username    ON "3k_social_media"(username) WHERE username IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_social_media_reliability ON "3k_social_media"(reliability);
CREATE INDEX IF NOT EXISTS idx_social_media_primary     ON "3k_social_media"(root_id) WHERE is_primary = TRUE;
CREATE TABLE IF NOT EXISTS "4a_customer_service_history" (
    id BIGSERIAL PRIMARY KEY,
    service_id TEXT,
    inbox_id UUID  NOT NULL REFERENCES "0a_inbox_whatsapp"(inbox_id) ON DELETE CASCADE,
    root_id BIGINT NOT NULL REFERENCES "3a_customer_root_record"(id) ON DELETE CASCADE,
    scheduled_by_wallet_id  UUID REFERENCES "1a_whatsapp_user_contact"(wallet_id) ON DELETE SET NULL,
    service_datetime_start  TIMESTAMPTZ NOT NULL,
    service_datetime_end    TIMESTAMPTZ NOT NULL,
    service_status          TEXT DEFAULT 'Scheduled' CHECK (service_status  IN ('Scheduled', 'Confirmed', 'Completed', 'Cancelled', 'Rescheduled', 'No_Show')),
    service_type            TEXT,
    is_online               BOOLEAN NOT NULL DEFAULT FALSE,
    calendar_name           TEXT,  -- nome do calendário (geralmente o nome do profissinal, exemplo: "Dra Alessandra Ribeiro")
    location_event          TEXT,  -- local onde o serviço será prestado (online, endereço da clinica ou endereço do cliente quando for a domicilio)
    value_cents         INTEGER CHECK (value_cents >= 0),
    payment_method      TEXT,
    requires_invoice    BOOLEAN NOT NULL DEFAULT FALSE,
    invoice_status      TEXT DEFAULT 'Nao_Necessario' CHECK (invoice_status IN ('Nao_Necessario', 'Pendente', 'Emitida', 'Enviada_Cliente', 'Falha')),
    notes               TEXT,
    follow_up_date      TIMESTAMPTZ,
    attachments         JSONB,
    scheduled_at        TIMESTAMPTZ,  -- Quando recebeu status 'Scheduled'
    confirmed_at        TIMESTAMPTZ,  -- Quando recebeu status 'Confirmed'
    completed_at        TIMESTAMPTZ,  -- Quando recebeu status 'Completed'
    cancelled_at        TIMESTAMPTZ,  -- Quando recebeu status 'Cancelled'
    rescheduled_at      TIMESTAMPTZ,  -- Quando recebeu status 'Rescheduled'
    no_show_at          TIMESTAMPTZ,  -- Quando recebeu status 'No_Show'
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_appointment_scheduled_at   ON "4a_customer_service_history"(scheduled_at)   WHERE scheduled_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_appointment_confirmed_at   ON "4a_customer_service_history"(confirmed_at)   WHERE confirmed_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_appointment_cancelled_at   ON "4a_customer_service_history"(cancelled_at)   WHERE cancelled_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_appointment_completed_at   ON "4a_customer_service_history"(completed_at)   WHERE completed_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_appointment_rescheduled_at ON "4a_customer_service_history"(rescheduled_at) WHERE rescheduled_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_appointment_no_show_at     ON "4a_customer_service_history"(no_show_at)     WHERE no_show_at IS NOT NULL;
CREATE OR REPLACE FUNCTION func_upsert_contact_from_webhook(
  p_inbox_id             UUID,
  p_owner_wallet_id      UUID,
  p_client_name          TEXT DEFAULT NULL,
  p_inbox_name           TEXT DEFAULT NULL,
  p_avatar_inbox_url     TEXT DEFAULT NULL,
  p_login_identity       TEXT DEFAULT NULL,
  p_status_workflow      workflow_status DEFAULT '🟢',
  p_avatar_agent_url     TEXT DEFAULT NULL,
  p_name_agent           TEXT DEFAULT NULL,
  p_bio_agent            TEXT DEFAULT NULL,
  p_monthly_limit        BIGINT DEFAULT 0,
  p_credits_used         BIGINT DEFAULT 0,
  p_remaining_credits    BIGINT DEFAULT 0,
  p_wallet_id            UUID DEFAULT NULL,
  p_status_contact       workflow_status DEFAULT '🟢',
  p_status_agent         workflow_status DEFAULT '🟢',
  p_push_name            TEXT DEFAULT NULL,
  p_latest_avatar_url    TEXT DEFAULT NULL,
  p_phone_number         TEXT DEFAULT NULL,
  p_country_flag_emoji   TEXT DEFAULT NULL,
  p_country_code         VARCHAR DEFAULT NULL,
  p_area_code            VARCHAR DEFAULT NULL,
  p_contact_message_count BIGINT DEFAULT 0,
  p_ai_engagement        BIGINT DEFAULT 0,
  p_human_engagement     BIGINT DEFAULT 0,
  p_engagement_score     FLOAT DEFAULT 0.0,
  p_last_interaction_at  TIMESTAMPTZ DEFAULT NULL,
  p_source_device        TEXT DEFAULT NULL,
  p_energy_daily_credit  BIGINT DEFAULT 0,
  p_energy_current_balance BIGINT DEFAULT 0,
  p_tags                 JSONB DEFAULT '[]'::jsonb,
  p_condensed_memory     JSONB DEFAULT '[]'::jsonb
)
RETURNS void AS $function_body$
DECLARE
  v_is_new_contact BOOLEAN;
BEGIN
  IF p_inbox_id IS NULL OR p_owner_wallet_id IS NULL OR p_wallet_id IS NULL THEN
    RAISE EXCEPTION 'Parâmetros obrigatórios faltando: inbox_id, owner_wallet_id, wallet_id';
  END IF;
  INSERT INTO "0a_inbox_whatsapp" (
    inbox_id, owner_wallet_id, client_name, inbox_name, avatar_inbox_url,
    login_identity, status_workflow, avatar_agent_url, name_agent, bio_agent,
    monthly_limit, credits_used, remaining_credits, updated_at
  )
  VALUES (
    p_inbox_id, p_owner_wallet_id, p_client_name, p_inbox_name, p_avatar_inbox_url,
    p_login_identity, p_status_workflow, p_avatar_agent_url, p_name_agent, p_bio_agent,
    p_monthly_limit, p_credits_used, p_remaining_credits, NOW()
  )
  ON CONFLICT (inbox_id) DO UPDATE SET
    client_name = COALESCE(EXCLUDED.client_name, "0a_inbox_whatsapp".client_name),
    inbox_name = COALESCE(EXCLUDED.inbox_name, "0a_inbox_whatsapp".inbox_name),
    avatar_inbox_url = COALESCE(EXCLUDED.avatar_inbox_url, "0a_inbox_whatsapp".avatar_inbox_url),
    login_identity = COALESCE(EXCLUDED.login_identity, "0a_inbox_whatsapp".login_identity),
    status_workflow = COALESCE(EXCLUDED.status_workflow, "0a_inbox_whatsapp".status_workflow),
    avatar_agent_url = COALESCE(EXCLUDED.avatar_agent_url, "0a_inbox_whatsapp".avatar_agent_url),
    name_agent = COALESCE(EXCLUDED.name_agent, "0a_inbox_whatsapp".name_agent),
    bio_agent = COALESCE(EXCLUDED.bio_agent, "0a_inbox_whatsapp".bio_agent),
    monthly_limit = COALESCE(EXCLUDED.monthly_limit, "0a_inbox_whatsapp".monthly_limit),
    credits_used = COALESCE(EXCLUDED.credits_used, "0a_inbox_whatsapp".credits_used),
    remaining_credits = COALESCE(EXCLUDED.remaining_credits, "0a_inbox_whatsapp".remaining_credits),
    updated_at = NOW();
  SELECT NOT EXISTS(
    SELECT 1 FROM "1a_whatsapp_user_contact" WHERE wallet_id = p_wallet_id
  ) INTO v_is_new_contact;
  INSERT INTO "1a_whatsapp_user_contact" (
    wallet_id, inbox_id, status_contact, status_agent, push_name, latest_avatar_url,
    phone_number, country_flag_emoji, country_code, area_code, contact_message_count,
    ai_engagement, human_engagement, engagement_score, last_interaction_at,
    source_device, energy_daily_credit, energy_current_balance, tags, condensed_memory, updated_at
  )
  VALUES (
    p_wallet_id, p_inbox_id, p_status_contact, p_status_agent, p_push_name, p_latest_avatar_url,
    p_phone_number, p_country_flag_emoji, p_country_code, p_area_code, p_contact_message_count,
    p_ai_engagement, p_human_engagement, p_engagement_score, p_last_interaction_at,
    p_source_device, p_energy_daily_credit, p_energy_current_balance, p_tags, p_condensed_memory, NOW()
  )
  ON CONFLICT (wallet_id) DO UPDATE SET
    status_contact = COALESCE(EXCLUDED.status_contact, "1a_whatsapp_user_contact".status_contact),
    status_agent = COALESCE(EXCLUDED.status_agent, "1a_whatsapp_user_contact".status_agent),
    push_name = COALESCE(EXCLUDED.push_name, "1a_whatsapp_user_contact".push_name),
    latest_avatar_url = COALESCE(EXCLUDED.latest_avatar_url, "1a_whatsapp_user_contact".latest_avatar_url),
    phone_number = COALESCE(EXCLUDED.phone_number, "1a_whatsapp_user_contact".phone_number),
    country_flag_emoji = COALESCE(EXCLUDED.country_flag_emoji, "1a_whatsapp_user_contact".country_flag_emoji),
    country_code = COALESCE(EXCLUDED.country_code, "1a_whatsapp_user_contact".country_code),
    area_code = COALESCE(EXCLUDED.area_code, "1a_whatsapp_user_contact".area_code),
    contact_message_count = COALESCE(EXCLUDED.contact_message_count, "1a_whatsapp_user_contact".contact_message_count),
    ai_engagement = COALESCE(EXCLUDED.ai_engagement, "1a_whatsapp_user_contact".ai_engagement),
    human_engagement = COALESCE(EXCLUDED.human_engagement, "1a_whatsapp_user_contact".human_engagement),
    engagement_score = COALESCE(EXCLUDED.engagement_score, "1a_whatsapp_user_contact".engagement_score),
    last_interaction_at = COALESCE(EXCLUDED.last_interaction_at, "1a_whatsapp_user_contact".last_interaction_at),
    source_device = COALESCE(EXCLUDED.source_device, "1a_whatsapp_user_contact".source_device),
    energy_daily_credit = COALESCE(EXCLUDED.energy_daily_credit, "1a_whatsapp_user_contact".energy_daily_credit),
    energy_current_balance = COALESCE(EXCLUDED.energy_current_balance, "1a_whatsapp_user_contact".energy_current_balance),
    tags = COALESCE(EXCLUDED.tags, "1a_whatsapp_user_contact".tags),
    condensed_memory = COALESCE(EXCLUDED.condensed_memory, "1a_whatsapp_user_contact".condensed_memory),
    updated_at = NOW();
  IF v_is_new_contact THEN
    UPDATE "0b_inbox_counters"
    SET contact_count = contact_count + 1
    WHERE inbox_id = p_inbox_id;
    IF NOT FOUND THEN
      INSERT INTO "0b_inbox_counters" (inbox_id, contact_count, form_count, scheduling_count)
      VALUES (p_inbox_id, 1, 0, 0)
      ON CONFLICT (inbox_id) DO UPDATE
      SET contact_count = "0b_inbox_counters".contact_count + 1;
    END IF;
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Erro na função func_upsert_contact_from_webhook: % - %', SQLERRM, SQLSTATE;
END;
$function_body$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION func_sync_owner_to_cell_sheet()
RETURNS TRIGGER AS $function_body$
DECLARE
    v_wallet_id UUID;
BEGIN
    SELECT wallet_id INTO v_wallet_id
    FROM "1a_whatsapp_user_contact"
    WHERE phone_number = NEW.whatsapp_owner
      AND inbox_id = NEW.inbox_id
    LIMIT 1;
    IF v_wallet_id IS NULL THEN
        RETURN NEW;
    END IF;
    INSERT INTO "3b_cell_phone_linked_service_sheet" (
        root_id,
        wallet_id,
        cell_phone,
        is_primary,
        is_whatsapp,
        verified
    )
    VALUES (
        NEW.id,
        v_wallet_id,
        NEW.whatsapp_owner,
        TRUE,
        TRUE,
        TRUE
    )
    ON CONFLICT (root_id, wallet_id) DO UPDATE SET
        cell_phone = EXCLUDED.cell_phone,
        is_primary = EXCLUDED.is_primary,
        is_whatsapp = EXCLUDED.is_whatsapp,
        verified = EXCLUDED.verified,
        updated_at = NOW();
    RETURN NEW;
END;
$function_body$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION func_generate_friendly_client_id()
RETURNS TRIGGER AS $function_body$
DECLARE
    new_count INT;
BEGIN
    UPDATE "0b_inbox_counters"
    SET client_count = client_count + 1
    WHERE inbox_id = NEW.inbox_id
    RETURNING client_count INTO new_count;
    IF NOT FOUND THEN
        new_count := 1;
        INSERT INTO "0b_inbox_counters" (inbox_id, client_count, atendimento_count)
        VALUES (NEW.inbox_id, new_count, 0)
        ON CONFLICT (inbox_id) DO NOTHING;
    END IF;
    NEW.client_id := 'CT' || new_count::text;
    RETURN NEW;
END;
$function_body$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION func_generate_friendly_service_id()
RETURNS TRIGGER AS $function_body$
DECLARE
    new_count INT;
BEGIN
    UPDATE "0b_inbox_counters"
    SET atendimento_count = atendimento_count + 1
    WHERE inbox_id = NEW.inbox_id
    RETURNING atendimento_count INTO new_count;
    IF NOT FOUND THEN
        new_count := 1;
        INSERT INTO "0b_inbox_counters" (inbox_id, client_count, atendimento_count)
        VALUES (NEW.inbox_id, 0, new_count)
        ON CONFLICT (inbox_id) DO UPDATE 
        SET atendimento_count = new_count;
    END IF;
    NEW.service_id := 'AT' || new_count::text;
    RETURN NEW;
END;
$function_body$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION func_ensure_first_is_primary()
RETURNS TRIGGER AS $function_body$
DECLARE
    v_count INT;
BEGIN
    EXECUTE format('SELECT COUNT(*) FROM %I WHERE root_id = $1', TG_TABLE_NAME)
    INTO v_count
    USING NEW.root_id;
    IF v_count = 0 THEN
        NEW.is_primary := TRUE;
    END IF;
    RETURN NEW;
END;
$function_body$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION func_generate_ulid()
RETURNS TEXT AS $function_body$
DECLARE
    unix_time BIGINT;
    randomness TEXT := '';
    encoding TEXT := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    output TEXT := '';
    i INT;
    rand_byte INT;
BEGIN
    unix_time := (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT;
    FOR i IN REVERSE 9..0 LOOP
        output := output || SUBSTRING(encoding FROM ((unix_time >> (i * 5)) & 31) + 1 FOR 1);
    END LOOP;
    FOR i IN 1..16 LOOP
        rand_byte := FLOOR(RANDOM() * 32)::INT;
        randomness := randomness || SUBSTRING(encoding FROM rand_byte + 1 FOR 1);
    END LOOP;
    RETURN output || randomness;
END;
$function_body$ LANGUAGE plpgsql VOLATILE;
CREATE OR REPLACE FUNCTION func_auto_populate_message_fields()
RETURNS TRIGGER AS $function_body$
BEGIN
    IF (NEW.source_message_id IS NULL OR NEW.source_message_id = '') AND
       NEW.sender_type IN ('ai_agent', 'human_agent', 'system') THEN
        NEW.source_message_id := func_generate_ulid();
    END IF;
    IF NEW.message_content IS NOT NULL AND NEW.message_content <> '' THEN
        NEW.message_content_tsv := to_tsvector('portuguese', NEW.message_content);
    END IF;
    RETURN NEW;
END;
$function_body$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $function_body$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$function_body$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION func_upsert_contact_from_webhook(
  p_inbox_id             UUID,
  p_owner_wallet_id      UUID,
  p_client_name          TEXT DEFAULT NULL,
  p_inbox_name           TEXT DEFAULT NULL,
  p_avatar_inbox_url     TEXT DEFAULT NULL,
  p_login_identity       TEXT DEFAULT NULL,
  p_status_workflow      workflow_status DEFAULT '🟢',
  p_avatar_agent_url     TEXT DEFAULT NULL,
  p_name_agent           TEXT DEFAULT NULL,
  p_bio_agent            TEXT DEFAULT NULL,
  p_monthly_limit        BIGINT DEFAULT 0,
  p_credits_used         BIGINT DEFAULT 0,
  p_remaining_credits    BIGINT DEFAULT 0,
  p_wallet_id            UUID DEFAULT NULL,
  p_status_contact       workflow_status DEFAULT '🟢',
  p_status_agent         workflow_status DEFAULT '🟢',
  p_push_name            TEXT DEFAULT NULL,
  p_latest_avatar_url    TEXT DEFAULT NULL,
  p_phone_number         TEXT DEFAULT NULL,
  p_country_flag_emoji   TEXT DEFAULT NULL,
  p_country_code         VARCHAR DEFAULT NULL,
  p_area_code            VARCHAR DEFAULT NULL,
  p_contact_message_count BIGINT DEFAULT 0,
  p_ai_engagement        BIGINT DEFAULT 0,
  p_human_engagement     BIGINT DEFAULT 0,
  p_engagement_score     FLOAT DEFAULT 0.0,
  p_last_interaction_at  TIMESTAMPTZ DEFAULT NULL,
  p_source_device        TEXT DEFAULT NULL,
  p_energy_daily_credit  BIGINT DEFAULT 0,
  p_energy_current_balance BIGINT DEFAULT 0,
  p_tags                 JSONB DEFAULT '[]'::jsonb,
  p_condensed_memory     JSONB DEFAULT '[]'::jsonb
)
RETURNS void AS $function_body$
DECLARE
  v_is_new_contact BOOLEAN;
BEGIN
  IF p_inbox_id IS NULL OR p_owner_wallet_id IS NULL OR p_wallet_id IS NULL THEN
    RAISE EXCEPTION 'Parâmetros obrigatórios faltando: inbox_id, owner_wallet_id, wallet_id';
  END IF;
  INSERT INTO "0a_inbox_whatsapp" (
    inbox_id, owner_wallet_id, client_name, inbox_name, avatar_inbox_url,
    login_identity, status_workflow, avatar_agent_url, name_agent, bio_agent,
    monthly_limit, credits_used, remaining_credits, updated_at
  )
  VALUES (
    p_inbox_id, p_owner_wallet_id, p_client_name, p_inbox_name, p_avatar_inbox_url,
    p_login_identity, p_status_workflow, p_avatar_agent_url, p_name_agent, p_bio_agent,
    p_monthly_limit, p_credits_used, p_remaining_credits, NOW()
  )
  ON CONFLICT (inbox_id) DO UPDATE SET
    client_name = COALESCE(EXCLUDED.client_name, "0a_inbox_whatsapp".client_name),
    inbox_name = COALESCE(EXCLUDED.inbox_name, "0a_inbox_whatsapp".inbox_name),
    avatar_inbox_url = COALESCE(EXCLUDED.avatar_inbox_url, "0a_inbox_whatsapp".avatar_inbox_url),
    login_identity = COALESCE(EXCLUDED.login_identity, "0a_inbox_whatsapp".login_identity),
    status_workflow = COALESCE(EXCLUDED.status_workflow, "0a_inbox_whatsapp".status_workflow),
    avatar_agent_url = COALESCE(EXCLUDED.avatar_agent_url, "0a_inbox_whatsapp".avatar_agent_url),
    name_agent = COALESCE(EXCLUDED.name_agent, "0a_inbox_whatsapp".name_agent),
    bio_agent = COALESCE(EXCLUDED.bio_agent, "0a_inbox_whatsapp".bio_agent),
    monthly_limit = COALESCE(EXCLUDED.monthly_limit, "0a_inbox_whatsapp".monthly_limit),
    credits_used = COALESCE(EXCLUDED.credits_used, "0a_inbox_whatsapp".credits_used),
    remaining_credits = COALESCE(EXCLUDED.remaining_credits, "0a_inbox_whatsapp".remaining_credits),
    updated_at = NOW();
  SELECT NOT EXISTS(
    SELECT 1 FROM "1a_whatsapp_user_contact" WHERE wallet_id = p_wallet_id
  ) INTO v_is_new_contact;
  INSERT INTO "1a_whatsapp_user_contact" (
    wallet_id, inbox_id, status_contact, status_agent, push_name, latest_avatar_url,
    phone_number, country_flag_emoji, country_code, area_code, contact_message_count,
    ai_engagement, human_engagement, engagement_score, last_interaction_at,
    source_device, energy_daily_credit, energy_current_balance, tags, condensed_memory, updated_at
  )
  VALUES (
    p_wallet_id, p_inbox_id, p_status_contact, p_status_agent, p_push_name, p_latest_avatar_url,
    p_phone_number, p_country_flag_emoji, p_country_code, p_area_code, p_contact_message_count,
    p_ai_engagement, p_human_engagement, p_engagement_score, p_last_interaction_at,
    p_source_device, p_energy_daily_credit, p_energy_current_balance, p_tags, p_condensed_memory, NOW()
  )
  ON CONFLICT (wallet_id) DO UPDATE SET
    status_contact = COALESCE(EXCLUDED.status_contact, "1a_whatsapp_user_contact".status_contact),
    status_agent = COALESCE(EXCLUDED.status_agent, "1a_whatsapp_user_contact".status_agent),
    push_name = COALESCE(EXCLUDED.push_name, "1a_whatsapp_user_contact".push_name),
    latest_avatar_url = COALESCE(EXCLUDED.latest_avatar_url, "1a_whatsapp_user_contact".latest_avatar_url),
    phone_number = COALESCE(EXCLUDED.phone_number, "1a_whatsapp_user_contact".phone_number),
    country_flag_emoji = COALESCE(EXCLUDED.country_flag_emoji, "1a_whatsapp_user_contact".country_flag_emoji),
    country_code = COALESCE(EXCLUDED.country_code, "1a_whatsapp_user_contact".country_code),
    area_code = COALESCE(EXCLUDED.area_code, "1a_whatsapp_user_contact".area_code),
    contact_message_count = COALESCE(EXCLUDED.contact_message_count, "1a_whatsapp_user_contact".contact_message_count),
    ai_engagement = COALESCE(EXCLUDED.ai_engagement, "1a_whatsapp_user_contact".ai_engagement),
    human_engagement = COALESCE(EXCLUDED.human_engagement, "1a_whatsapp_user_contact".human_engagement),
    engagement_score = COALESCE(EXCLUDED.engagement_score, "1a_whatsapp_user_contact".engagement_score),
    last_interaction_at = COALESCE(EXCLUDED.last_interaction_at, "1a_whatsapp_user_contact".last_interaction_at),
    source_device = COALESCE(EXCLUDED.source_device, "1a_whatsapp_user_contact".source_device),
    energy_daily_credit = COALESCE(EXCLUDED.energy_daily_credit, "1a_whatsapp_user_contact".energy_daily_credit),
    energy_current_balance = COALESCE(EXCLUDED.energy_current_balance, "1a_whatsapp_user_contact".energy_current_balance),
    tags = COALESCE(EXCLUDED.tags, "1a_whatsapp_user_contact".tags),
    condensed_memory = COALESCE(EXCLUDED.condensed_memory, "1a_whatsapp_user_contact".condensed_memory),
    updated_at = NOW();
  IF v_is_new_contact THEN
    UPDATE "0b_inbox_counters"
    SET contact_count = contact_count + 1
    WHERE inbox_id = p_inbox_id;
    IF NOT FOUND THEN
      INSERT INTO "0b_inbox_counters" (inbox_id, contact_count, form_count, scheduling_count)
      VALUES (p_inbox_id, 1, 0, 0)
      ON CONFLICT (inbox_id) DO UPDATE
      SET contact_count = "0b_inbox_counters".contact_count + 1;
    END IF;
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Erro na função func_upsert_contact_from_webhook: % - %', SQLERRM, SQLSTATE;
END;
$function_body$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION func_sync_owner_to_cell_sheet()
RETURNS TRIGGER AS $function_body$
DECLARE
    v_wallet_id UUID;
BEGIN
    SELECT wallet_id INTO v_wallet_id
    FROM "1a_whatsapp_user_contact"
    WHERE phone_number = NEW.whatsapp_owner
      AND inbox_id = NEW.inbox_id
    LIMIT 1;
    IF v_wallet_id IS NULL THEN
        RETURN NEW;
    END IF;
    INSERT INTO "3b_cell_phone_linked_service_sheet" (
        root_id,
        wallet_id,
        cell_phone,
        is_primary,
        is_whatsapp,
        verified
    )
    VALUES (
        NEW.id,
        v_wallet_id,
        NEW.whatsapp_owner,
        TRUE,
        TRUE,
        TRUE
    )
    ON CONFLICT (root_id, wallet_id) DO UPDATE SET
        cell_phone = EXCLUDED.cell_phone,
        is_primary = EXCLUDED.is_primary,
        is_whatsapp = EXCLUDED.is_whatsapp,
        verified = EXCLUDED.verified,
        updated_at = NOW();
    RETURN NEW;
END;
$function_body$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION func_generate_friendly_client_id()
RETURNS TRIGGER AS $function_body$
DECLARE
    new_count INT;
BEGIN
    UPDATE "0b_inbox_counters"
    SET client_count = client_count + 1
    WHERE inbox_id = NEW.inbox_id
    RETURNING client_count INTO new_count;
    IF NOT FOUND THEN
        new_count := 1;
        INSERT INTO "0b_inbox_counters" (inbox_id, client_count, atendimento_count)
        VALUES (NEW.inbox_id, new_count, 0)
        ON CONFLICT (inbox_id) DO NOTHING;
    END IF;
    NEW.client_id := 'CT' || new_count::text;
    RETURN NEW;
END;
$function_body$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION func_generate_friendly_service_id()
RETURNS TRIGGER AS $function_body$
DECLARE
    new_count INT;
BEGIN
    UPDATE "0b_inbox_counters"
    SET atendimento_count = atendimento_count + 1
    WHERE inbox_id = NEW.inbox_id
    RETURNING atendimento_count INTO new_count;
    IF NOT FOUND THEN
        new_count := 1;
        INSERT INTO "0b_inbox_counters" (inbox_id, client_count, atendimento_count)
        VALUES (NEW.inbox_id, 0, new_count)
        ON CONFLICT (inbox_id) DO UPDATE 
        SET atendimento_count = new_count;
    END IF;
    NEW.service_id := 'AT' || new_count::text;
    RETURN NEW;
END;
$function_body$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION func_ensure_first_is_primary()
RETURNS TRIGGER AS $function_body$
DECLARE
    v_count INT;
BEGIN
    EXECUTE format('SELECT COUNT(*) FROM %I WHERE root_id = $1', TG_TABLE_NAME)
    INTO v_count
    USING NEW.root_id;
    IF v_count = 0 THEN
        NEW.is_primary := TRUE;
    END IF;
    RETURN NEW;
END;
$function_body$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION func_generate_ulid()
RETURNS TEXT AS $function_body$
DECLARE
    unix_time BIGINT;
    randomness TEXT := '';
    encoding TEXT := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    output TEXT := '';
    i INT;
    rand_byte INT;
BEGIN
    unix_time := (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT;
    FOR i IN REVERSE 9..0 LOOP
        output := output || SUBSTRING(encoding FROM ((unix_time >> (i * 5)) & 31) + 1 FOR 1);
    END LOOP;
    FOR i IN 1..16 LOOP
        rand_byte := FLOOR(RANDOM() * 32)::INT;
        randomness := randomness || SUBSTRING(encoding FROM rand_byte + 1 FOR 1);
    END LOOP;
    RETURN output || randomness;
END;
$function_body$ LANGUAGE plpgsql VOLATILE;
CREATE OR REPLACE FUNCTION func_auto_populate_message_fields()
RETURNS TRIGGER AS $function_body$
BEGIN
    IF (NEW.source_message_id IS NULL OR NEW.source_message_id = '') AND
       NEW.sender_type IN ('ai_agent', 'human_agent', 'system') THEN
        NEW.source_message_id := func_generate_ulid();
    END IF;
    IF NEW.message_content IS NOT NULL AND NEW.message_content <> '' THEN
        NEW.message_content_tsv := to_tsvector('portuguese', NEW.message_content);
    END IF;
    RETURN NEW;
END;
$function_body$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $function_body$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$function_body$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION func_check_complete_form(p_root_id BIGINT)
RETURNS BOOLEAN AS $function_body$
DECLARE
    v_inbox_id UUID;
    v_required_config JSONB;
    v_field_name TEXT;
    v_is_required BOOLEAN;
    v_field_value TEXT;
    v_exists BOOLEAN;
BEGIN
    SELECT
        r.inbox_id,
        i.required_data_form
    INTO
        v_inbox_id,
        v_required_config
    FROM "3a_customer_root_record" r
    JOIN "0a_inbox_whatsapp" i ON i.inbox_id = r.inbox_id
    WHERE r.id = p_root_id;
    IF v_inbox_id IS NULL THEN
        RETURN FALSE;
    END IF;
    IF v_required_config IS NULL OR v_required_config = '{}'::jsonb THEN
        RETURN TRUE;
    END IF;
    FOR v_field_name, v_is_required IN
        SELECT
            key,
            (value->>'required')::boolean
        FROM jsonb_each(v_required_config)
    LOOP
        IF v_is_required THEN
            CASE v_field_name
                WHEN 'treatment_name' THEN
                    SELECT treatment_name INTO v_field_value
                    FROM "3a_customer_root_record"
                    WHERE id = p_root_id;
                    IF v_field_value IS NULL OR v_field_value = '' THEN
                        RETURN FALSE;
                    END IF;
                WHEN 'legal_name_complete' THEN
                    SELECT legal_name_complete INTO v_field_value
                    FROM "3a_customer_root_record"
                    WHERE id = p_root_id;
                    IF v_field_value IS NULL OR v_field_value = '' THEN
                        RETURN FALSE;
                    END IF;
                WHEN 'whatsapp_owner' THEN
                    SELECT whatsapp_owner INTO v_field_value
                    FROM "3a_customer_root_record"
                    WHERE id = p_root_id;
                    IF v_field_value IS NULL OR v_field_value = '' THEN
                        RETURN FALSE;
                    END IF;
                WHEN 'cell_phone' THEN
                    SELECT EXISTS(
                        SELECT 1 FROM "3b_cell_phone_linked_service_sheet"
                        WHERE root_id = p_root_id
                        AND cell_phone IS NOT NULL
                        AND cell_phone <> ''
                    ) INTO v_exists;
                    IF NOT v_exists THEN
                        RETURN FALSE;
                    END IF;
                WHEN 'gender' THEN
                    SELECT EXISTS(
                        SELECT 1 FROM "3c_gender"
                        WHERE root_id = p_root_id
                        AND gender IS NOT NULL
                    ) INTO v_exists;
                    IF NOT v_exists THEN
                        RETURN FALSE;
                    END IF;
                WHEN 'birth_date' THEN
                    SELECT EXISTS(
                        SELECT 1 FROM "3d_birth_date"
                        WHERE root_id = p_root_id
                        AND birth_date IS NOT NULL
                    ) INTO v_exists;
                    IF NOT v_exists THEN
                        RETURN FALSE;
                    END IF;
                WHEN 'email' THEN
                    SELECT EXISTS(
                        SELECT 1 FROM "3e_email"
                        WHERE root_id = p_root_id
                        AND email IS NOT NULL
                        AND email <> ''
                    ) INTO v_exists;
                    IF NOT v_exists THEN
                        RETURN FALSE;
                    END IF;
                WHEN 'landline_phone' THEN
                    SELECT EXISTS(
                        SELECT 1 FROM "3f_landline_phone"
                        WHERE root_id = p_root_id
                        AND phone_number IS NOT NULL
                        AND phone_number <> ''
                    ) INTO v_exists;
                    IF NOT v_exists THEN
                        RETURN FALSE;
                    END IF;
                WHEN 'cpf' THEN
                    SELECT EXISTS(
                        SELECT 1 FROM "3g_cpf"
                        WHERE root_id = p_root_id
                        AND cpf IS NOT NULL
                        AND cpf <> ''
                    ) INTO v_exists;
                    IF NOT v_exists THEN
                        RETURN FALSE;
                    END IF;
                WHEN 'rg_numero' THEN
                    SELECT EXISTS(
                        SELECT 1 FROM "3h_rg"
                        WHERE root_id = p_root_id
                        AND rg_numero IS NOT NULL
                        AND rg_numero <> ''
                    ) INTO v_exists;
                    IF NOT v_exists THEN
                        RETURN FALSE;
                    END IF;
                WHEN 'endereco' THEN
                    SELECT EXISTS(
                        SELECT 1 FROM "3i_endereco_br"
                        WHERE root_id = p_root_id
                        AND logradouro IS NOT NULL
                        AND logradouro <> ''
                        AND cidade IS NOT NULL
                        AND cidade <> ''
                    ) INTO v_exists;
                    IF NOT v_exists THEN
                        RETURN FALSE;
                    END IF;
                ELSE
                    NULL;
            END CASE;
        END IF;
    END LOOP;
    RETURN TRUE;
EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING 'Erro em func_check_complete_form para root_id %: % - %',
                      p_root_id, SQLERRM, SQLSTATE;
        RETURN FALSE;
END;
$function_body$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION func_update_form_counter()
RETURNS TRIGGER AS $function_body$
DECLARE
    v_root_id BIGINT;
    v_inbox_id UUID;
    v_is_complete_now BOOLEAN;
    v_was_complete_before BOOLEAN;
BEGIN
    IF TG_TABLE_NAME = '3a_customer_root_record' THEN
        v_root_id := NEW.id;
    ELSE
        v_root_id := NEW.root_id;
    END IF;
    IF v_root_id IS NULL THEN
        RETURN NEW;
    END IF;
    SELECT inbox_id, is_form_complete
    INTO v_inbox_id, v_was_complete_before
    FROM "3a_customer_root_record"
    WHERE id = v_root_id;
    IF v_inbox_id IS NULL THEN
        RETURN NEW;
    END IF;
    v_is_complete_now := func_check_complete_form(v_root_id);
    IF v_is_complete_now AND NOT v_was_complete_before THEN
        UPDATE "3a_customer_root_record"
        SET is_form_complete = TRUE
        WHERE id = v_root_id;
        UPDATE "0b_inbox_counters"
        SET form_count = form_count + 1
        WHERE inbox_id = v_inbox_id;
        IF NOT FOUND THEN
            INSERT INTO "0b_inbox_counters" (inbox_id, contact_count, form_count, scheduling_count)
            VALUES (v_inbox_id, 0, 1, 0)
            ON CONFLICT (inbox_id) DO UPDATE
            SET form_count = "0b_inbox_counters".form_count + 1;
        END IF;
    ELSIF NOT v_is_complete_now AND v_was_complete_before THEN
        UPDATE "3a_customer_root_record"
        SET is_form_complete = FALSE
        WHERE id = v_root_id;
        UPDATE "0b_inbox_counters"
        SET form_count = GREATEST(form_count - 1, 0)
        WHERE inbox_id = v_inbox_id;
    END IF;
    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING 'Erro em func_update_form_counter para root_id %: % - %',
                      v_root_id, SQLERRM, SQLSTATE;
        RETURN NEW;
END;
$function_body$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION func_set_status_timestamp()
RETURNS TRIGGER AS $function_body$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        CASE NEW.service_status
            WHEN 'Scheduled' THEN
                NEW.scheduled_at := NOW();
            WHEN 'Confirmed' THEN
                NEW.confirmed_at := NOW();
            WHEN 'Completed' THEN
                NEW.completed_at := NOW();
            WHEN 'Cancelled' THEN
                NEW.cancelled_at := NOW();
            WHEN 'Rescheduled' THEN
                NEW.rescheduled_at := NOW();
            WHEN 'No_Show' THEN
                NEW.no_show_at := NOW();
        END CASE;
    ELSIF (TG_OP = 'UPDATE') THEN
        IF OLD.service_status IS DISTINCT FROM NEW.service_status THEN
            CASE NEW.service_status
                WHEN 'Scheduled' THEN
                    NEW.scheduled_at := NOW();
                WHEN 'Confirmed' THEN
                    NEW.confirmed_at := NOW();
                WHEN 'Completed' THEN
                    NEW.completed_at := NOW();
                WHEN 'Cancelled' THEN
                    NEW.cancelled_at := NOW();
                WHEN 'Rescheduled' THEN
                    NEW.rescheduled_at := NOW();
                WHEN 'No_Show' THEN
                    NEW.no_show_at := NOW();
            END CASE;
        END IF;
    END IF;
    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING 'Erro em func_set_status_timestamp para service_id %: % - %',
                      NEW.service_id, SQLERRM, SQLSTATE;
        RETURN NEW;
END;
$function_body$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION func_update_appointment_status_counter()
RETURNS TRIGGER AS $function_body$
DECLARE
    v_inbox_id UUID;
    v_old_status TEXT;
    v_new_status TEXT;
BEGIN
    v_inbox_id := NEW.inbox_id;
    v_new_status := NEW.service_status;
    IF (TG_OP = 'INSERT') THEN
        CASE v_new_status
            WHEN 'Scheduled' THEN
                UPDATE "0b_inbox_counters"
                SET scheduled_count = scheduled_count + 1
                WHERE inbox_id = v_inbox_id;
            WHEN 'Confirmed' THEN
                UPDATE "0b_inbox_counters"
                SET confirmed_count = confirmed_count + 1
                WHERE inbox_id = v_inbox_id;
            WHEN 'Completed' THEN
                UPDATE "0b_inbox_counters"
                SET completed_count = completed_count + 1
                WHERE inbox_id = v_inbox_id;
            WHEN 'Cancelled' THEN
                UPDATE "0b_inbox_counters"
                SET cancelled_count = cancelled_count + 1
                WHERE inbox_id = v_inbox_id;
            WHEN 'Rescheduled' THEN
                UPDATE "0b_inbox_counters"
                SET rescheduled_count = rescheduled_count + 1
                WHERE inbox_id = v_inbox_id;
            WHEN 'No_Show' THEN
                UPDATE "0b_inbox_counters"
                SET no_show_count = no_show_count + 1
                WHERE inbox_id = v_inbox_id;
        END CASE;
        IF NOT FOUND THEN
            INSERT INTO "0b_inbox_counters" (
                inbox_id,
                contact_count,
                form_count,
                scheduling_count,
                scheduled_count,
                confirmed_count,
                completed_count,
                cancelled_count,
                rescheduled_count,
                no_show_count
            )
            VALUES (
                v_inbox_id,
                0,
                0,
                0,
                CASE WHEN v_new_status = 'Scheduled' THEN 1 ELSE 0 END,
                CASE WHEN v_new_status = 'Confirmed' THEN 1 ELSE 0 END,
                CASE WHEN v_new_status = 'Completed' THEN 1 ELSE 0 END,
                CASE WHEN v_new_status = 'Cancelled' THEN 1 ELSE 0 END,
                CASE WHEN v_new_status = 'Rescheduled' THEN 1 ELSE 0 END,
                CASE WHEN v_new_status = 'No_Show' THEN 1 ELSE 0 END
            )
            ON CONFLICT (inbox_id) DO UPDATE SET
                scheduled_count = CASE WHEN v_new_status = 'Scheduled'
                    THEN "0b_inbox_counters".scheduled_count + 1
                    ELSE "0b_inbox_counters".scheduled_count END,
                confirmed_count = CASE WHEN v_new_status = 'Confirmed'
                    THEN "0b_inbox_counters".confirmed_count + 1
                    ELSE "0b_inbox_counters".confirmed_count END,
                completed_count = CASE WHEN v_new_status = 'Completed'
                    THEN "0b_inbox_counters".completed_count + 1
                    ELSE "0b_inbox_counters".completed_count END,
                cancelled_count = CASE WHEN v_new_status = 'Cancelled'
                    THEN "0b_inbox_counters".cancelled_count + 1
                    ELSE "0b_inbox_counters".cancelled_count END,
                rescheduled_count = CASE WHEN v_new_status = 'Rescheduled'
                    THEN "0b_inbox_counters".rescheduled_count + 1
                    ELSE "0b_inbox_counters".rescheduled_count END,
                no_show_count = CASE WHEN v_new_status = 'No_Show'
                    THEN "0b_inbox_counters".no_show_count + 1
                    ELSE "0b_inbox_counters".no_show_count END;
        END IF;
    ELSIF (TG_OP = 'UPDATE') THEN
        v_old_status := OLD.service_status;
        IF v_old_status IS DISTINCT FROM v_new_status THEN
            CASE v_old_status
                WHEN 'Scheduled' THEN
                    UPDATE "0b_inbox_counters"
                    SET scheduled_count = GREATEST(scheduled_count - 1, 0)
                    WHERE inbox_id = v_inbox_id;
                WHEN 'Confirmed' THEN
                    UPDATE "0b_inbox_counters"
                    SET confirmed_count = GREATEST(confirmed_count - 1, 0)
                    WHERE inbox_id = v_inbox_id;
                WHEN 'Completed' THEN
                    UPDATE "0b_inbox_counters"
                    SET completed_count = GREATEST(completed_count - 1, 0)
                    WHERE inbox_id = v_inbox_id;
                WHEN 'Cancelled' THEN
                    UPDATE "0b_inbox_counters"
                    SET cancelled_count = GREATEST(cancelled_count - 1, 0)
                    WHERE inbox_id = v_inbox_id;
                WHEN 'Rescheduled' THEN
                    UPDATE "0b_inbox_counters"
                    SET rescheduled_count = GREATEST(rescheduled_count - 1, 0)
                    WHERE inbox_id = v_inbox_id;
                WHEN 'No_Show' THEN
                    UPDATE "0b_inbox_counters"
                    SET no_show_count = GREATEST(no_show_count - 1, 0)
                    WHERE inbox_id = v_inbox_id;
            END CASE;
            CASE v_new_status
                WHEN 'Scheduled' THEN
                    UPDATE "0b_inbox_counters"
                    SET scheduled_count = scheduled_count + 1
                    WHERE inbox_id = v_inbox_id;
                WHEN 'Confirmed' THEN
                    UPDATE "0b_inbox_counters"
                    SET confirmed_count = confirmed_count + 1
                    WHERE inbox_id = v_inbox_id;
                WHEN 'Completed' THEN
                    UPDATE "0b_inbox_counters"
                    SET completed_count = completed_count + 1
                    WHERE inbox_id = v_inbox_id;
                WHEN 'Cancelled' THEN
                    UPDATE "0b_inbox_counters"
                    SET cancelled_count = cancelled_count + 1
                    WHERE inbox_id = v_inbox_id;
                WHEN 'Rescheduled' THEN
                    UPDATE "0b_inbox_counters"
                    SET rescheduled_count = rescheduled_count + 1
                    WHERE inbox_id = v_inbox_id;
                WHEN 'No_Show' THEN
                    UPDATE "0b_inbox_counters"
                    SET no_show_count = no_show_count + 1
                    WHERE inbox_id = v_inbox_id;
            END CASE;
        END IF;
    END IF;
    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING 'Erro em func_update_appointment_status_counter para inbox_id %: % - %',
                      v_inbox_id, SQLERRM, SQLSTATE;
        RETURN NEW;
END;
$function_body$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION get_billing_by_period(
    p_inbox_id UUID,
    p_start_date TIMESTAMPTZ,
    p_end_date TIMESTAMPTZ
)
RETURNS JSONB AS $function_body$
DECLARE
    v_total_cents BIGINT;
    v_completed_count INT;
    v_avg_ticket_cents BIGINT;
    v_result JSONB;
BEGIN
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
    IF v_completed_count > 0 THEN
        v_avg_ticket_cents := v_total_cents / v_completed_count;
    ELSE
        v_avg_ticket_cents := 0;
    END IF;
    v_result := jsonb_build_object(
        'total_billing_cents', v_total_cents,
        'total_billing_currency', ROUND(v_total_cents::NUMERIC / 100, 2),
        'completed_count', v_completed_count,
        'average_ticket_cents', v_avg_ticket_cents,
        'average_ticket_currency', ROUND(v_avg_ticket_cents::NUMERIC / 100, 2),
        'period', jsonb_build_object(
            'start', p_start_date,
            'end', p_end_date
        )
    );
    RETURN v_result;
END;
$function_body$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION get_billing_today(
    p_inbox_id UUID
)
RETURNS JSONB AS $function_body$
DECLARE
    v_today_start TIMESTAMPTZ;
BEGIN
    v_today_start := date_trunc('day', NOW());
    RETURN get_billing_by_period(
        p_inbox_id,
        v_today_start,
        NOW()
    );
END;
$function_body$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION get_billing_last_n_days(
    p_inbox_id UUID,
    p_days INT
)
RETURNS JSONB AS $function_body$
BEGIN
    RETURN get_billing_by_period(
        p_inbox_id,
        NOW() - (p_days || ' days')::INTERVAL,
        NOW()
    );
END;
$function_body$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION get_billing_specific_month(
    p_inbox_id UUID,
    p_year INT,
    p_month INT
)
RETURNS JSONB AS $function_body$
DECLARE
    v_start_date TIMESTAMPTZ;
    v_end_date TIMESTAMPTZ;
BEGIN
    IF p_month < 1 OR p_month > 12 THEN
        RAISE EXCEPTION 'Mês inválido: %. Deve estar entre 1 e 12.', p_month;
    END IF;
    v_start_date := make_timestamptz(p_year, p_month, 1, 0, 0, 0);
    v_end_date := v_start_date + INTERVAL '1 month';
    RETURN get_billing_by_period(
        p_inbox_id,
        v_start_date,
        v_end_date
    );
END;
$function_body$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION get_customer_ltv(
    p_root_id BIGINT
)
RETURNS JSONB AS $function_body$
DECLARE
    v_result JSONB;
BEGIN
    SELECT
        jsonb_build_object(
            'root_id', cr.id,
            'client_id', cr.client_id,
            'treatment_name', cr.treatment_name,
            'total_spent_cents', cr.total_spent_cents,
            'total_spent_currency', ROUND(cr.total_spent_cents::NUMERIC / 100, 2),
            'total_completed_appointments', cr.total_completed_appointments,
            'average_ticket_cents', CASE
                WHEN cr.total_completed_appointments > 0
                THEN cr.total_spent_cents / cr.total_completed_appointments
                ELSE 0
            END,
            'average_ticket_currency', CASE
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
    IF v_result IS NULL THEN
        RAISE EXCEPTION 'Cliente com root_id % não encontrado', p_root_id;
    END IF;
    RETURN v_result;
END;
$function_body$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION get_top_customers_by_ltv(
    p_inbox_id UUID,
    p_limit INT DEFAULT 10
)
RETURNS JSONB AS $function_body$
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
            'total_spent_currency', ROUND(cr.total_spent_cents::NUMERIC / 100, 2),
            'total_completed_appointments', cr.total_completed_appointments,
            'average_ticket_cents', CASE
                WHEN cr.total_completed_appointments > 0
                THEN cr.total_spent_cents / cr.total_completed_appointments
                ELSE 0
            END,
            'average_ticket_currency', CASE
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
$function_body$ LANGUAGE plpgsql;
CREATE OR REPLACE VIEW vw_customer_billing_summary AS
SELECT
    cr.id as root_id,
    cr.client_id,
    cr.inbox_id,
    cr.treatment_name,
    cr.total_spent_cents,
    ROUND(cr.total_spent_cents::NUMERIC / 100, 2) as total_spent_currency,
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
    END as average_ticket_currency,
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
CREATE OR REPLACE FUNCTION func_get_appointment_counters_by_period(
    p_inbox_id UUID,
    p_start_date TIMESTAMPTZ,
    p_end_date TIMESTAMPTZ
)
RETURNS JSONB AS $function_body$
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
$function_body$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION func_get_counters_last_n_days(
    p_inbox_id UUID,
    p_days INT
)
RETURNS JSONB AS $function_body$
BEGIN
    RETURN func_get_appointment_counters_by_period(
        p_inbox_id,
        NOW() - (p_days || ' days')::INTERVAL,
        NOW()
    );
END;
$function_body$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION func_get_counters_specific_month(
    p_inbox_id UUID,
    p_year INT,
    p_month INT
)
RETURNS JSONB AS $function_body$
DECLARE
    v_start_date TIMESTAMPTZ;
    v_end_date TIMESTAMPTZ;
BEGIN
    v_start_date := make_timestamptz(p_year, p_month, 1, 0, 0, 0);
    v_end_date := v_start_date + INTERVAL '1 month';
    RETURN func_get_appointment_counters_by_period(
        p_inbox_id,
        v_start_date,
        v_end_date
    );
END;
$function_body$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION func_count_status_changes(
    p_inbox_id UUID,
    p_status TEXT,
    p_start_date TIMESTAMPTZ,
    p_end_date TIMESTAMPTZ
)
RETURNS INTEGER AS $function_body$
DECLARE
    v_count INTEGER;
    v_column_name TEXT;
BEGIN
    v_column_name := CASE p_status
        WHEN 'Scheduled' THEN 'scheduled_at'
        WHEN 'Confirmed' THEN 'confirmed_at'
        WHEN 'Completed' THEN 'completed_at'
        WHEN 'Cancelled' THEN 'cancelled_at'
        WHEN 'Rescheduled' THEN 'rescheduled_at'
        WHEN 'No_Show' THEN 'no_show_at'
        ELSE NULL
    END;
    IF v_column_name IS NULL THEN
        RAISE WARNING 'Status inválido: %. Valores válidos: Scheduled, Confirmed, Completed, Cancelled, Rescheduled, No_Show', p_status;
        RETURN 0;
    END IF;
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
$function_body$ LANGUAGE plpgsql;
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
DROP TRIGGER IF EXISTS trig_sync_owner_to_cell ON "3a_customer_root_record";
CREATE TRIGGER trig_sync_owner_to_cell
    AFTER INSERT OR UPDATE ON "3a_customer_root_record"
    FOR EACH ROW
    EXECUTE FUNCTION func_sync_owner_to_cell_sheet();
DROP TRIGGER IF EXISTS trg_generate_client_id ON "3a_customer_root_record";
CREATE TRIGGER trg_generate_client_id
    BEFORE INSERT ON "3a_customer_root_record"
    FOR EACH ROW
    EXECUTE FUNCTION func_generate_friendly_client_id();
DROP TRIGGER IF EXISTS trg_generate_service_id ON "4a_customer_service_history";
CREATE TRIGGER trg_generate_service_id
    BEFORE INSERT ON "4a_customer_service_history"
    FOR EACH ROW
    EXECUTE FUNCTION func_generate_friendly_service_id();
DO $do_block$
DECLARE
    t text;
BEGIN
    FOR t IN 
        SELECT table_name 
        FROM information_schema.columns 
        WHERE column_name = 'updated_at' 
          AND table_schema = 'public'
    LOOP
        EXECUTE format('
            DROP TRIGGER IF EXISTS trigger_update_timestamp ON %I;
            CREATE TRIGGER trigger_update_timestamp
            BEFORE UPDATE ON %I
            FOR EACH ROW
            EXECUTE FUNCTION update_updated_at_column();
        ', t, t);
    END LOOP;
END$;
DROP TRIGGER IF EXISTS trg_first_cell_phone_is_primary ON "3b_cell_phone_linked_service_sheet";
CREATE TRIGGER trg_first_cell_phone_is_primary
    BEFORE INSERT ON "3b_cell_phone_linked_service_sheet"
    FOR EACH ROW
    EXECUTE FUNCTION func_ensure_first_is_primary();
DROP TRIGGER IF EXISTS trg_first_email_is_primary ON "3e_email";
CREATE TRIGGER trg_first_email_is_primary
    BEFORE INSERT ON "3e_email"
    FOR EACH ROW
    EXECUTE FUNCTION func_ensure_first_is_primary();
DROP TRIGGER IF EXISTS trg_first_landline_is_primary ON "3f_landline_phone";
CREATE TRIGGER trg_first_landline_is_primary
    BEFORE INSERT ON "3f_landline_phone"
    FOR EACH ROW
    EXECUTE FUNCTION func_ensure_first_is_primary();
DROP TRIGGER IF EXISTS trg_auto_populate_message ON "2b_conversation_messages";
CREATE TRIGGER trg_auto_populate_message
    BEFORE INSERT OR UPDATE ON "2b_conversation_messages"
    FOR EACH ROW
    EXECUTE FUNCTION func_auto_populate_message_fields();
DROP TRIGGER IF EXISTS trg_check_form_complete_3a ON "3a_customer_root_record";
CREATE TRIGGER trg_check_form_complete_3a
    AFTER INSERT OR UPDATE ON "3a_customer_root_record"
    FOR EACH ROW
    EXECUTE FUNCTION func_update_form_counter();
DROP TRIGGER IF EXISTS trg_check_form_complete_3b ON "3b_cell_phone_linked_service_sheet";
CREATE TRIGGER trg_check_form_complete_3b
    AFTER INSERT OR UPDATE ON "3b_cell_phone_linked_service_sheet"
    FOR EACH ROW
    EXECUTE FUNCTION func_update_form_counter();
DROP TRIGGER IF EXISTS trg_check_form_complete_3c ON "3c_gender";
CREATE TRIGGER trg_check_form_complete_3c
    AFTER INSERT OR UPDATE ON "3c_gender"
    FOR EACH ROW
    EXECUTE FUNCTION func_update_form_counter();
DROP TRIGGER IF EXISTS trg_check_form_complete_3d ON "3d_birth_date";
CREATE TRIGGER trg_check_form_complete_3d
    AFTER INSERT OR UPDATE ON "3d_birth_date"
    FOR EACH ROW
    EXECUTE FUNCTION func_update_form_counter();
DROP TRIGGER IF EXISTS trg_check_form_complete_3e ON "3e_email";
CREATE TRIGGER trg_check_form_complete_3e
    AFTER INSERT OR UPDATE ON "3e_email"
    FOR EACH ROW
    EXECUTE FUNCTION func_update_form_counter();
DROP TRIGGER IF EXISTS trg_check_form_complete_3f ON "3f_landline_phone";
CREATE TRIGGER trg_check_form_complete_3f
    AFTER INSERT OR UPDATE ON "3f_landline_phone"
    FOR EACH ROW
    EXECUTE FUNCTION func_update_form_counter();
DROP TRIGGER IF EXISTS trg_check_form_complete_3g ON "3g_cpf";
CREATE TRIGGER trg_check_form_complete_3g
    AFTER INSERT OR UPDATE ON "3g_cpf"
    FOR EACH ROW
    EXECUTE FUNCTION func_update_form_counter();
DROP TRIGGER IF EXISTS trg_check_form_complete_3h ON "3h_rg";
CREATE TRIGGER trg_check_form_complete_3h
    AFTER INSERT OR UPDATE ON "3h_rg"
    FOR EACH ROW
    EXECUTE FUNCTION func_update_form_counter();
DROP TRIGGER IF EXISTS trg_check_form_complete_3i ON "3i_endereco_br";
CREATE TRIGGER trg_check_form_complete_3i
    AFTER INSERT OR UPDATE ON "3i_endereco_br"
    FOR EACH ROW
    EXECUTE FUNCTION func_update_form_counter();
DROP TRIGGER IF EXISTS trg_set_status_timestamp ON "4a_customer_service_history";
CREATE TRIGGER trg_set_status_timestamp
    BEFORE INSERT OR UPDATE ON "4a_customer_service_history"
    FOR EACH ROW
    EXECUTE FUNCTION func_set_status_timestamp();
DROP TRIGGER IF EXISTS trg_update_appointment_status_counter ON "4a_customer_service_history";
CREATE TRIGGER trg_update_appointment_status_counter
    AFTER INSERT OR UPDATE ON "4a_customer_service_history"
    FOR EACH ROW
    EXECUTE FUNCTION func_update_appointment_status_counter();
CREATE OR REPLACE FUNCTION update_customer_ltv()
RETURNS TRIGGER AS $function_body$
DECLARE
    v_should_update BOOLEAN := FALSE;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.service_status = 'Completed' THEN
            v_should_update := TRUE;
        END IF;
    END IF;
    IF TG_OP = 'UPDATE' THEN
        IF NEW.service_status = 'Completed' AND OLD.service_status != 'Completed' THEN
            v_should_update := TRUE;
        END IF;
    END IF;
    IF v_should_update THEN
        IF NEW.value_cents IS NULL OR NEW.value_cents <= 0 THEN
            v_should_update := FALSE;
        END IF;
    END IF;
    IF NOT v_should_update THEN
        RETURN NEW;
    END IF;
    UPDATE "3a_customer_root_record"
    SET
        total_spent_cents = total_spent_cents + NEW.value_cents,
        total_completed_appointments = total_completed_appointments + 1,
        last_purchase_at = NEW.completed_at,
        first_purchase_at = CASE
            WHEN first_purchase_at IS NULL THEN NEW.completed_at
            ELSE first_purchase_at
        END,
        updated_at = NOW()
    WHERE id = NEW.root_id;
    RAISE NOTICE 'LTV atualizado para root_id %: +% centavos (total agora: %)',
        NEW.root_id,
        NEW.value_cents,
        (SELECT total_spent_cents FROM "3a_customer_root_record" WHERE id = NEW.root_id);
    RETURN NEW;
END;
$function_body$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trigger_update_customer_ltv ON "4a_customer_service_history";
CREATE TRIGGER trigger_update_customer_ltv
    AFTER INSERT OR UPDATE OF service_status
    ON "4a_customer_service_history"
    FOR EACH ROW
    EXECUTE FUNCTION update_customer_ltv();
CREATE OR REPLACE FUNCTION recalculate_customer_ltv(
    p_root_id BIGINT
)
RETURNS JSONB AS $function_body$
DECLARE
    v_total_cents BIGINT;
    v_completed_count INT;
    v_first_purchase TIMESTAMPTZ;
    v_last_purchase TIMESTAMPTZ;
    v_result JSONB;
BEGIN
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
    UPDATE "3a_customer_root_record"
    SET
        total_spent_cents = v_total_cents,
        total_completed_appointments = v_completed_count,
        first_purchase_at = v_first_purchase,
        last_purchase_at = v_last_purchase,
        updated_at = NOW()
    WHERE id = p_root_id;
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
$function_body$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION recalculate_all_ltv_for_inbox(
    p_inbox_id UUID
)
RETURNS JSONB AS $function_body$
DECLARE
    v_customer_count INT;
    v_total_billing BIGINT := 0;
    v_customer RECORD;
    v_result JSONB;
BEGIN
    v_customer_count := 0;
    FOR v_customer IN
        SELECT id FROM "3a_customer_root_record"
        WHERE inbox_id = p_inbox_id
    LOOP
        PERFORM recalculate_customer_ltv(v_customer.id);
        v_customer_count := v_customer_count + 1;
    END LOOP;
    SELECT COALESCE(SUM(total_spent_cents), 0)
    INTO v_total_billing
    FROM "3a_customer_root_record"
    WHERE inbox_id = p_inbox_id;
    v_result := jsonb_build_object(
        'inbox_id', p_inbox_id,
        'customers_processed', v_customer_count,
        'total_billing_cents', v_total_billing,
        'total_billing_currency', ROUND(v_total_billing::NUMERIC / 100, 2),
        'recalculated_at', NOW()
    );
    RETURN v_result;
END;
$function_body$ LANGUAGE plpgsql;
COMMIT;
