-- =================================================================================================
-- MÓDULO: FUNÇÕES E GATILHOS DO WORKFLOW AGES
-- =================================================================================================
-- DESCRIÇÃO: 
--   Este módulo centraliza todas as funções de negócio e triggers do sistema AGES.
--   Responsável por:
--   - Sincronização de dados entre tabelas
--   - Geração de IDs amigáveis sequenciais
--   - Atualização automática de timestamps
--   - Manutenção de integridade referencial
-- -------------------------------------------------------------------------------------------------
-- VERSÃO: 1.1
-- DATA: 2025-11-14
-- -------------------------------------------------------------------------------------------------

-- =================================================================================================
-- SEÇÃO 1: FUNÇÕES DE NEGÓCIO
-- =================================================================================================
-- Esta seção contém as funções principais do sistema, organizadas por responsabilidade:
--
-- 1.1 SINCRONIZAÇÃO DE DADOS
--     └─ func_upsert_contact_from_webhook ........ Sincroniza dados do Webhook PING
--     └─ func_sync_owner_to_cell_sheet ........... Propaga whatsapp_owner para cell_phone
--
-- 1.2 GERAÇÃO DE IDS AMIGÁVEIS
--     └─ func_generate_friendly_client_id ........ Gera IDs tipo "CT1", "CT2"...
--     └─ func_generate_friendly_service_id ....... Gera IDs tipo "AT1", "AT2"...
--
-- 1.3 MARCAÇÃO AUTOMÁTICA DE PRIMÁRIO
--     └─ func_ensure_first_is_primary ............ Garante primeiro registro como primário
--
-- 1.4 AUTOMAÇÃO DE MENSAGENS
--     └─ func_generate_ulid ....................... Gera ULID para rastreio
--     └─ func_auto_populate_message_fields ........ Preenche source_message_id e tsvector
--
-- 1.5 UTILITÁRIOS AUTOMÁTICOS
--     └─ update_updated_at_column ................ Atualiza campo updated_at automaticamente
-- =================================================================================================


-- -------------------------------------------------------------------------------------------------
-- 1.1 SINCRONIZAÇÃO DE DADOS
-- -------------------------------------------------------------------------------------------------

-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNÇÃO: func_upsert_contact_from_webhook                                                    │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   Sincroniza dados recebidos do Webhook PING com as tabelas locais de forma atômica.        │
-- │   Realiza UPSERT em duas tabelas: inbox e contatos.                                         │
-- │                                                                                             │
-- │ TABELAS AFETADAS:                                                                           │
-- │   • 0a_inbox_whatsapp ............. (INSERT/UPDATE) Dados da inbox                          │
-- │   • 1a_whatsapp_user_contact ...... (INSERT/UPDATE) Dados do contato                        │
-- │                                                                                             │
-- │ CARACTERÍSTICAS:                                                                            │
-- │   ✓ Operação atômica (tudo ou nada)                                                         │
-- │   ✓ Idempotente (pode ser executada múltiplas vezes com segurança)                          │
-- │   ✓ Usa COALESCE para preservar dados existentes quando o parâmetro é NULL                  │
-- │   ✓ Atualiza updated_at automaticamente                                                     │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
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
RETURNS void AS $$
BEGIN
  -- Validação de parâmetros obrigatórios
  IF p_inbox_id IS NULL OR p_owner_wallet_id IS NULL OR p_wallet_id IS NULL THEN
    RAISE EXCEPTION 'Parâmetros obrigatórios faltando: inbox_id, owner_wallet_id, wallet_id';
  END IF;

  -- UPSERT Inbox (atômico e idempotente)
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

  -- UPSERT Contato (atômico e idempotente)
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

EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Erro na função func_upsert_contact_from_webhook: % - %', SQLERRM, SQLSTATE;
END;
$$ LANGUAGE plpgsql;


