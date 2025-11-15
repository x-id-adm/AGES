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
--
-- 2.6 TRIGGERS DE VALIDAÇÃO DE FORMULÁRIO COMPLETO
--     └─ trg_check_form_complete_3a .......... [3a_customer_root_record] → Valida completude
--     └─ trg_check_form_complete_3b .......... [3b_cell_phone_linked_service_sheet] → Valida completude
--     └─ trg_check_form_complete_3c .......... [3c_gender] → Valida completude
--     └─ trg_check_form_complete_3d .......... [3d_birth_date] → Valida completude
--     └─ trg_check_form_complete_3e .......... [3e_email] → Valida completude
--     └─ trg_check_form_complete_3f .......... [3f_landline_phone] → Valida completude
--     └─ trg_check_form_complete_3g .......... [3g_cpf] → Valida completude
--     └─ trg_check_form_complete_3h .......... [3h_rg] → Valida completude
--     └─ trg_check_form_complete_3i .......... [3i_endereco_br] → Valida completude
--
-- 2.7 TRIGGERS DE CONTADORES DE STATUS DE ATENDIMENTOS
--     └─ trg_update_appointment_status_counter [4a_customer_service_history] → Atualiza contadores de status
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


-- -------------------------------------------------------------------------------------------------
-- 2.6 TRIGGERS DE VALIDAÇÃO DE FORMULÁRIO COMPLETO
-- -------------------------------------------------------------------------------------------------

-- ╔═════════════════════════════════════════════════════════════════════════════════════════════╗
-- ║ TRIGGERS: trg_check_form_complete_*                                                         ║
-- ╠═════════════════════════════════════════════════════════════════════════════════════════════╣
-- ║ TABELAS ALVO: Todas as tabelas do NÍVEL 3 (3a até 3i)                                      ║
-- ║ EVENTO: AFTER INSERT OR UPDATE                                                              ║
-- ║ FUNÇÃO: func_update_form_counter()                                                          ║
-- ║                                                                                             ║
-- ║ PROPÓSITO:                                                                                  ║
-- ║   Monitora mudanças em qualquer campo da ficha de cliente e automaticamente:                ║
-- ║   1. Verifica se a ficha está completa baseado em required_data_form da inbox               ║
-- ║   2. Atualiza o campo is_form_complete na tabela 3a_customer_root_record                    ║
-- ║   3. Incrementa/decrementa o contador form_count em 0b_inbox_counters                       ║
-- ║                                                                                             ║
-- ║ COMPORTAMENTO:                                                                              ║
-- ║   Quando qualquer dado da ficha é inserido ou atualizado:                                   ║
-- ║   → Trigger dispara APÓS a operação (garantindo dados consistentes)                         ║
-- ║   → Função verifica completude baseada nas regras JSON da inbox                             ║
-- ║   → Se mudou de estado (incompleto→completo ou vice-versa), atualiza contador               ║
-- ║                                                                                             ║
-- ║ EXEMPLO DE FLUXO:                                                                           ║
-- ║   1. Inbox configurada com: {"treatment_name": {"required": true}, "cpf": {"required": true}}│
-- ║   2. INSERT em 3a_customer_root_record com treatment_name                                   ║
-- ║      → Trigger dispara → Ficha incompleta (falta CPF) → form_count não muda                 ║
-- ║   3. INSERT em 3g_cpf com CPF do cliente                                                    ║
-- ║      → Trigger dispara → Ficha completa! → form_count += 1 🎉                                ║
-- ║                                                                                             ║
-- ║ TABELAS MONITORADAS:                                                                        ║
-- ║   • 3a_customer_root_record ......... Campos: treatment_name, legal_name_complete, etc.     ║
-- ║   • 3b_cell_phone_linked_service .... Campo: cell_phone                                     ║
-- ║   • 3c_gender ....................... Campo: gender                                         ║
-- ║   • 3d_birth_date ................... Campo: birth_date                                     ║
-- ║   • 3e_email ........................ Campo: email                                          ║
-- ║   • 3f_landline_phone ............... Campo: phone_number                                   ║
-- ║   • 3g_cpf .......................... Campo: cpf                                            ║
-- ║   • 3h_rg ........................... Campo: rg_numero                                      ║
-- ║   • 3i_endereco_br .................. Campos: logradouro, cidade                            ║
-- ╚═════════════════════════════════════════════════════════════════════════════════════════════╝

