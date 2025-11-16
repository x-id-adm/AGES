# Catálogo de Mini-Apps do Banco de Dados AGES

> **Conceito:** Cada par função/gatilho (ou função isolada) funciona como um "mini-app" dentro do banco de dados PostgreSQL. Este documento cataloga todos os mini-apps, suas categorias e dependências.

---

## Índice de Categorias

| Categoria | Nome | Qtd Mini-Apps | Descrição |
|-----------|------|---------------|-----------|
| [0*](#0---gateway-ponto-de-entrada) | **GATEWAY (Ponto de Entrada)** | 1 | Função crítica que alimenta todo o sistema |
| [1*](#1---infraestrutura-do-banco) | **INFRAESTRUTURA DO BANCO** | 2 | Funcionalidades básicas de suporte |
| [2*](#2---automações-de-gatilhos) | **AUTOMAÇÕES DE GATILHOS** | 9 | Mini-apps executados automaticamente por eventos |
| [3*](#3---funções-de-consultarelatório) | **FUNÇÕES DE CONSULTA/RELATÓRIO** | 10 | Mini-apps chamados pela aplicação para buscar dados |
| [4*](#4---funções-administrativas) | **FUNÇÕES ADMINISTRATIVAS** | 2 | Mini-apps para manutenção e recálculo manual |
| **TOTAL** | | **24** | |

---

## Estatísticas Gerais

- **Total de Funções PostgreSQL:** 25
- **Total de Gatilhos PostgreSQL:** 20
- **Total de Mini-Apps:** 24
- **Arquivos SQL Fonte:** 11

---

## 0* - GATEWAY (Ponto de Entrada)

> **CRÍTICO:** Esta é a porta de entrada de dados no sistema. Sem ela funcionando, todos os outros mini-apps perdem utilidade.

### 0.1 Cria ou atualiza inbox e contato via webhook

**Propósito:** Sincroniza dados externos do webhook (PING service) com o banco local. Cria ou atualiza registros de inbox e contato de forma atômica.

**Arquivos:**
```
├─ FN_func_upsert_contact_from_webhook.sql
└─ README.md
```

**Detalhes Técnicos:**
- **Função:** `func_upsert_contact_from_webhook()`
- **Gatilho:** Não (chamada diretamente pela aplicação)
- **Tabelas Modificadas:**
  - `0a_inbox_whatsapp` (UPSERT)
  - `1a_whatsapp_user_contact` (UPSERT)
- **Tipo de Operação:** UPSERT atômico
- **Chamado por:** Código da aplicação (on webhook receipt)

**Importância:**
- Primeira função executada quando dados externos chegam
- Todos os gatilhos subsequentes dependem dos dados inseridos por ela
- Falha aqui = sistema não recebe dados novos

---

## 1* - INFRAESTRUTURA DO BANCO

> Funcionalidades básicas que suportam o funcionamento de todo o sistema.

### 1.1 Atualiza timestamp automaticamente

**Propósito:** Mantém o campo `updated_at` sempre atualizado em qualquer tabela que tenha essa coluna.

**Arquivos:**
```
├─ FN_update_updated_at_column.sql
├─ TR_trigger_update_timestamp.sql
└─ README.md
```

**Detalhes Técnicos:**
- **Função:** `update_updated_at_column()`
- **Gatilho:** `trigger_update_timestamp` (DINÂMICO)
- **Evento:** BEFORE UPDATE
- **Tabelas Afetadas:** Todas com coluna `updated_at` (10+ tabelas)
- **Comportamento:** Gatilho criado dinamicamente via `DO` block

**Tabelas com este gatilho:**
- `0a_inbox_whatsapp`
- `1a_whatsapp_user_contact`
- `2b_conversation_messages`
- `3a_customer_root_record`
- `3b_cell_phone_linked_service_sheet`
- `3c_gender`
- `3d_birth_date`
- `3e_email`
- `3f_landline_phone`
- `3g_cpf`
- `3h_rg`
- `3i_endereco_br`
- `4a_customer_service_history`

---

### 1.2 Gera ULID para mensagens

**Propósito:** Gera identificadores únicos lexicograficamente ordenáveis para rastreamento de mensagens.

**Arquivos:**
```
├─ FN_func_generate_ulid.sql
└─ README.md
```

**Detalhes Técnicos:**
- **Função:** `func_generate_ulid()`
- **Gatilho:** Não (chamada por outra função)
- **Chamado por:** `func_auto_populate_message_fields()` (mini-app 2.5)
- **Retorno:** STRING no formato ULID

---

## 2* - AUTOMAÇÕES DE GATILHOS

> Mini-apps que executam automaticamente quando eventos específicos ocorrem nas tabelas.

### 2.1 Sincroniza owner para celular

**Propósito:** Propaga o `whatsapp_owner` do registro do cliente para a tabela de celular, mantendo sincronização.

**Arquivos:**
```
├─ FN_func_sync_owner_to_cell_sheet.sql
├─ TR_trig_sync_owner_to_cell.sql
└─ README.md
```

**Detalhes Técnicos:**
- **Função:** `func_sync_owner_to_cell_sheet()`
- **Gatilho:** `trig_sync_owner_to_cell`
- **Tabela Monitorada:** `3a_customer_root_record`
- **Evento:** AFTER INSERT OR UPDATE
- **Tabela Modificada:** `3b_cell_phone_linked_service_sheet`

---

### 2.2 Gera ID amigavel cliente

**Propósito:** Gera automaticamente IDs amigáveis para clientes no formato CT1, CT2, CT3...

**Arquivos:**
```
├─ FN_func_generate_friendly_client_id.sql
├─ TR_trg_generate_client_id.sql
└─ README.md
```

**Detalhes Técnicos:**
- **Função:** `func_generate_friendly_client_id()`
- **Gatilho:** `trg_generate_client_id`
- **Tabela Monitorada:** `3a_customer_root_record`
- **Evento:** BEFORE INSERT
- **Tabela Modificada:** `0b_inbox_counters` (incrementa `client_count`)
- **Formato ID:** CT{N} (CT1, CT2, CT3...)

---

### 2.3 Gera ID amigavel atendimento

**Propósito:** Gera automaticamente IDs amigáveis para atendimentos no formato AT1, AT2, AT3...

**Arquivos:**
```
├─ FN_func_generate_friendly_service_id.sql
├─ TR_trg_generate_service_id.sql
└─ README.md
```

**Detalhes Técnicos:**
- **Função:** `func_generate_friendly_service_id()`
- **Gatilho:** `trg_generate_service_id`
- **Tabela Monitorada:** `4a_customer_service_history`
- **Evento:** BEFORE INSERT
- **Tabela Modificada:** `0b_inbox_counters` (incrementa `atendimento_count`)
- **Formato ID:** AT{N} (AT1, AT2, AT3...)

---

### 2.4 Marca primeiro registro como principal

**Propósito:** Automaticamente marca o primeiro registro (telefone, email, etc.) como principal quando inserido.

**Arquivos:**
```
├─ FN_func_ensure_first_is_primary.sql
├─ TR_trg_first_cell_phone_is_primary.sql
├─ TR_trg_first_email_is_primary.sql
├─ TR_trg_first_landline_is_primary.sql
└─ README.md
```

**Detalhes Técnicos:**
- **Função:** `func_ensure_first_is_primary()` (REUTILIZÁVEL)
- **Gatilhos:** 3 gatilhos usam a mesma função
  - `trg_first_cell_phone_is_primary` → `3b_cell_phone_linked_service_sheet`
  - `trg_first_email_is_primary` → `3e_email`
  - `trg_first_landline_is_primary` → `3f_landline_phone`
- **Evento:** BEFORE INSERT
- **Lógica:** Se não existir outro registro, define `is_primary = TRUE`

---

### 2.5 Popula campos mensagem automaticamente

**Propósito:** Auto-popula campos da mensagem (ULID, tsvector para busca) quando mensagem é criada/atualizada.

**Arquivos:**
```
├─ FN_func_auto_populate_message_fields.sql
├─ TR_trg_auto_populate_message.sql
└─ README.md
```

**Detalhes Técnicos:**
- **Função:** `func_auto_populate_message_fields()`
- **Gatilho:** `trg_auto_populate_message`
- **Tabela Monitorada:** `2b_conversation_messages`
- **Evento:** BEFORE INSERT OR UPDATE
- **Dependência:** Chama `func_generate_ulid()` (mini-app 1.2)
- **Funcionalidades:**
  - Gera ULID para mensagens internas (ai_agent, human_agent, system)
  - Cria tsvector para busca full-text em português

---

### 2.6 Valida completude formulario

**Propósito:** Verifica se o formulário do cliente está completo baseado nos requisitos JSON e atualiza contadores.

**Arquivos:**
```
├─ FN_func_check_complete_form.sql (auxiliar)
├─ FN_func_update_form_counter.sql (principal)
├─ TR_trg_check_form_complete_3a.sql
├─ TR_trg_check_form_complete_3b.sql
├─ TR_trg_check_form_complete_3c.sql
├─ TR_trg_check_form_complete_3d.sql
├─ TR_trg_check_form_complete_3e.sql
├─ TR_trg_check_form_complete_3f.sql
├─ TR_trg_check_form_complete_3g.sql
├─ TR_trg_check_form_complete_3h.sql
├─ TR_trg_check_form_complete_3i.sql
└─ README.md
```

**Detalhes Técnicos:**
- **Função Principal:** `func_update_form_counter()`
- **Função Auxiliar:** `func_check_complete_form()` (validação)
- **Gatilhos:** 9 gatilhos (um para cada tabela de dados do formulário)
  - `trg_check_form_complete_3a` → `3a_customer_root_record`
  - `trg_check_form_complete_3b` → `3b_cell_phone_linked_service_sheet`
  - `trg_check_form_complete_3c` → `3c_gender`
  - `trg_check_form_complete_3d` → `3d_birth_date`
  - `trg_check_form_complete_3e` → `3e_email`
  - `trg_check_form_complete_3f` → `3f_landline_phone`
  - `trg_check_form_complete_3g` → `3g_cpf`
  - `trg_check_form_complete_3h` → `3h_rg`
  - `trg_check_form_complete_3i` → `3i_endereco_br`
- **Evento:** AFTER INSERT OR UPDATE
- **Tabelas Modificadas:**
  - `3a_customer_root_record` (flag `is_form_complete`)
  - `0b_inbox_counters` (campo `form_count`)
- **Configuração:** Usa JSON `required_data_form` do inbox

---

### 2.7 Define timestamp por status

**Propósito:** Registra automaticamente o timestamp quando o status do atendimento muda (scheduled_at, confirmed_at, completed_at, etc.).

**Arquivos:**
```
├─ FN_func_set_status_timestamp.sql
├─ TR_trg_set_status_timestamp.sql
└─ README.md
```

**Detalhes Técnicos:**
- **Função:** `func_set_status_timestamp()`
- **Gatilho:** `trg_set_status_timestamp`
- **Tabela Monitorada:** `4a_customer_service_history`
- **Evento:** BEFORE INSERT OR UPDATE
- **Campos Atualizados:**
  - `scheduled_at` quando status = 'Scheduled'
  - `confirmed_at` quando status = 'Confirmed'
  - `completed_at` quando status = 'Completed'
  - `cancelled_at` quando status = 'Cancelled'
  - etc.

---

### 2.8 Atualiza contador status atendimento

**Propósito:** Mantém contadores de status de atendimento atualizados (quantos scheduled, confirmed, completed, etc.).

**Arquivos:**
```
├─ FN_func_update_appointment_status_counter.sql
├─ TR_trg_update_appointment_status_counter.sql
└─ README.md
```

**Detalhes Técnicos:**
- **Função:** `func_update_appointment_status_counter()`
- **Gatilho:** `trg_update_appointment_status_counter`
- **Tabela Monitorada:** `4a_customer_service_history`
- **Evento:** AFTER INSERT OR UPDATE
- **Tabela Modificada:** `0b_inbox_counters`
- **Campos Atualizados:**
  - `scheduled_count`
  - `confirmed_count`
  - `completed_count`
  - `cancelled_count`
  - `rescheduled_count`
  - `no_show_count`
- **Lógica:**
  - INSERT: incrementa contador do novo status
  - UPDATE (se mudou): decrementa antigo, incrementa novo

---

### 2.9 Atualiza LTV cliente automaticamente

**Propósito:** Atualiza automaticamente o Lifetime Value (LTV) do cliente quando um atendimento é concluído.

**Arquivos:**
```
├─ FN_update_customer_ltv.sql
├─ TR_trigger_update_customer_ltv.sql
└─ README.md
```

**Detalhes Técnicos:**
- **Função:** `update_customer_ltv()`
- **Gatilho:** `trigger_update_customer_ltv`
- **Tabela Monitorada:** `4a_customer_service_history`
- **Evento:** AFTER INSERT OR UPDATE OF `service_status`
- **Condição:** Status muda para 'Completed'
- **Tabela Modificada:** `3a_customer_root_record`
- **Campos Atualizados:**
  - `total_spent_cents` (incrementa)
  - `total_completed_appointments` (incrementa)
  - `first_purchase_at` (se NULL)
  - `last_purchase_at` (sempre atualiza)

---

## 3* - FUNÇÕES DE CONSULTA/RELATÓRIO

> Mini-apps chamados pela aplicação para buscar e agregar dados. Não são executados por gatilhos.

### 3.1 Busca faturamento por periodo

**Propósito:** Retorna o faturamento total para um período específico.

**Arquivos:**
```
├─ FN_get_billing_by_period.sql
└─ README.md
```

**Detalhes Técnicos:**
- **Função:** `get_billing_by_period(inbox_id, start_date, end_date)`
- **Tabela Consultada:** `4a_customer_service_history`
- **Filtro:** `service_status = 'Completed'` AND `completed_at BETWEEN dates`
- **Retorno:** Total, contagem, ticket médio, informações do período

---

### 3.2 Busca faturamento hoje

**Propósito:** Retorna o faturamento do dia atual.

**Arquivos:**
```
├─ FN_get_billing_today.sql
└─ README.md
```

**Detalhes Técnicos:**
- **Função:** `get_billing_today(inbox_id)`
- **Dependência:** Chama `get_billing_by_period()` internamente
- **Período:** Data atual (TODAY)

---

### 3.3 Busca faturamento ultimos N dias

**Propósito:** Retorna o faturamento dos últimos N dias.

**Arquivos:**
```
├─ FN_get_billing_last_n_days.sql
└─ README.md
```

**Detalhes Técnicos:**
- **Função:** `get_billing_last_n_days(inbox_id, days)`
- **Dependência:** Chama `get_billing_by_period()` internamente
- **Período:** NOW() - N dias até NOW()

---

### 3.4 Busca faturamento mes especifico

**Propósito:** Retorna o faturamento de um mês específico.

**Arquivos:**
```
├─ FN_get_billing_specific_month.sql
└─ README.md
```

**Detalhes Técnicos:**
- **Função:** `get_billing_specific_month(inbox_id, year, month)`
- **Dependência:** Chama `get_billing_by_period()` internamente
- **Período:** Primeiro ao último dia do mês especificado

---

### 3.5 Busca LTV cliente

**Propósito:** Retorna métricas de Lifetime Value para um cliente específico.

**Arquivos:**
```
├─ FN_get_customer_ltv.sql
└─ README.md
```

**Detalhes Técnicos:**
- **Função:** `get_customer_ltv(root_id)`
- **Tabela Consultada:** `3a_customer_root_record`
- **Retorno:** Campos de LTV do cliente (total_spent, appointments, datas)

---

### 3.6 Lista top clientes por LTV

**Propósito:** Retorna os N clientes com maior Lifetime Value.

**Arquivos:**
```
├─ FN_get_top_customers_by_ltv.sql
└─ README.md
```

**Detalhes Técnicos:**
- **Função:** `get_top_customers_by_ltv(inbox_id, limit)`
- **Tabela Consultada:** `3a_customer_root_record`
- **Ordenação:** `total_spent_cents DESC`
- **Retorno:** Lista dos top N clientes com informações de LTV

---

### 3.7 Busca contadores atendimento por periodo

**Propósito:** Retorna contadores de atendimento agrupados por status para um período.

**Arquivos:**
```
├─ FN_func_get_appointment_counters_by_period.sql
└─ README.md
```

**Detalhes Técnicos:**
- **Função:** `func_get_appointment_counters_by_period(inbox_id, start_date, end_date)`
- **Tabela Consultada:** `4a_customer_service_history`
- **Agrupamento:** Por `service_status`
- **Retorno:** Contagem por status (Scheduled, Confirmed, Completed, etc.)

---

### 3.8 Busca contadores ultimos N dias

**Propósito:** Retorna contadores de atendimento dos últimos N dias.

**Arquivos:**
```
├─ FN_func_get_counters_last_n_days.sql
└─ README.md
```

**Detalhes Técnicos:**
- **Função:** `func_get_counters_last_n_days(inbox_id, days)`
- **Dependência:** Chama `func_get_appointment_counters_by_period()` internamente

---

### 3.9 Busca contadores mes especifico

**Propósito:** Retorna contadores de atendimento de um mês específico.

**Arquivos:**
```
├─ FN_func_get_counters_specific_month.sql
└─ README.md
```

**Detalhes Técnicos:**
- **Função:** `func_get_counters_specific_month(inbox_id, year, month)`
- **Dependência:** Chama `func_get_appointment_counters_by_period()` internamente

---

### 3.10 Conta mudancas status

**Propósito:** Conta quantas vezes cada status foi aplicado em um período (diferente de contadores atuais).

**Arquivos:**
```
├─ FN_func_count_status_changes.sql
└─ README.md
```

**Detalhes Técnicos:**
- **Função:** `func_count_status_changes(inbox_id, start_date, end_date)`
- **Diferença:** Conta mudanças de estado, não estado atual
- **Uso:** Análise de fluxo de trabalho

---

## 4* - FUNÇÕES ADMINISTRATIVAS

> Mini-apps para manutenção manual e recálculos. Executados sob demanda por administradores.

### 4.1 Recalcula LTV cliente individual

**Propósito:** Recalcula manualmente o LTV de um cliente específico do zero.

**Arquivos:**
```
├─ FN_recalculate_customer_ltv.sql
└─ README.md
```

**Detalhes Técnicos:**
- **Função:** `recalculate_customer_ltv(p_root_id)`
- **Uso:** `SELECT recalculate_customer_ltv(123);`
- **Processo:**
  - Soma todos os atendimentos concluídos do cliente
  - Recalcula `total_spent_cents`, `total_completed_appointments`
  - Define `first_purchase_at` e `last_purchase_at` corretamente
  - Sobrescreve valores incorretos
- **Retorno:** JSONB com resultados detalhados
- **Quando usar:** Correção de inconsistências de dados

---

### 4.2 Recalcula LTV todos clientes inbox

**Propósito:** Recalcula o LTV de TODOS os clientes de um inbox em lote.

**Arquivos:**
```
├─ FN_recalculate_all_ltv_for_inbox.sql
└─ README.md
```

**Detalhes Técnicos:**
- **Função:** `recalculate_all_ltv_for_inbox(p_inbox_id)`
- **Uso:** `SELECT recalculate_all_ltv_for_inbox('uuid-inbox');`
- **Processo:**
  - Loop por todos os clientes do inbox
  - Chama `recalculate_customer_ltv()` para cada um
  - Agrega estatísticas
- **Retorno:** JSONB com estatísticas gerais
- **Quando usar:** Migração de dados, correção em massa, auditoria

---

## Fluxo de Execução Principal

```
WEBHOOK EXTERNO
       ↓
[0.1] func_upsert_contact_from_webhook() ← GATEWAY
       ↓
   DADOS NO BANCO
       ↓
┌──────────────────────────────────────┐
│      GATILHOS AUTOMÁTICOS (2*)       │
├──────────────────────────────────────┤
│ INSERT Cliente:                      │
│   [2.2] Gera ID CT{N}                │
│   [2.6] Valida formulário            │
│   [1.1] Atualiza timestamp           │
│                                      │
│ INSERT Atendimento:                  │
│   [2.3] Gera ID AT{N}                │
│   [2.7] Define timestamp status      │
│   [2.8] Atualiza contadores          │
│   [2.9] Atualiza LTV (se Completed)  │
│   [1.1] Atualiza timestamp           │
│                                      │
│ INSERT Mensagem:                     │
│   [2.5] Popula campos + ULID         │
│   [1.1] Atualiza timestamp           │
└──────────────────────────────────────┘
       ↓
   DADOS PRONTOS
       ↓
┌──────────────────────────────────────┐
│    CONSULTAS DA APLICAÇÃO (3*)       │
├──────────────────────────────────────┤
│ [3.1-3.4] Relatórios de faturamento  │
│ [3.5-3.6] Métricas de LTV            │
│ [3.7-3.10] Contadores de status      │
└──────────────────────────────────────┘
       ↓
   MANUTENÇÃO (quando necessário)
       ↓
┌──────────────────────────────────────┐
│        ADMINISTRATIVAS (4*)          │
├──────────────────────────────────────┤
│ [4.1] Recalcula LTV individual       │
│ [4.2] Recalcula LTV em massa         │
└──────────────────────────────────────┘
```

---

## Como Adicionar Novo Mini-App

### 1. Identifique a Categoria

| Se o mini-app... | Categoria |
|------------------|-----------|
| É ponto de entrada crítico para dados externos | 0* |
| Suporta infraestrutura básica do sistema | 1* |
| Executa automaticamente via gatilho | 2* |
| É chamado pela aplicação para consultar/agregar dados | 3* |
| É usado para manutenção/correção manual | 4* |

### 2. Determine o Próximo Número

Verifique o último número usado na categoria e incremente:
- Se categoria 2* tem até 2.9, o próximo é **2.10**
- Se categoria 3* tem até 3.10, o próximo é **3.11**

### 3. Crie a Estrutura de Pastas

```bash
mkdir "X.Y Nome descritivo do mini-app"
```

### 4. Crie os Arquivos

**Se for apenas função:**
```
├─ FN_nome_da_funcao.sql
└─ README.md
```

**Se for função + gatilho(s):**
```
├─ FN_nome_da_funcao.sql
├─ TR_nome_do_trigger.sql
└─ README.md
```

### 5. Template do README.md

```markdown
# X.Y Nome do Mini-App

## Propósito
[Descrição clara do que este mini-app faz]

## Arquivos
- `FN_nome.sql` - [descrição]
- `TR_nome.sql` - [descrição] (se aplicável)

## Detalhes Técnicos
- **Função:** `nome_da_funcao()`
- **Gatilho:** `nome_do_trigger` (ou "Não aplicável")
- **Tabela Monitorada:** [nome] (ou "Não aplicável")
- **Evento:** [BEFORE/AFTER INSERT/UPDATE/DELETE]
- **Tabelas Modificadas:** [lista]
- **Dependências:** [outros mini-apps que este usa]
- **Usado por:** [mini-apps que usam este]

## Exemplo de Uso
```sql
-- Código SQL de exemplo
```

## Observações
[Notas importantes sobre o mini-app]
```

### 6. Atualize Este Catálogo

Adicione a entrada na seção da categoria apropriada seguindo o formato existente.

---

## Manutenção do Catálogo

- **Ao criar novo mini-app:** Adicione entrada neste documento
- **Ao modificar mini-app:** Atualize a entrada correspondente
- **Ao remover mini-app:** Remova a entrada (mantenha numeração dos outros)
- **Revisão periódica:** Verifique se todas as dependências estão corretas

---

## Dependências Entre Mini-Apps

### Diagrama de Dependências

```
[1.2] func_generate_ulid
  ↑
  └── usado por [2.5] Popula campos mensagem

[3.1] get_billing_by_period
  ↑
  ├── usado por [3.2] Busca faturamento hoje
  ├── usado por [3.3] Busca faturamento ultimos N dias
  └── usado por [3.4] Busca faturamento mes especifico

[3.7] func_get_appointment_counters_by_period
  ↑
  ├── usado por [3.8] Busca contadores ultimos N dias
  └── usado por [3.9] Busca contadores mes especifico

[4.1] recalculate_customer_ltv
  ↑
  └── usado por [4.2] Recalcula LTV todos clientes inbox
```

---

## Glossário

| Termo | Definição |
|-------|-----------|
| **Mini-App** | Conjunto de função(ões) e gatilho(s) que executa uma funcionalidade específica |
| **FN** | Prefixo para arquivo de função (Function) |
| **TR** | Prefixo para arquivo de gatilho (Trigger) |
| **LTV** | Lifetime Value - valor total gasto pelo cliente |
| **ULID** | Universally Unique Lexicographically Sortable Identifier |
| **UPSERT** | Operação que insere se não existe ou atualiza se existe |
| **Gateway** | Ponto de entrada de dados no sistema |

---

**Última atualização:** 2025-11-16
**Total de Mini-Apps:** 24
**Versão do Catálogo:** 1.0
