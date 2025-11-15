# Taxas de Conversão - Documentação

## Visão Geral

O sistema calcula automaticamente as taxas de conversão baseadas nos contadores de status de agendamentos. As taxas são atualizadas **em tempo real** sempre que um agendamento muda de status.

## Tabela: `0b_inbox_counters`

### Contadores do Funil de Atendimento

| Campo | Tipo | Descrição | Mudado Por |
|-------|------|-----------|------------|
| `contact_count` | INT | Total de contatos que iniciaram conversa | Sistema (webhook) |
| `form_count` | INT | Total de contatos que preencheram ficha completa | Sistema (triggers) |
| `scheduling_count` | INT | Total de agendamentos realizados | Sistema (triggers) |

### Contadores de Status de Agendamentos

| Campo | Tipo | Descrição | Mudado Por |
|-------|------|-----------|------------|
| `scheduled_count` | INT | Total de agendamentos com status "Scheduled" | Agente de IA |
| `confirmed_count` | INT | Total de agendamentos com status "Confirmed" | Agente de IA |
| `completed_count` | INT | Total de agendamentos com status "Completed" | Humano |
| `cancelled_count` | INT | Total de agendamentos com status "Cancelled" | Humano/IA |
| `rescheduled_count` | INT | Total de agendamentos com status "Rescheduled" | Humano |
| `no_show_count` | INT | Total de agendamentos com status "No_Show" | Humano |

### Taxas de Conversão (Calculadas Automaticamente)

#### Taxas do Funil de Atendimento

| Campo | Tipo | Fórmula | Exemplo | Descrição |
|-------|------|---------|---------|-----------|
| `form_rate` | DECIMAL(5,4) | `form_count / contact_count` | 0.7500 (75%) | Taxa de cadastro (ficha) |
| `scheduling_rate` | DECIMAL(5,4) | `scheduling_count / contact_count` | 0.6000 (60%) | Taxa de agendamento |

#### Taxas de Status de Agendamentos

| Campo | Tipo | Fórmula | Exemplo | Descrição |
|-------|------|---------|---------|-----------|
| `confirmed_rate` | DECIMAL(5,4) | `confirmed_count / scheduled_count` | 0.8500 (85%) | Taxa de confirmação |
| `completed_rate` | DECIMAL(5,4) | `completed_count / scheduled_count` | 0.7500 (75%) | Taxa de conclusão |
| `cancelled_rate` | DECIMAL(5,4) | `cancelled_count / scheduled_count` | 0.1000 (10%) | Taxa de cancelamento |
| `rescheduled_rate` | DECIMAL(5,4) | `rescheduled_count / scheduled_count` | 0.0500 (5%) | Taxa de reagendamento |
| `no_show_rate` | DECIMAL(5,4) | `no_show_count / scheduled_count` | 0.0500 (5%) | Taxa de não comparecimento |

## Como Funciona

### 1. Cálculo Automático

As taxas são **colunas geradas** (`GENERATED ALWAYS AS ... STORED`), ou seja:
- ✅ **Atualização automática**: Sempre que um contador muda, a taxa é recalculada
- ✅ **Performance otimizada**: O valor é armazenado (STORED) no banco
- ✅ **Sem código adicional**: Não precisa de triggers ou funções extras

### 2. Formato dos Valores

- **Formato armazenado**: Decimal com 4 casas decimais
  - Exemplo: `0.9310` representa 93.10%
  - Exemplo: `0.0000` representa 0%

- **Para exibir em percentual**:
  ```sql
  SELECT ROUND(confirmed_rate * 100, 2) || '%' AS taxa_confirmacao
  FROM "0b_inbox_counters";
  ```
  Resultado: `93.10%`

### 3. Proteção contra Divisão por Zero

Todas as taxas têm proteção contra divisão por zero:

**Taxas de funil** (quando não há contatos):
```sql
CASE
    WHEN contact_count > 0
    THEN ROUND(form_count::DECIMAL / contact_count, 4)
    ELSE 0
END
```

