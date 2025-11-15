# AGES - Documentação do Banco de Dados

Documentação completa dos objetos do banco de dados PostgreSQL/Supabase do sistema AGES (WhatsApp Customer Management).

---

## Sumário

- [Enums](#enums)
- [Tabelas](#tabelas)
- [Funções](#funções)
- [Triggers](#triggers)
- [Views](#views)
- [Estatísticas](#estatísticas)

---

## Enums

| Nome | Propósito | Valores |
|------|-----------|---------|
| `workflow_status` | Status do workflow com indicadores visuais | `'⚪'` Inativo, `'⚫'` Bloqueado, `'🧪'` Teste, `'🟢'` Ativo, `'🟡'` Atenção, `'🔴'` Erro, `'🚫'` Suspenso |
| `message_sender_type` | Identifica origem das mensagens | `'contact'`, `'ai_agent'`, `'human_agent'`, `'system'` |

**Arquivo:** `schema.sql:17-42`

---

## Tabelas

### Nível 0 - Gestão do Inbox

| Tabela | Propósito |
|--------|-----------|
| `0a_inbox_whatsapp` | Tabela raiz do inbox WhatsApp com config do provedor, agente IA, créditos e formulário obrigatório |
| `0b_inbox_counters` | Contadores em tempo real (contatos, formulários, agendamentos) com taxas de conversão auto-calculadas |

### Nível 1 - Contatos WhatsApp

| Tabela | Propósito |
|--------|-----------|
| `1a_whatsapp_user_contact` | Registros de contatos WhatsApp com métricas de engajamento, device info, tags e memória IA |

### Nível 2 - Mensagens

| Tabela | Propósito |
|--------|-----------|
| `2a_temporary_messages` | Armazenamento temporário de mensagens antes do processamento |
| `2b_conversation_messages` | Histórico completo de mensagens com busca full-text (GIN index) |

### Nível 3 - Perfil do Cliente

| Tabela | Relação | Propósito |
|--------|---------|-----------|
| `3a_customer_root_record` | Principal | Registro mestre do cliente com LTV tracking (total gasto, agendamentos concluídos) |
| `3b_cell_phone_linked_service_sheet` | 1:N | Múltiplos celulares vinculados ao cliente |
| `3c_gender` | 1:1 | Gênero do cliente |
| `3d_birth_date` | 1:1 | Data de nascimento |
| `3e_email` | 1:N | Múltiplos emails do cliente |
| `3f_landline_phone` | 1:N | Telefones fixos |
| `3g_cpf` | 1:1 | CPF (único por inbox) |
| `3h_rg` | 1:1 | RG com órgão emissor |
| `3i_endereco_br` | 1:N | Endereços brasileiros (residencial/comercial) |
| `3j_veiculos_br` | 1:N | Veículos do cliente (placa, RENAVAM, chassi, etc.) |
| `3k_social_media` | 1:N | Redes sociais com verificação de confiabilidade |

### Nível 4 - Histórico de Serviços

| Tabela | Propósito |
|--------|-----------|
| `4a_customer_service_history` | Histórico de agendamentos com status, valores financeiros e timestamps automáticos |

**Arquivo:** `schema.sql:47-507`

---

## Funções

### Gestão de Dados Core

| Função | Retorno | Propósito |
|--------|---------|-----------|
| `func_upsert_contact_from_webhook()` | void | Upsert atômico de inbox e contato via webhook (idempotente) |
| `func_sync_owner_to_cell_sheet()` | TRIGGER | Sincroniza whatsapp_owner para tabela de celulares como primário |
| `func_generate_friendly_client_id()` | TRIGGER | Gera IDs amigáveis: CT1, CT2, CT3... |
| `func_generate_friendly_service_id()` | TRIGGER | Gera IDs amigáveis: AT1, AT2, AT3... |
| `func_ensure_first_is_primary()` | TRIGGER | Marca primeiro item inserido como primário automaticamente |
| `func_generate_ulid()` | TEXT | Gera ULID para mensagens internas |
| `func_auto_populate_message_fields()` | TRIGGER | Auto-popula ULID e vetor de busca full-text |
| `update_updated_at_column()` | TRIGGER | Atualiza timestamp updated_at automaticamente |
| `func_check_complete_form()` | BOOLEAN | Verifica se formulário está completo conforme config do inbox |
| `func_update_form_counter()` | TRIGGER | Atualiza contadores de formulário quando dados mudam |
| `func_set_status_timestamp()` | TRIGGER | Auto-popula timestamps de status (confirmed_at, completed_at, etc.) |
| `func_update_appointment_status_counter()` | TRIGGER | Atualiza contadores de status de agendamento |

**Arquivo:** `functions.SQL`

### Billing & LTV (Lifetime Value)

| Função | Retorno | Propósito |
|--------|---------|-----------|
| `get_billing_by_period(inbox_id, start, end)` | JSONB | Faturamento total e métricas por período |
| `get_billing_today(inbox_id)` | JSONB | Faturamento do dia atual |
| `get_billing_last_n_days(inbox_id, days)` | JSONB | Faturamento dos últimos N dias |
| `get_billing_specific_month(inbox_id, year, month)` | JSONB | Faturamento de um mês específico |
| `get_customer_ltv(root_id)` | JSONB | Calcula LTV de um cliente específico |
| `get_top_customers_by_ltv(inbox_id, limit)` | JSONB | Top N clientes por LTV (maior para menor) |
| `update_customer_ltv()` | TRIGGER | Auto-atualiza LTV quando agendamento é concluído |
| `recalculate_customer_ltv(root_id)` | JSONB | Recalcula LTV de um cliente manualmente |
| `recalculate_all_ltv_for_inbox(inbox_id)` | JSONB | Recalcula LTV de todos os clientes de um inbox |

**Arquivo:** `functions_billing_metrics.sql` e `trigger_update_customer_ltv.sql`

### Contadores de Agendamentos

| Função | Retorno | Propósito |
|--------|---------|-----------|
| `func_get_appointment_counters_by_period(inbox_id, start, end)` | JSONB | Contagem de agendamentos por status em um período |
| `func_get_counters_last_n_days(inbox_id, days)` | JSONB | Contadores dos últimos N dias |
| `func_get_counters_specific_month(inbox_id, year, month)` | JSONB | Contadores de um mês específico |
| `func_count_status_changes(inbox_id, status, start, end)` | INTEGER | Conta mudanças para um status específico |

**Arquivo:** `functions_time_based_counters.sql`

---

## Triggers

### Sincronização & IDs Automáticos

| Trigger | Tabela | Evento | Propósito |
|---------|--------|--------|-----------|
| `trig_sync_owner_to_cell` | 3a_customer_root_record | AFTER INSERT/UPDATE | Sincroniza whatsapp_owner para celular primário |
| `trg_generate_client_id` | 3a_customer_root_record | BEFORE INSERT | Gera CT+número e incrementa contador |
| `trg_generate_service_id` | 4a_customer_service_history | BEFORE INSERT | Gera AT+número automaticamente |

### Timestamps Automáticos

| Trigger | Tabela | Evento | Propósito |
|---------|--------|--------|-----------|
| `trigger_update_timestamp` | Todas com updated_at | BEFORE UPDATE | Auto-atualiza updated_at em todas as modificações |

### Marcação de Primário

| Trigger | Tabela | Evento | Propósito |
|---------|--------|--------|-----------|
| `trg_first_cell_phone_is_primary` | 3b_cell_phone_linked_service_sheet | BEFORE INSERT | Primeiro celular é primário automaticamente |
| `trg_first_email_is_primary` | 3e_email | BEFORE INSERT | Primeiro email é primário automaticamente |
| `trg_first_landline_is_primary` | 3f_landline_phone | BEFORE INSERT | Primeiro fixo é primário automaticamente |

### Mensagens

| Trigger | Tabela | Evento | Propósito |
|---------|--------|--------|-----------|
| `trg_auto_populate_message` | 2b_conversation_messages | BEFORE INSERT/UPDATE | Gera ULID e vetor de busca full-text |

### Validação de Formulário

| Trigger | Tabela | Evento | Propósito |
|---------|--------|--------|-----------|
| `trg_check_form_complete_3a` | 3a_customer_root_record | AFTER INSERT/UPDATE | Monitora completude do formulário |
| `trg_check_form_complete_3b` | 3b_cell_phone_linked_service_sheet | AFTER INSERT/UPDATE | Monitora completude do formulário |
| `trg_check_form_complete_3c` | 3c_gender | AFTER INSERT/UPDATE | Monitora completude do formulário |
| `trg_check_form_complete_3d` | 3d_birth_date | AFTER INSERT/UPDATE | Monitora completude do formulário |
| `trg_check_form_complete_3e` | 3e_email | AFTER INSERT/UPDATE | Monitora completude do formulário |
| `trg_check_form_complete_3f` | 3f_landline_phone | AFTER INSERT/UPDATE | Monitora completude do formulário |
| `trg_check_form_complete_3g` | 3g_cpf | AFTER INSERT/UPDATE | Monitora completude do formulário |
| `trg_check_form_complete_3h` | 3h_rg | AFTER INSERT/UPDATE | Monitora completude do formulário |
| `trg_check_form_complete_3i` | 3i_endereco_br | AFTER INSERT/UPDATE | Monitora completude do formulário |

### Agendamentos

| Trigger | Tabela | Evento | Propósito |
|---------|--------|--------|-----------|
| `trg_set_status_timestamp` | 4a_customer_service_history | BEFORE INSERT/UPDATE | Auto-popula timestamps de status |
| `trg_update_appointment_status_counter` | 4a_customer_service_history | AFTER INSERT/UPDATE | Atualiza contadores de status no inbox |
| `trigger_update_customer_ltv` | 4a_customer_service_history | AFTER INSERT/UPDATE | Atualiza LTV quando agendamento é concluído |

**Arquivos:** `triggers.SQL` e `trigger_update_customer_ltv.sql`

---

## Views

| View | Propósito | Campos Principais |
|------|-----------|-------------------|
| `vw_customer_billing_summary` | Resumo consolidado de faturamento por cliente ordenado por LTV | root_id, client_id, treatment_name, total_spent, average_ticket, lifetime_days |
| `vw_appointment_status_timeline` | Timeline de status de agendamentos com todos os timestamps | service_id, service_status, scheduled_at, confirmed_at, completed_at, etc. |

**Arquivos:** `functions_billing_metrics.sql:398` e `functions_time_based_counters.sql:279`

---

## Estatísticas

| Categoria | Quantidade |
|-----------|------------|
| **Enums** | 2 |
| **Tabelas** | 17 |
| **Funções** | 25+ |
| **Triggers** | 20 |
| **Views** | 2 |
| **Total de Objetos** | **66+** |

---

## Arquitetura

### Padrão Hierárquico
```
Nível 0: Inbox (configuração)
    ↓
Nível 1: Contatos WhatsApp
    ↓
Nível 2: Mensagens
    ↓
Nível 3: Perfil do Cliente (dados normalizados em múltiplas tabelas)
    ↓
Nível 4: Histórico de Serviços/Agendamentos
```

### Automações Principais
- **Timestamps automáticos** - updated_at em todas as tabelas
- **IDs amigáveis** - CT (clientes) e AT (agendamentos)
- **Primário automático** - Primeiro item marcado como principal
- **Full-text search** - Busca em português para mensagens
- **LTV tracking** - Valor vitalício calculado automaticamente
- **Form validation** - Completude de formulário monitorada em tempo real
- **Contadores de status** - Métricas atualizadas automaticamente