-- Tabela 3a: Raiz da ficha
DROP TRIGGER IF EXISTS trg_check_form_complete_3a ON "3a_customer_root_record";

CREATE TRIGGER trg_check_form_complete_3a
    AFTER INSERT OR UPDATE ON "3a_customer_root_record"
    FOR EACH ROW
    EXECUTE FUNCTION func_update_form_counter();


-- Tabela 3b: Telefones celulares
DROP TRIGGER IF EXISTS trg_check_form_complete_3b ON "3b_cell_phone_linked_service_sheet";

CREATE TRIGGER trg_check_form_complete_3b
    AFTER INSERT OR UPDATE ON "3b_cell_phone_linked_service_sheet"
    FOR EACH ROW
    EXECUTE FUNCTION func_update_form_counter();


-- Tabela 3c: Gênero
DROP TRIGGER IF EXISTS trg_check_form_complete_3c ON "3c_gender";

CREATE TRIGGER trg_check_form_complete_3c
    AFTER INSERT OR UPDATE ON "3c_gender"
    FOR EACH ROW
    EXECUTE FUNCTION func_update_form_counter();


-- Tabela 3d: Data de nascimento
DROP TRIGGER IF EXISTS trg_check_form_complete_3d ON "3d_birth_date";

CREATE TRIGGER trg_check_form_complete_3d
    AFTER INSERT OR UPDATE ON "3d_birth_date"
    FOR EACH ROW
    EXECUTE FUNCTION func_update_form_counter();


-- Tabela 3e: E-mails
DROP TRIGGER IF EXISTS trg_check_form_complete_3e ON "3e_email";

CREATE TRIGGER trg_check_form_complete_3e
    AFTER INSERT OR UPDATE ON "3e_email"
    FOR EACH ROW
    EXECUTE FUNCTION func_update_form_counter();


-- Tabela 3f: Telefones fixos
DROP TRIGGER IF EXISTS trg_check_form_complete_3f ON "3f_landline_phone";

CREATE TRIGGER trg_check_form_complete_3f
    AFTER INSERT OR UPDATE ON "3f_landline_phone"
    FOR EACH ROW
    EXECUTE FUNCTION func_update_form_counter();


-- Tabela 3g: CPF
DROP TRIGGER IF EXISTS trg_check_form_complete_3g ON "3g_cpf";

CREATE TRIGGER trg_check_form_complete_3g
    AFTER INSERT OR UPDATE ON "3g_cpf"
    FOR EACH ROW
    EXECUTE FUNCTION func_update_form_counter();


-- Tabela 3h: RG
DROP TRIGGER IF EXISTS trg_check_form_complete_3h ON "3h_rg";

CREATE TRIGGER trg_check_form_complete_3h
    AFTER INSERT OR UPDATE ON "3h_rg"
    FOR EACH ROW
    EXECUTE FUNCTION func_update_form_counter();


-- Tabela 3i: Endereço
DROP TRIGGER IF EXISTS trg_check_form_complete_3i ON "3i_endereco_br";

CREATE TRIGGER trg_check_form_complete_3i
    AFTER INSERT OR UPDATE ON "3i_endereco_br"
    FOR EACH ROW
    EXECUTE FUNCTION func_update_form_counter();


-- -------------------------------------------------------------------------------------------------
-- 2.7 TRIGGERS DE CONTADORES DE STATUS DE ATENDIMENTOS
-- -------------------------------------------------------------------------------------------------