**Taxas de status** (quando não há agendamentos):
```sql
CASE
    WHEN scheduled_count > 0
    THEN ROUND(confirmed_count::DECIMAL / scheduled_count, 4)
    ELSE 0
END
```

## Exemplos de Uso

### Consultar Funil Completo de Atendimento

```sql
SELECT
    inbox_id,

    -- Contadores do funil
    contact_count AS total_contatos,
    form_count AS total_fichas,
    scheduling_count AS total_agendamentos,

    -- Taxas do funil em percentual
    ROUND(form_rate * 100, 2) || '%' AS taxa_cadastro,
    ROUND(scheduling_rate * 100, 2) || '%' AS taxa_agendamento,

    -- Taxas de conversão de agendamentos
    ROUND(confirmed_rate * 100, 2) || '%' AS taxa_confirmacao,
    ROUND(completed_rate * 100, 2) || '%' AS taxa_conclusao
FROM "0b_inbox_counters"
WHERE inbox_id = 'sua-inbox-id-aqui';
```

**Exemplo de resultado:**
```
total_contatos: 1000
total_fichas: 750
total_agendamentos: 600
taxa_cadastro: 75.00%
taxa_agendamento: 60.00%
taxa_confirmacao: 85.00%
taxa_conclusao: 75.00%
```

### Consultar Taxas de Status de uma Inbox

```sql
SELECT
    inbox_id,
    scheduled_count AS total_agendamentos,

    -- Taxas em decimal
    confirmed_rate,
    completed_rate,

    -- Taxas em percentual
    ROUND(confirmed_rate * 100, 2) || '%' AS taxa_confirmacao_pct,
    ROUND(completed_rate * 100, 2) || '%' AS taxa_conclusao_pct
FROM "0b_inbox_counters"
WHERE inbox_id = 'sua-inbox-id-aqui';
```

### Consultar Top Inboxes por Taxa de Conclusão

```sql
SELECT
    i.inbox_name,
    c.scheduled_count AS agendamentos,
    ROUND(c.completed_rate * 100, 2) || '%' AS taxa_conclusao
FROM "0b_inbox_counters" c
JOIN "0a_inbox_whatsapp" i ON i.inbox_id = c.inbox_id
WHERE c.scheduled_count > 0  -- Apenas inboxes com agendamentos
ORDER BY c.completed_rate DESC
LIMIT 10;
```

### Alertar Inboxes com Alta Taxa de Cancelamento

```sql
SELECT
    i.inbox_name,
    c.scheduled_count AS agendamentos,
    ROUND(c.cancelled_rate * 100, 2) || '%' AS taxa_cancelamento
FROM "0b_inbox_counters" c
JOIN "0a_inbox_whatsapp" i ON i.inbox_id = c.inbox_id
WHERE c.cancelled_rate > 0.15  -- Mais de 15% de cancelamentos
  AND c.scheduled_count >= 20   -- Amostra mínima
ORDER BY c.cancelled_rate DESC;
```

### Identificar Gargalos no Funil de Atendimento

```sql
SELECT
    i.inbox_name,
    c.contact_count AS contatos,
    c.form_count AS fichas,
    c.scheduling_count AS agendamentos,

    -- Identificar onde há perda
    ROUND(c.form_rate * 100, 2) || '%' AS taxa_cadastro,
    ROUND(c.scheduling_rate * 100, 2) || '%' AS taxa_agendamento,

    -- Calcular taxa de conversão de ficha para agendamento
    CASE
        WHEN c.form_count > 0
        THEN ROUND((c.scheduling_count::DECIMAL / c.form_count) * 100, 2) || '%'
        ELSE '0%'
    END AS taxa_ficha_para_agendamento
FROM "0b_inbox_counters" c
JOIN "0a_inbox_whatsapp" i ON i.inbox_id = c.inbox_id
WHERE c.contact_count >= 50  -- Amostra mínima
  AND (c.form_rate < 0.50 OR c.scheduling_rate < 0.40)  -- Baixa conversão
ORDER BY c.contact_count DESC;
```