-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNÇÃO: func_sync_owner_to_cell_sheet                                                       │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   Sincroniza automaticamente o campo 'whatsapp_owner' da tabela 3a para a tabela 3b.        │
-- │   Garante que toda ficha de cliente tenha pelo menos um telefone WhatsApp associado.        │
-- │                                                                                             │
-- │ FLUXO:                                                                                      │
-- │   1. Busca o wallet_id na tabela 1a usando phone_number e inbox_id                          │
-- │   2. Se encontrar, faz UPSERT na tabela 3b com is_primary=TRUE                              │
-- │   3. Se não encontrar, apenas retorna (aguarda criação do contato)                          │
-- │                                                                                             │
-- │ TABELAS AFETADAS:                                                                           │
-- │   • 1a_whatsapp_user_contact ...... (SELECT) Busca wallet_id pelo telefone                  │
-- │   • 3b_cell_phone_linked_service .. (INSERT/UPDATE) Registra telefone primário              │
-- │                                                                                             │
-- │ OBSERVAÇÕES:                                                                                │
-- │   • Usada como função de TRIGGER (retorna TRIGGER)                                          │
-- │   • Executa AFTER INSERT/UPDATE na tabela 3a_customer_root_record                           │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION func_sync_owner_to_cell_sheet()
RETURNS TRIGGER AS $$
DECLARE
    v_wallet_id UUID;
BEGIN
    -- Busca wallet_id do contato usando phone_number e inbox_id
    SELECT wallet_id INTO v_wallet_id
    FROM "1a_whatsapp_user_contact"
    WHERE phone_number = NEW.whatsapp_owner
      AND inbox_id = NEW.inbox_id
    LIMIT 1;

    -- Se o contato ainda não existe na tabela 1a, apenas retorna
    IF v_wallet_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- UPSERT do telefone na tabela 3b marcando como primário
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
$$ LANGUAGE plpgsql;


-- -------------------------------------------------------------------------------------------------
-- 1.2 GERAÇÃO DE IDS AMIGÁVEIS
-- -------------------------------------------------------------------------------------------------

-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNÇÃO: func_generate_friendly_client_id                                                    │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   Gera IDs sequenciais amigáveis para clientes no formato "CT1", "CT2", "CT3"...            │
-- │                                                                                             │
-- │ FUNCIONAMENTO:                                                                              │
-- │   1. Incrementa atomicamente o contador 'client_count' na tabela 0b_inbox_counters          │
-- │   2. Atribui o valor formatado ao campo 'client_id' do registro sendo inserido              │
-- │   3. Se a inbox não tem contador, cria um iniciando em 1                                    │
-- │                                                                                             │
-- │ TABELAS AFETADAS:                                                                           │
-- │   • 0b_inbox_counters ............. (UPDATE/INSERT) Gerencia contadores por inbox           │
-- │                                                                                             │
-- │ CARACTERÍSTICAS:                                                                            │
-- │   ✓ Thread-safe (usa UPDATE ... RETURNING para atomicidade)                                 │
-- │   ✓ Cada inbox tem sua própria sequência independente                                       │
-- │   ✓ Usada como função de TRIGGER (BEFORE INSERT)                                            │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION func_generate_friendly_client_id()
RETURNS TRIGGER AS $$
DECLARE
    new_count INT;
BEGIN
    -- Incrementa o contador atomicamente e retorna o novo valor
    UPDATE "0b_inbox_counters"
    SET client_count = client_count + 1
    WHERE inbox_id = NEW.inbox_id
    RETURNING client_count INTO new_count;
    
    -- Se não houver contador (primeira vez), cria um
    IF NOT FOUND THEN
        new_count := 1;
        INSERT INTO "0b_inbox_counters" (inbox_id, client_count, atendimento_count)
        VALUES (NEW.inbox_id, new_count, 0)
        ON CONFLICT (inbox_id) DO NOTHING;
    END IF;
    
    -- Atribui o ID formatado ao registro
    NEW.client_id := 'CT' || new_count::text;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNÇÃO: func_generate_friendly_service_id                                                   │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   Gera IDs sequenciais amigáveis para atendimentos no formato "AT1", "AT2", "AT3"...        │
-- │                                                                                             │
-- │ FUNCIONAMENTO:                                                                              │
-- │   Idêntico à func_generate_friendly_client_id, mas usa o contador 'atendimento_count'       │
-- │   e gera IDs com prefixo "AT" (Atendimento)                                                 │
-- │                                                                                             │
-- │ TABELAS AFETADAS:                                                                           │
-- │   • 0b_inbox_counters ............. (UPDATE/INSERT) Gerencia contadores por inbox           │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION func_generate_friendly_service_id()
RETURNS TRIGGER AS $$
DECLARE
    new_count INT;