-- ╔═════════════════════════════════════════════════════════════════════════════════════════════╗
-- ║ TRIGGER: trg_set_status_timestamp                                                           ║
-- ╠═════════════════════════════════════════════════════════════════════════════════════════════╣
-- ║ TABELA ALVO: 4a_customer_service_history                                                    ║
-- ║ EVENTO: BEFORE INSERT OR UPDATE                                                             ║
-- ║ FUNÇÃO: func_set_status_timestamp()                                                         ║
-- ║                                                                                             ║
-- ║ PROPÓSITO:                                                                                  ║
-- ║   Preenche automaticamente os campos de timestamp (scheduled_at, confirmed_at, etc.)        ║
-- ║   quando um agendamento é criado ou tem seu status alterado.                                ║
-- ║                                                                                             ║
-- ║ COMPORTAMENTO:                                                                              ║
-- ║   • INSERT: Define o timestamp do status inicial                                            ║
-- ║   • UPDATE: Define o timestamp do novo status (preserva os anteriores)                      ║
-- ║                                                                                             ║
-- ║ OBSERVAÇÃO:                                                                                 ║
-- ║   Este trigger executa ANTES (BEFORE) para modificar o registro antes de salvar.            ║
-- ║   Deve vir antes do trigger de contadores (que executa AFTER).                              ║
-- ╚═════════════════════════════════════════════════════════════════════════════════════════════╝
DROP TRIGGER IF EXISTS trg_set_status_timestamp ON "4a_customer_service_history";

CREATE TRIGGER trg_set_status_timestamp
    BEFORE INSERT OR UPDATE ON "4a_customer_service_history"
    FOR EACH ROW
    EXECUTE FUNCTION func_set_status_timestamp();


-- ╔═════════════════════════════════════════════════════════════════════════════════════════════╗
-- ║ TRIGGER: trg_update_appointment_status_counter                                              ║
-- ╠═════════════════════════════════════════════════════════════════════════════════════════════╣
-- ║ TABELA ALVO: 4a_customer_service_history                                                    ║
-- ║ EVENTO: AFTER INSERT OR UPDATE                                                              ║
-- ║ FUNÇÃO: func_update_appointment_status_counter()                                            ║
-- ║                                                                                             ║
-- ║ PROPÓSITO:                                                                                  ║
-- ║   Monitora mudanças na tabela de atendimentos e automaticamente atualiza os contadores      ║
-- ║   de status em 0b_inbox_counters quando:                                                    ║
-- ║   • Um novo atendimento é criado (INSERT)                                                   ║
-- ║   • O status de um atendimento é alterado (UPDATE)                                          ║
-- ║                                                                                             ║
-- ║ COMPORTAMENTO:                                                                              ║
-- ║   INSERT:                                                                                   ║
-- ║   → Incrementa contador do status do novo atendimento                                       ║
-- ║                                                                                             ║
-- ║   UPDATE (quando service_status muda):                                                      ║
-- ║   → Decrementa contador do status antigo                                                    ║
-- ║   → Incrementa contador do novo status                                                      ║
-- ║                                                                                             ║
-- ║ CONTADORES ATUALIZADOS:                                                                     ║
-- ║   • scheduled_count ..... Atendimentos com status 'Scheduled'                               ║
-- ║   • confirmed_count ..... Atendimentos com status 'Confirmed'                               ║
-- ║   • completed_count ..... Atendimentos com status 'Completed'                               ║
-- ║   • cancelled_count ..... Atendimentos com status 'Cancelled'                               ║
-- ║   • rescheduled_count ... Atendimentos com status 'Rescheduled'                             ║
-- ║   • no_show_count ....... Atendimentos com status 'No_Show'                                 ║
-- ║                                                                                             ║
-- ║ EXEMPLO DE FLUXO:                                                                           ║
-- ║   1. INSERT atendimento com status 'Scheduled'                                              ║
-- ║      → scheduled_count: 0 → 1                                                               ║
-- ║                                                                                             ║
-- ║   2. UPDATE status: 'Scheduled' → 'Confirmed'                                               ║
-- ║      → scheduled_count: 1 → 0                                                               ║
-- ║      → confirmed_count: 0 → 1                                                               ║
-- ║                                                                                             ║
-- ║   3. UPDATE status: 'Confirmed' → 'Completed'                                               ║
-- ║      → confirmed_count: 1 → 0                                                               ║
-- ║      → completed_count: 0 → 1                                                               ║
-- ╚═════════════════════════════════════════════════════════════════════════════════════════════╝
DROP TRIGGER IF EXISTS trg_update_appointment_status_counter ON "4a_customer_service_history";

CREATE TRIGGER trg_update_appointment_status_counter
    AFTER INSERT OR UPDATE ON "4a_customer_service_history"
    FOR EACH ROW
    EXECUTE FUNCTION func_update_appointment_status_counter();


