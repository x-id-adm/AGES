-- #################################################################################################
-- =================================================================================================
-- # GATILHOS (TRIGGERS)
-- =================================================================================================
-- Esta seção contém todos os triggers do sistema, organizados por tabela alvo:
--
-- 2.1 TRIGGERS DE SINCRONIZAÇÃO
--     └─ trig_sync_owner_to_cell ............. [3a_customer_root_record] → Sincroniza whatsapp
--
-- 2.2 TRIGGERS DE GERAÇÃO DE IDS
--     └─ trg_generate_client_id .............. [3a_customer_root_record] → Gera client_id
--     └─ trg_generate_service_id ............. [4a_customer_service_history] → Gera service_id
--
-- 2.3 TRIGGERS AUTOMÁTICOS (APLICADOS DINAMICAMENTE)
--     └─ trigger_update_timestamp ............ [TODAS COM updated_at] → Atualiza timestamp
--
-- 2.4 TRIGGERS DE MARCAÇÃO PRIMÁRIA
--     └─ trg_first_cell_phone_is_primary ..... [3b_cell_phone_linked_service_sheet] → Primeiro = primário
--     └─ trg_first_email_is_primary .......... [3e_email] → Primeiro = primário
--     └─ trg_first_landline_is_primary ....... [3f_landline_phone] → Primeiro = primário
--
-- 2.5 TRIGGERS DE AUTOMAÇÃO DE MENSAGENS
--     └─ trg_auto_populate_message ........... [2b_conversation_messages] → Popula campos automáticos
-- =================================================================================================


-- -------------------------------------------------------------------------------------------------
-- 2.1 TRIGGERS DE SINCRONIZAÇÃO
-- -------------------------------------------------------------------------------------------------

-- ╔═════════════════════════════════════════════════════════════════════════════════════════════╗
-- ║ TRIGGER: trig_sync_owner_to_cell                                                            ║
-- ╠═════════════════════════════════════════════════════════════════════════════════════════════╣
-- ║ TABELA ALVO: 3a_customer_root_record                                                        ║
-- ║ EVENTO: AFTER INSERT OR UPDATE                                                              ║
-- ║ FUNÇÃO: func_sync_owner_to_cell_sheet()                                                     ║
-- ║                                                                                             ║
-- ║ COMPORTAMENTO:                                                                              ║
-- ║   Quando um registro é criado/atualizado em 3a_customer_root_record:                        ║
-- ║   → Busca o wallet_id correspondente ao whatsapp_owner                                      ║
-- ║   → Cria/atualiza registro na 3b_cell_phone_linked_service_sheet                            ║
-- ║   → Define o telefone como primário, verificado e WhatsApp                                  ║
-- ╚═════════════════════════════════════════════════════════════════════════════════════════════╝
DROP TRIGGER IF EXISTS trig_sync_owner_to_cell ON "3a_customer_root_record";

CREATE TRIGGER trig_sync_owner_to_cell
    AFTER INSERT OR UPDATE ON "3a_customer_root_record"
    FOR EACH ROW
    EXECUTE FUNCTION func_sync_owner_to_cell_sheet();


-- -------------------------------------------------------------------------------------------------
-- 2.2 TRIGGERS DE GERAÇÃO DE IDS
-- -------------------------------------------------------------------------------------------------

-- ╔═════════════════════════════════════════════════════════════════════════════════════════════╗
-- ║ TRIGGER: trg_generate_client_id                                                             ║
-- ╠═════════════════════════════════════════════════════════════════════════════════════════════╣
-- ║ TABELA ALVO: 3a_customer_root_record                                                        ║
-- ║ EVENTO: BEFORE INSERT                                                                       ║
-- ║ FUNÇÃO: func_generate_friendly_client_id()                                                  ║
-- ║                                                                                             ║
-- ║ COMPORTAMENTO:                                                                              ║
-- ║   Antes de inserir um novo cliente:                                                         ║
-- ║   → Incrementa o contador client_count da inbox                                             ║
-- ║   → Atribui client_id = "CT" + número (ex: CT1, CT2, CT3...)                                ║
-- ╚═════════════════════════════════════════════════════════════════════════════════════════════╝
DROP TRIGGER IF EXISTS trg_generate_client_id ON "3a_customer_root_record";

CREATE TRIGGER trg_generate_client_id
    BEFORE INSERT ON "3a_customer_root_record"
    FOR EACH ROW
    EXECUTE FUNCTION func_generate_friendly_client_id();