BEGIN
    -- Incrementa o contador atomicamente e retorna o novo valor
    UPDATE "0b_inbox_counters"
    SET atendimento_count = atendimento_count + 1
    WHERE inbox_id = NEW.inbox_id
    RETURNING atendimento_count INTO new_count;
    
    -- Se não houver contador (primeira vez), cria um
    IF NOT FOUND THEN
        new_count := 1;
        INSERT INTO "0b_inbox_counters" (inbox_id, client_count, atendimento_count)
        VALUES (NEW.inbox_id, 0, new_count)
        ON CONFLICT (inbox_id) DO UPDATE 
        SET atendimento_count = new_count;
    END IF;
    
    -- Atribui o ID formatado ao registro
    NEW.service_id := 'AT' || new_count::text;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- -------------------------------------------------------------------------------------------------
-- 1.3 MARCAÇÃO AUTOMÁTICA DE PRIMÁRIO
-- -------------------------------------------------------------------------------------------------

-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNÇÃO: func_ensure_first_is_primary                                                        │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   Garante que o PRIMEIRO registro inserido para uma ficha (root_id) seja automaticamente    │
-- │   marcado como primário (is_primary = TRUE).                                                │
-- │   Registros subsequentes mantêm is_primary = FALSE por padrão.                              │
-- │                                                                                             │
-- │ LÓGICA:                                                                                     │
-- │   1. Verifica se já existe algum registro para aquele root_id                               │
-- │   2. Se NÃO existir nenhum → força is_primary = TRUE (é o primeiro!)                        │
-- │   3. Se JÁ existir algum → mantém o valor informado (padrão FALSE)                          │
-- │                                                                                             │
-- │ APLICÁVEL EM:                                                                               │
-- │   • 3b_cell_phone_linked_service_sheet ... Primeiro telefone                                │
-- │   • 3e_email ............................ Primeiro e-mail                                   │
-- │   • 3f_landline_phone ................... Primeiro telefone fixo                            │
-- │                                                                                             │
-- │ CARACTERÍSTICAS:                                                                            │
-- │   ✓ Genérica (funciona em qualquer tabela com root_id e is_primary)                         │
-- │   ✓ Executa BEFORE INSERT                                                                   │
-- │   ✓ Não interfere se o usuário explicitamente definir is_primary = TRUE                     │
-- │   ✓ Idempotente e thread-safe                                                               │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION func_ensure_first_is_primary()
RETURNS TRIGGER AS $$
DECLARE
    v_count INT;
BEGIN
    -- Conta quantos registros já existem para este root_id
    EXECUTE format('SELECT COUNT(*) FROM %I WHERE root_id = $1', TG_TABLE_NAME)
    INTO v_count
    USING NEW.root_id;
    
    -- Se não existir nenhum registro, este é o primeiro → força is_primary = TRUE
    IF v_count = 0 THEN
        NEW.is_primary := TRUE;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- -------------------------------------------------------------------------------------------------
-- 1.4 AUTOMAÇÃO DE MENSAGENS
-- -------------------------------------------------------------------------------------------------

-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNÇÃO: func_generate_ulid                                                                  │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   Gera um ULID (Universally Unique Lexicographically Sortable Identifier) para              │
-- │   rastreamento interno de mensagens.                                                        │
-- │                                                                                             │
-- │ CARACTERÍSTICAS DO ULID:                                                                    │
-- │   • 26 caracteres (Base32)                                                                  │
-- │   • Ordenável cronologicamente (timestamp nos primeiros 10 chars)                           │
-- │   • Mais legível que UUID                                                                   │
-- │   • Compatível com índices de string                                                        │
-- │                                                                                             │
-- │ FORMATO:                                                                                    │
-- │   TTTTTTTTTTRRRRRRRRRRRRRRRR                                                                │
-- │   └─ 10 chars timestamp (milissegundos desde epoch)                                         │
-- │              └─ 16 chars aleatórios                                                         │
-- │                                                                                             │
-- │ EXEMPLO:                                                                                    │
-- │   01HW5Z8K7F9G2M3N4P5Q6R7S8T                                                                │
-- │                                                                                             │
-- │ OBSERVAÇÃO:                                                                                 │
-- │   Implementação pura em PL/pgSQL sem dependências externas.                                 │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION func_generate_ulid()
RETURNS TEXT AS $$
DECLARE
    -- Timestamp em milissegundos desde epoch Unix
    unix_time BIGINT;
    -- Parte aleatória do ULID
    randomness TEXT := '';
    -- Alfabeto Crockford Base32 (sem I, L, O, U para evitar confusão)
    encoding TEXT := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    -- Resultado final
    output TEXT := '';
    -- Variáveis auxiliares
    i INT;
    rand_byte INT;