## Métricas de Negócio

### Taxa de Conversão Ideal

#### Funil de Atendimento

| Métrica | Meta Recomendada | Crítico | Descrição |
|---------|------------------|---------|-----------|
| Taxa de Cadastro (Ficha) | > 70% | < 50% | % de contatos que preencheram ficha |
| Taxa de Agendamento | > 50% | < 30% | % de contatos que agendaram |

#### Status de Agendamentos

| Métrica | Meta Recomendada | Crítico | Descrição |
|---------|------------------|---------|-----------|
| Taxa de Confirmação | > 80% | < 60% | % de agendamentos confirmados |
| Taxa de Conclusão | > 70% | < 50% | % de agendamentos concluídos |
| Taxa de Cancelamento | < 10% | > 20% | % de agendamentos cancelados |
| Taxa de No-Show | < 5% | > 15% | % de não comparecimento |

### Interpretação das Taxas

#### Taxas do Funil

**Taxa de Cadastro Baixa (< 50%)**
- ⚠️ Processo de preenchimento de ficha pode estar complexo
- ⚠️ Verificar se campos obrigatórios são realmente necessários
- ⚠️ Revisar mensagens do bot que solicitam os dados

**Taxa de Agendamento Baixa (< 30%)**
- ⚠️ Barreira entre ficha e agendamento
- ⚠️ Verificar disponibilidade de horários
- ⚠️ Melhorar clareza do processo de agendamento

**Taxa de Cadastro Alta (> 70%)**
- ✅ Processo de cadastro está fluido
- ✅ Bot está conduzindo bem a conversa

**Taxa de Agendamento Alta (> 50%)**
- ✅ Interesse genuíno dos contatos
- ✅ Oferta de horários adequada

#### Taxas de Status

**Taxa de Confirmação Alta (> 80%)**
- ✅ Agente de IA está funcionando bem
- ✅ Processo de agendamento está claro

**Taxa de Conclusão Alta (> 70%)**
- ✅ Clientes estão comparecendo
- ✅ Serviço entregando valor

**Taxa de Cancelamento Alta (> 15%)**
- ⚠️ Investigar motivos dos cancelamentos
- ⚠️ Melhorar lembretes/confirmações

**Taxa de No-Show Alta (> 10%)**
- ⚠️ Implementar lembretes mais eficazes
- ⚠️ Revisar política de confirmação

## Testes

Para validar os cálculos das taxas, execute:

```bash
psql -U seu_usuario -d sua_database -f test_conversion_rates.sql
```

O arquivo de testes cria cenários com:
- 100 agendamentos iniciais
- 85% de confirmação
- 75% de conclusão
- Distribuição de cancelamentos, reagendamentos e no-shows

## Histórico de Alterações

### 2025-11-15 (v2)
- ✨ **NOVO**: Adicionadas taxas de conversão do funil de atendimento
  - `form_rate`: Taxa de cadastro (fichas/contatos)
  - `scheduling_rate`: Taxa de agendamento (agendamentos/contatos)
- 📝 Atualizada documentação com exemplos do funil completo
- 📊 Adicionadas métricas de negócio para o funil

### 2025-11-15 (v1)
- ✨ Adicionadas colunas de taxa de conversão automática de status
- ✨ Criados testes de validação
- 📝 Documentação criada

### 2025-11-14
- ✨ Implementados contadores de status de agendamentos
- ✨ Criado trigger para atualização automática dos contadores

## Referências

- **Schema**: `schema.sql` (linhas 75-122)
- **Testes**: `test_conversion_rates.sql`
- **Funções relacionadas**:
  - `func_upsert_contact_from_webhook()` - Incrementa `contact_count`
  - `func_update_form_counter()` - Incrementa `form_count`
  - `func_update_appointment_status_counter()` - Incrementa contadores de status