-- ╔═════════════════════════════════════════════════════════════════════════════════════════════╗
-- ║ TRIGGER: trg_generate_service_id                                                            ║
-- ╠═════════════════════════════════════════════════════════════════════════════════════════════╣
-- ║ TABELA ALVO: 4a_customer_service_history                                                    ║
-- ║ EVENTO: BEFORE INSERT                                                                       ║
-- ║ FUNÇÃO: func_generate_friendly_service_id()                                                 ║
-- ║                                                                                             ║
-- ║ COMPORTAMENTO:                                                                              ║
-- ║   Antes de inserir um novo atendimento:                                                     ║
-- ║   → Incrementa o contador atendimento_count da inbox                                        ║
-- ║   → Atribui service_id = "AT" + número (ex: AT1, AT2, AT3...)                               ║
-- ╚═════════════════════════════════════════════════════════════════════════════════════════════╝
DROP TRIGGER IF EXISTS trg_generate_service_id ON "4a_customer_service_history";

CREATE TRIGGER trg_generate_service_id
    BEFORE INSERT ON "4a_customer_service_history"
    FOR EACH ROW
    EXECUTE FUNCTION func_generate_friendly_service_id();


-- -------------------------------------------------------------------------------------------------
-- 2.3 TRIGGERS AUTOMÁTICOS (APLICAÇÃO DINÂMICA)
-- -------------------------------------------------------------------------------------------------

-- ╔═════════════════════════════════════════════════════════════════════════════════════════════╗
-- ║ TRIGGER: trigger_update_timestamp (APLICADO DINAMICAMENTE)                                  ║
-- ╠═════════════════════════════════════════════════════════════════════════════════════════════╣
-- ║ TABELAS ALVO: Todas que possuem coluna 'updated_at'                                         ║
-- ║ EVENTO: BEFORE UPDATE                                                                       ║
-- ║ FUNÇÃO: update_updated_at_column()                                                          ║
-- ║                                                                                             ║
-- ║ COMPORTAMENTO:                                                                              ║
-- ║   O bloco abaixo descobre automaticamente todas as tabelas do schema 'public'               ║
-- ║   que possuem a coluna 'updated_at' e aplica o trigger em cada uma delas.                   ║
-- ║                                                                                             ║
-- ║ AÇÃO:                                                                                       ║
-- ║   → A cada UPDATE, define updated_at = NOW() automaticamente                                ║
-- ║                                                                                             ║
-- ║ TABELAS AFETADAS (descobertas dinamicamente):                                               ║
-- ║   • 0a_inbox_whatsapp                                                                       ║
-- ║   • 1a_whatsapp_user_contact                                                                ║
-- ║   • 3a_customer_root_record                                                                 ║
-- ║   • 3b_cell_phone_linked_service_sheet                                                      ║
-- ║   • 4a_customer_service_history                                                             ║
-- ║   • ... (e todas as outras com updated_at)                                                  ║
-- ╚═════════════════════════════════════════════════════════════════════════════════════════════╝
DO $
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


-- -------------------------------------------------------------------------------------------------
-- 2.4 TRIGGERS DE MARCAÇÃO PRIMÁRIA
-- -------------------------------------------------------------------------------------------------

-- ╔═════════════════════════════════════════════════════════════════════════════════════════════╗
-- ║ TRIGGER: trg_first_cell_phone_is_primary                                                    ║
-- ╠═════════════════════════════════════════════════════════════════════════════════════════════╣
-- ║ TABELA ALVO: 3b_cell_phone_linked_service_sheet                                             ║
-- ║ EVENTO: BEFORE INSERT                                                                       ║
-- ║ FUNÇÃO: func_ensure_first_is_primary()                                                      ║
-- ║                                                                                             ║
-- ║ COMPORTAMENTO:                                                                              ║
-- ║   O primeiro telefone celular adicionado a uma ficha é automaticamente marcado como         ║
-- ║   primário (is_primary = TRUE). Telefones adicionais ficam como FALSE por padrão.           ║
-- ╚═════════════════════════════════════════════════════════════════════════════════════════════╝
DROP TRIGGER IF EXISTS trg_first_cell_phone_is_primary ON "3b_cell_phone_linked_service_sheet";

CREATE TRIGGER trg_first_cell_phone_is_primary
    BEFORE INSERT ON "3b_cell_phone_linked_service_sheet"
    FOR EACH ROW
    EXECUTE FUNCTION func_ensure_first_is_primary();