BEGIN
    -- 1. TIMESTAMP (10 caracteres)
    -- Obtém timestamp atual em milissegundos
    unix_time := (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT;
    
    -- Converte para Base32 (10 chars)
    FOR i IN REVERSE 9..0 LOOP
        output := output || SUBSTRING(encoding FROM ((unix_time >> (i * 5)) & 31) + 1 FOR 1);
    END LOOP;
    
    -- 2. RANDOMNESS (16 caracteres)
    -- Gera 16 caracteres aleatórios usando Base32
    FOR i IN 1..16 LOOP
        -- Gera número aleatório entre 0-31
        rand_byte := FLOOR(RANDOM() * 32)::INT;
        randomness := randomness || SUBSTRING(encoding FROM rand_byte + 1 FOR 1);
    END LOOP;
    
    RETURN output || randomness;
END;
$$ LANGUAGE plpgsql VOLATILE;


-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNÇÃO: func_auto_populate_message_fields                                                   │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   Automatiza o preenchimento de campos de mensagens antes da inserção:                      │
-- │   1. Gera source_message_id interno (ULID) para mensagens do sistema                        │
-- │   2. Popula message_content_tsv para busca full-text em português                           │
-- │                                                                                             │
-- │ LÓGICA:                                                                                     │
-- │   • source_message_id:                                                                      │
-- │     - Se vazio E sender_type ∈ {ai_agent, human_agent, system} → Gera ULID                  │
-- │     - Se já preenchido (mensagem de contact) → Mantém o valor                               │
-- │                                                                                             │
-- │   • message_content_tsv:                                                                    │
-- │     - Se message_content não for NULL → Converte para tsvector português                    │
-- │     - Usa configuração 'portuguese' para stemming correto                                   │
-- │                                                                                             │
-- │ TABELA AFETADA:                                                                             │
-- │   • 2b_conversation_messages ... (INSERT/UPDATE) Preenche campos automáticos                │
-- │                                                                                             │
-- │ CARACTERÍSTICAS:                                                                            │
-- │   ✓ Executa BEFORE INSERT OR UPDATE                                                         │
-- │   ✓ Preserva source_message_id de mensagens externas (WhatsApp)                             │
-- │   ✓ Otimiza busca full-text com tsvector indexado                                           │
-- │   ✓ Suporta atualização de mensagens                                                        │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION func_auto_populate_message_fields()
RETURNS TRIGGER AS $$
BEGIN
    -- 1. GERAR source_message_id INTERNO (apenas para mensagens internas)
    -- Se o campo está vazio/nulo E é uma mensagem interna → gera ULID
    IF (NEW.source_message_id IS NULL OR NEW.source_message_id = '') AND
       NEW.sender_type IN ('ai_agent', 'human_agent', 'system') THEN
        NEW.source_message_id := func_generate_ulid();
    END IF;
    
    -- 2. POPULAR message_content_tsv para busca full-text
    -- Se há conteúdo de mensagem → converte para tsvector em português
    IF NEW.message_content IS NOT NULL AND NEW.message_content <> '' THEN
        NEW.message_content_tsv := to_tsvector('portuguese', NEW.message_content);
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- -------------------------------------------------------------------------------------------------
-- 1.5 UTILITÁRIOS AUTOMÁTICOS
-- -------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;



-- =================================================================================================
-- FIM DO MÓDULO
-- =================================================================================================
-- Para visualizar todos os triggers ativos no banco:
--   SELECT * FROM information_schema.triggers WHERE trigger_schema = 'public';
--
-- Para ver funções criadas:
--   SELECT routine_name FROM information_schema.routines 
--   WHERE routine_schema = 'public' AND routine_type = 'FUNCTION';
--
-- Para testar geração de ULID:
--   SELECT func_generate_ulid();
--
-- Para visualizar mensagens e seus IDs:
--   SELECT id, sender_type, source_message_id, 
--          LEFT(message_content, 50) as preview
--   FROM "2b_conversation_messages"
--   ORDER BY message_timestamp DESC;
-- 
-- ==============================================================================================                                                                           │
-- │   ✓ Operação atômica (tudo ou nada)                                                         │
-- │   ✓ Idempotente (pode ser executada múltiplas vezes com segurança)                          │
-- │   ✓ Usa COALESCE para preservar dados existentes quando o parâmetro é NULL                  │
-- │   ✓ Atualiza updated_at automaticamente                                                     │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
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
RETURNS void AS $$
BEGIN
  -- Validação de parâmetros obrigatórios
  IF p_inbox_id IS NULL OR p_owner_wallet_id IS NULL OR p_wallet_id IS NULL THEN
    RAISE EXCEPTION 'Parâmetros obrigatórios faltando: inbox_id, owner_wallet_id, wallet_id';
  END IF;

  -- UPSERT Inbox (atômico e idempotente)
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

  -- UPSERT Contato (atômico e idempotente)
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

EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Erro na função func_upsert_contact_from_webhook: % - %', SQLERRM, SQLSTATE;
END;
$$ LANGUAGE plpgsql;


-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNÇÃO: func_sync_owner_to_cell_sheet                                                       │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   Sincroniza automaticamente o campo 'whatsapp_owner' da tabela 3a para a tabela 3b.        │
-- │   Garante que toda ficha de cliente tenha pelo menos um telefone WhatsApp associado.        │
-- │                                                                                             │
-- │ FLUXO:                                                                                      │
-- │   1. Busca o wallet_id na tabela 1a usando phone_number e inbox_id                          │
-- │   2. Se encontrar, faz UPSERT na tabela 3b com is_primary=TRUE                              │
-- │   3. Se não encontrar, apenas retorna (aguarda criação do contato)                          │
-- │                                                                                             │
-- │ TABELAS AFETADAS:                                                                           │
-- │   • 1a_whatsapp_user_contact ...... (SELECT) Busca wallet_id pelo telefone                  │
-- │   • 3b_cell_phone_linked_service .. (INSERT/UPDATE) Registra telefone primário              │
-- │                                                                                             │
-- │ OBSERVAÇÕES:                                                                                │
-- │   • Usada como função de TRIGGER (retorna TRIGGER)                                          │
-- │   • Executa AFTER INSERT/UPDATE na tabela 3a_customer_root_record                           │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION func_sync_owner_to_cell_sheet()
RETURNS TRIGGER AS $$
DECLARE
    v_wallet_id UUID;
BEGIN
    -- Busca wallet_id do contato usando phone_number e inbox_id
    SELECT wallet_id INTO v_wallet_id
    FROM "1a_whatsapp_user_contact"
    WHERE phone_number = NEW.whatsapp_owner
      AND inbox_id = NEW.inbox_id
    LIMIT 1;

    -- Se o contato ainda não existe na tabela 1a, apenas retorna
    IF v_wallet_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- UPSERT do telefone na tabela 3b marcando como primário
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
$$ LANGUAGE plpgsql;


-- -------------------------------------------------------------------------------------------------
-- 1.2 GERAÇÃO DE IDS AMIGÁVEIS
-- -------------------------------------------------------------------------------------------------

-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNÇÃO: func_generate_friendly_client_id                                                    │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   Gera IDs sequenciais amigáveis para clientes no formato "CT1", "CT2", "CT3"...            │
-- │                                                                                             │
-- │ FUNCIONAMENTO:                                                                              │
-- │   1. Incrementa atomicamente o contador 'client_count' na tabela 0b_inbox_counters          │
-- │   2. Atribui o valor formatado ao campo 'client_id' do registro sendo inserido              │
-- │   3. Se a inbox não tem contador, cria um iniciando em 1                                    │
-- │                                                                                             │
-- │ TABELAS AFETADAS:                                                                           │
-- │   • 0b_inbox_counters ............. (UPDATE/INSERT) Gerencia contadores por inbox           │
-- │                                                                                             │
-- │ CARACTERÍSTICAS:                                                                            │
-- │   ✓ Thread-safe (usa UPDATE ... RETURNING para atomicidade)                                 │
-- │   ✓ Cada inbox tem sua própria sequência independente                                       │
-- │   ✓ Usada como função de TRIGGER (BEFORE INSERT)                                            │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION func_generate_friendly_client_id()
RETURNS TRIGGER AS $$
DECLARE
    new_count INT;
BEGIN
    -- Incrementa o contador atomicamente e retorna o novo valor
    UPDATE "0b_inbox_counters"
    SET client_count = client_count + 1
    WHERE inbox_id = NEW.inbox_id
    RETURNING client_count INTO new_count;
    
    -- Se não houver contador (primeira vez), cria um
    IF NOT FOUND THEN
        new_count := 1;
        INSERT INTO "0b_inbox_counters" (inbox_id, client_count, atendimento_count)
        VALUES (NEW.inbox_id, new_count, 0)
        ON CONFLICT (inbox_id) DO NOTHING;
    END IF;
    
    -- Atribui o ID formatado ao registro
    NEW.client_id := 'CT' || new_count::text;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNÇÃO: func_generate_friendly_service_id                                                   │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   Gera IDs sequenciais amigáveis para atendimentos no formato "AT1", "AT2", "AT3"...        │
-- │                                                                                             │
-- │ FUNCIONAMENTO:                                                                              │
-- │   Idêntico à func_generate_friendly_client_id, mas usa o contador 'atendimento_count'       │
-- │   e gera IDs com prefixo "AT" (Atendimento)                                                 │
-- │                                                                                             │
-- │ TABELAS AFETADAS:                                                                           │
-- │   • 0b_inbox_counters ............. (UPDATE/INSERT) Gerencia contadores por inbox           │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION func_generate_friendly_service_id()
RETURNS TRIGGER AS $$
DECLARE
    new_count INT;
BEGIN
    -- Incrementa o contador atomicamente e retorna o novo valor
    UPDATE "0b_inbox_counters"
    SET atendimento_count = atendimento_count + 1
    WHERE inbox_id = NEW.inbox_id
    RETURNING atendimento_count INTO new_count;
    
    -- Se não houver contador (primeira vez), cria um
    IF NOT FOUND THEN
        new_count := 1;
        INSERT INTO "0b_inbox_counters" (inbox_id, client_count, atendimento_count)
        VALUES (NEW.inbox_id, 0, new_count)
        ON CONFLICT (inbox_id) DO UPDATE 
        SET atendimento_count = new_count;
    END IF;
    
    -- Atribui o ID formatado ao registro
    NEW.service_id := 'AT' || new_count::text;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- -------------------------------------------------------------------------------------------------
-- 1.3 MARCAÇÃO AUTOMÁTICA DE PRIMÁRIO
-- -------------------------------------------------------------------------------------------------

-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNÇÃO: func_ensure_first_is_primary                                                        │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   Garante que o PRIMEIRO registro inserido para uma ficha (root_id) seja automaticamente    │
-- │   marcado como primário (is_primary = TRUE).                                                │
-- │   Registros subsequentes mantêm is_primary = FALSE por padrão.                              │
-- │                                                                                             │
-- │ LÓGICA:                                                                                     │
-- │   1. Verifica se já existe algum registro para aquele root_id                               │
-- │   2. Se NÃO existir nenhum → força is_primary = TRUE (é o primeiro!)                        │
-- │   3. Se JÁ existir algum → mantém o valor informado (padrão FALSE)                          │
-- │                                                                                             │
-- │ APLICÁVEL EM:                                                                               │
-- │   • 3b_cell_phone_linked_service_sheet ... Primeiro telefone                                │
-- │   • 3e_email ............................ Primeiro e-mail                                   │
-- │   • 3f_landline_phone ................... Primeiro telefone fixo                            │
-- │                                                                                             │
-- │ CARACTERÍSTICAS:                                                                            │
-- │   ✓ Genérica (funciona em qualquer tabela com root_id e is_primary)                         │
-- │   ✓ Executa BEFORE INSERT                                                                   │
-- │   ✓ Não interfere se o usuário explicitamente definir is_primary = TRUE                     │
-- │   ✓ Idempotente e thread-safe                                                               │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION func_ensure_first_is_primary()
RETURNS TRIGGER AS $$
DECLARE
    v_count INT;
BEGIN
    -- Conta quantos registros já existem para este root_id
    EXECUTE format('SELECT COUNT(*) FROM %I WHERE root_id = $1', TG_TABLE_NAME)
    INTO v_count
    USING NEW.root_id;
    
    -- Se não existir nenhum registro, este é o primeiro → força is_primary = TRUE
    IF v_count = 0 THEN
        NEW.is_primary := TRUE;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- -------------------------------------------------------------------------------------------------
-- 1.4 AUTOMAÇÃO DE MENSAGENS
-- -------------------------------------------------------------------------------------------------

-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNÇÃO: func_generate_ulid                                                                  │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   Gera um ULID (Universally Unique Lexicographically Sortable Identifier) para              │
-- │   rastreamento interno de mensagens.                                                        │
-- │                                                                                             │
-- │ CARACTERÍSTICAS DO ULID:                                                                    │
-- │   • 26 caracteres (Base32)                                                                  │
-- │   • Ordenável cronologicamente (timestamp nos primeiros 10 chars)                           │
-- │   • Mais legível que UUID                                                                   │
-- │   • Compatível com índices de string                                                        │
-- │                                                                                             │
-- │ FORMATO:                                                                                    │
-- │   TTTTTTTTTTRRRRRRRRRRRRRRRR                                                                │
-- │   └─ 10 chars timestamp (milissegundos desde epoch)                                         │
-- │              └─ 16 chars aleatórios                                                         │
-- │                                                                                             │
-- │ EXEMPLO:                                                                                    │
-- │   01HW5Z8K7F9G2M3N4P5Q6R7S8T                                                                │
-- │                                                                                             │
-- │ OBSERVAÇÃO:                                                                                 │
-- │   Implementação pura em PL/pgSQL sem dependências externas.                                 │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION func_generate_ulid()
RETURNS TEXT AS $$
DECLARE
    -- Timestamp em milissegundos desde epoch Unix
    unix_time BIGINT;
    -- Parte aleatória do ULID
    randomness TEXT := '';
    -- Alfabeto Crockford Base32 (sem I, L, O, U para evitar confusão)
    encoding TEXT := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    -- Resultado final
    output TEXT := '';
    -- Variáveis auxiliares
    i INT;
    rand_byte INT;
BEGIN
    -- 1. TIMESTAMP (10 caracteres)
    -- Obtém timestamp atual em milissegundos
    unix_time := (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT;
    
    -- Converte para Base32 (10 chars)
    FOR i IN REVERSE 9..0 LOOP
        output := output || SUBSTRING(encoding FROM ((unix_time >> (i * 5)) & 31) + 1 FOR 1);
    END LOOP;
    
    -- 2. RANDOMNESS (16 caracteres)
    -- Gera 16 caracteres aleatórios usando Base32
    FOR i IN 1..16 LOOP
        -- Gera número aleatório entre 0-31
        rand_byte := FLOOR(RANDOM() * 32)::INT;
        randomness := randomness || SUBSTRING(encoding FROM rand_byte + 1 FOR 1);
    END LOOP;
    
    RETURN output || randomness;
END;
$$ LANGUAGE plpgsql VOLATILE;


-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNÇÃO: func_auto_populate_message_fields                                                   │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   Automatiza o preenchimento de campos de mensagens antes da inserção:                      │
-- │   1. Gera source_message_id interno (ULID) para mensagens do sistema                        │
-- │   2. Popula message_content_tsv para busca full-text em português                           │
-- │                                                                                             │
-- │ LÓGICA:                                                                                     │
-- │   • source_message_id:                                                                      │
-- │     - Se vazio E sender_type ∈ {ai_agent, human_agent, system} → Gera ULID                  │
-- │     - Se já preenchido (mensagem de contact) → Mantém o valor                               │
-- │                                                                                             │
-- │   • message_content_tsv:                                                                    │
-- │     - Se message_content não for NULL → Converte para tsvector português                    │
-- │     - Usa configuração 'portuguese' para stemming correto                                   │
-- │                                                                                             │
-- │ TABELA AFETADA:                                                                             │
-- │   • 2b_conversation_messages ... (INSERT/UPDATE) Preenche campos automáticos                │
-- │                                                                                             │
-- │ CARACTERÍSTICAS:                                                                            │
-- │   ✓ Executa BEFORE INSERT OR UPDATE                                                         │
-- │   ✓ Preserva source_message_id de mensagens externas (WhatsApp)                             │
-- │   ✓ Otimiza busca full-text com tsvector indexado                                           │
-- │   ✓ Suporta atualização de mensagens                                                        │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION func_auto_populate_message_fields()
RETURNS TRIGGER AS $$
BEGIN
    -- 1. GERAR source_message_id INTERNO (apenas para mensagens internas)
    -- Se o campo está vazio/nulo E é uma mensagem interna → gera ULID
    IF (NEW.source_message_id IS NULL OR NEW.source_message_id = '') AND
       NEW.sender_type IN ('ai_agent', 'human_agent', 'system') THEN
        NEW.source_message_id := func_generate_ulid();
    END IF;
    
    -- 2. POPULAR message_content_tsv para busca full-text
    -- Se há conteúdo de mensagem → converte para tsvector em português
    IF NEW.message_content IS NOT NULL AND NEW.message_content <> '' THEN
        NEW.message_content_tsv := to_tsvector('portuguese', NEW.message_content);
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- -------------------------------------------------------------------------------------------------
-- 1.5 UTILITÁRIOS AUTOMÁTICOS
-- -------------------------------------------------------------------------------------------------

-- ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
-- │ FUNÇÃO: update_updated_at_column                                                            │
-- ├─────────────────────────────────────────────────────────────────────────────────────────────┤
-- │ PROPÓSITO:                                                                                  │
-- │   Atualiza automaticamente o campo 'updated_at' para NOW() em qualquer operação UPDATE.     │
-- │   Esta é uma função genérica aplicada a todas as tabelas que possuem a coluna updated_at.   │
-- │                                                                                             │
-- │ USO:                                                                                        │
-- │   Esta função é aplicada automaticamente via trigger dinâmico (ver triggers.sql).           │
-- │   O sistema descobre todas as tabelas com coluna 'updated_at' e aplica o trigger.           │
-- │                                                                                             │
-- │ COMPORTAMENTO:                                                                              │
-- │   • Executa BEFORE UPDATE                                                                   │
-- │   • Atribui NOW() ao campo updated_at do registro sendo atualizado                          │
-- │   • Não interfere em operações INSERT (updated_at já tem DEFAULT NOW())                     │
-- │                                                                                             │
-- │ TABELAS AFETADAS (aplicado dinamicamente):                                                  │
-- │   • 0a_inbox_whatsapp                                                                       │
-- │   • 0b_inbox_counters (se tiver updated_at)                                                 │
-- │   • 1a_whatsapp_user_contact                                                                │
-- │   • 2b_conversation_messages (se tiver updated_at)                                          │
-- │   • 3a_customer_root_record                                                                 │
-- │   • 3b_cell_phone_linked_service_sheet                                                      │
-- │   • 3c_gender                                                                               │
-- │   • 3d_birth_date                                                                           │
-- │   • 3e_email                                                                                │
-- │   • 3f_landline_phone                                                                       │
-- │   • 3g_cpf                                                                                  │
-- │   • 3h_rg                                                                                   │
-- │   • 3i_endereco_br                                                                          │
-- │   • 4a_customer_service_history                                                             │
-- │   • ... (qualquer outra tabela com updated_at)                                              │
-- │                                                                                             │
-- │ CARACTERÍSTICAS:                                                                            │
-- │   ✓ Genérica - Funciona em qualquer tabela                                                  │
-- │   ✓ Transparente - Desenvolvedor não precisa se preocupar com updated_at                    │
-- │   ✓ Consistente - Garante timestamp sempre atualizado                                       │
-- │   ✓ Performance - Overhead mínimo (apenas atribuição de timestamp)                          │
-- │                                                                                             │
-- │ EXEMPLO DE USO:                                                                             │
-- │   -- O trigger é aplicado automaticamente, então basta fazer UPDATE normal:                 │
-- │   UPDATE "1a_whatsapp_user_contact"                                                         │
-- │   SET push_name = 'Novo Nome'                                                               │
-- │   WHERE wallet_id = 'uuid-123';                                                             │
-- │   -- O campo updated_at será automaticamente atualizado para NOW()                          │
-- │                                                                                             │
-- │ TRIGGER ASSOCIADO:                                                                          │
-- │   trigger_update_timestamp (criado dinamicamente em triggers.sql)                           │
-- │                                                                                             │
-- │ OBSERVAÇÕES:                                                                                │
-- │   • Esta função NÃO deve ser chamada manualmente                                            │
-- │   • É invocada automaticamente pelo trigger BEFORE UPDATE                                   │
-- │   • Se uma tabela não tiver updated_at, o trigger não é aplicado                            │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    -- Atribui o timestamp atual ao campo updated_at do registro sendo atualizado
    NEW.updated_at = NOW();
    
    -- Retorna o registro modificado para que a operação UPDATE continue
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;