-- ╔═════════════════════════════════════════════════════════════════════════════════════════════╗
-- ║ TRIGGER: trg_first_email_is_primary                                                         ║
-- ╠═════════════════════════════════════════════════════════════════════════════════════════════╣
-- ║ TABELA ALVO: 3e_email                                                                       ║
-- ║ EVENTO: BEFORE INSERT                                                                       ║
-- ║ FUNÇÃO: func_ensure_first_is_primary()                                                      ║
-- ║                                                                                             ║
-- ║ COMPORTAMENTO:                                                                              ║
-- ║   O primeiro e-mail adicionado a uma ficha é automaticamente marcado como primário          ║
-- ║   (is_primary = TRUE). E-mails adicionais ficam como FALSE por padrão.                      ║
-- ╚═════════════════════════════════════════════════════════════════════════════════════════════╝
DROP TRIGGER IF EXISTS trg_first_email_is_primary ON "3e_email";

CREATE TRIGGER trg_first_email_is_primary
    BEFORE INSERT ON "3e_email"
    FOR EACH ROW
    EXECUTE FUNCTION func_ensure_first_is_primary();


-- ╔═════════════════════════════════════════════════════════════════════════════════════════════╗
-- ║ TRIGGER: trg_first_landline_is_primary                                                      ║
-- ╠═════════════════════════════════════════════════════════════════════════════════════════════╣
-- ║ TABELA ALVO: 3f_landline_phone                                                              ║
-- ║ EVENTO: BEFORE INSERT                                                                       ║
-- ║ FUNÇÃO: func_ensure_first_is_primary()                                                      ║
-- ║                                                                                             ║
-- ║ COMPORTAMENTO:                                                                              ║
-- ║   O primeiro telefone fixo adicionado a uma ficha é automaticamente marcado como primário   ║
-- ║   (is_primary = TRUE). Telefones fixos adicionais ficam como FALSE por padrão.              ║
-- ╚═════════════════════════════════════════════════════════════════════════════════════════════╝
DROP TRIGGER IF EXISTS trg_first_landline_is_primary ON "3f_landline_phone";

CREATE TRIGGER trg_first_landline_is_primary
    BEFORE INSERT ON "3f_landline_phone"
    FOR EACH ROW
    EXECUTE FUNCTION func_ensure_first_is_primary();


-- -------------------------------------------------------------------------------------------------
-- 2.5 TRIGGERS DE AUTOMAÇÃO DE MENSAGENS
-- -------------------------------------------------------------------------------------------------

-- ╔═════════════════════════════════════════════════════════════════════════════════════════════╗
-- ║ TRIGGER: trg_auto_populate_message                                                          ║
-- ╠═════════════════════════════════════════════════════════════════════════════════════════════╣
-- ║ TABELA ALVO: 2b_conversation_messages                                                       ║
-- ║ EVENTO: BEFORE INSERT OR UPDATE                                                             ║
-- ║ FUNÇÃO: func_auto_populate_message_fields()                                                 ║
-- ║                                                                                             ║
-- ║ COMPORTAMENTO:                                                                              ║
-- ║   Antes de inserir ou atualizar uma mensagem:                                               ║
-- ║   → Se sender_type é interno (ai_agent, human_agent, system) E source_message_id vazio      ║
-- ║     • Gera ULID automaticamente para rastreamento                                           ║
-- ║   → Se message_content não é vazio                                                          ║
-- ║     • Converte para tsvector português para busca full-text otimizada                       ║
-- ║                                                                                             ║
-- ║ EXEMPLOS:                                                                                   ║
-- ║   INSERT sender_type='contact', source_message_id='wamid.xyz'                               ║
-- ║   → Mantém o ID externo do WhatsApp                                                         ║
-- ║                                                                                             ║
-- ║   INSERT sender_type='ai_agent', source_message_id=NULL                                     ║
-- ║   → Gera: '01HW5Z8K7F9G2M3N4P5Q6R7S8T' (ULID)                                               ║
-- ║                                                                                             ║
-- ║   INSERT message_content='Olá, como posso ajudar?'                                          ║
-- ║   → Cria tsvector: 'ajud':5 'olá':1 'pod':3                                                 ║
-- ╚═════════════════════════════════════════════════════════════════════════════════════════════╝
DROP TRIGGER IF EXISTS trg_auto_populate_message ON "2b_conversation_messages";

CREATE TRIGGER trg_auto_populate_message
    BEFORE INSERT OR UPDATE ON "2b_conversation_messages"
    FOR EACH ROW
    EXECUTE FUNCTION func_auto_populate_message_fields();


