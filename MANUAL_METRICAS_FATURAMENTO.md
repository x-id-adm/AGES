# 📊 Manual de Métricas de Faturamento e LTV

## Índice

1. [Introdução](#introdução)
2. [Instalação](#instalação)
3. [Conceitos Básicos](#conceitos-básicos)
4. [Faturamento por Tempo](#faturamento-por-tempo)
5. [LTV por Cliente](#ltv-por-cliente)
6. [Atualização Automática](#atualização-automática)
7. [Casos de Uso Práticos](#casos-de-uso-práticos)
8. [Queries Avançadas](#queries-avançadas)
9. [Funções Auxiliares](#funções-auxiliares)
10. [Troubleshooting](#troubleshooting)

---

## Introdução

Este sistema implementa rastreamento completo de faturamento com duas funcionalidades principais:

### 1. **Faturamento por Tempo**
Responde perguntas como:
- Quanto faturei hoje?
- Quanto faturei nos últimos 7 dias?
- Quanto faturei em Janeiro?

### 2. **LTV por Cliente** (Lifetime Value)
Responde perguntas como:
- Quanto um cliente específico já gastou?
- Quem são meus top 10 clientes?
- Qual o ticket médio dos meus clientes?

**💰 Importante:** Todos os valores são armazenados em **centavos** para evitar erros de arredondamento, e o sistema é **genérico** para qualquer moeda (Real, Dólar, Euro, etc.).

---

## Instalação

Execute os arquivos SQL nesta ordem:

```bash
# 1. Schema principal (se ainda não executou)
psql -d seu_banco < schema.sql

# 2. Criar funções de faturamento
psql -d seu_banco < functions_billing_metrics.sql

# 3. Criar trigger de atualização automática
psql -d seu_banco < trigger_update_customer_ltv.sql

# 4. (Opcional) Executar testes
psql -d seu_banco < test_billing_metrics.sql
```

### O que foi criado?

**Novos campos na tabela `3a_customer_root_record`:**

| Campo | Tipo | Descrição |
|-------|------|-----------|
| `total_spent_cents` | BIGINT | Total que o cliente gastou (em centavos) |
| `total_completed_appointments` | INTEGER | Quantidade de atendimentos finalizados |
| `first_purchase_at` | TIMESTAMPTZ | Data da primeira compra |
| `last_purchase_at` | TIMESTAMPTZ | Data da última compra |

---

## Conceitos Básicos

### Valores em Centavos

Todos os valores monetários são armazenados em **centavos**:

- R$ 100,00 = 10.000 centavos
- R$ 50,50 = 5.050 centavos
- R$ 1.234,56 = 123.456 centavos

As funções retornam tanto em `_cents` (centavos) quanto em `_currency` (moeda) para conveniência.

### Status de Atendimentos

Apenas atendimentos com status `'Completed'` são considerados no faturamento.

---

## Faturamento por Tempo

### 1. Faturamento de Hoje

```sql
SELECT get_billing_today('sua-inbox-uuid');
```

**Exemplo de retorno:**
```json
{
  "total_billing_cents": 45000,           // R$ 450,00
  "total_billing_currency": 450.00,       // Em moeda
  "completed_count": 15,                  // 15 atendimentos
  "average_ticket_cents": 3000,           // R$ 30,00
  "average_ticket_currency": 30.00,       // Ticket médio
  "period": {
    "start": "2025-11-15T00:00:00Z",
    "end": "2025-11-15T14:30:00Z"
  }
}
```

### 2. Faturamento dos Últimos N Dias

```sql
-- Últimos 7 dias
SELECT get_billing_last_n_days('sua-inbox-uuid', 7);

-- Últimos 30 dias
SELECT get_billing_last_n_days('sua-inbox-uuid', 30);

-- Último ano (365 dias)
SELECT get_billing_last_n_days('sua-inbox-uuid', 365);
```

### 3. Faturamento de um Mês Específico

```sql
-- Janeiro de 2025
SELECT get_billing_specific_month('sua-inbox-uuid', 2025, 1);

-- Dezembro de 2024
SELECT get_billing_specific_month('sua-inbox-uuid', 2024, 12);

-- Mês atual
SELECT get_billing_specific_month(
    'sua-inbox-uuid',
    EXTRACT(YEAR FROM NOW())::INT,
    EXTRACT(MONTH FROM NOW())::INT
);
```

### 4. Faturamento de Período Customizado

```sql
-- Faturamento entre 01/jan e 31/jan/2025
SELECT get_billing_by_period(
    'sua-inbox-uuid',
    '2025-01-01 00:00:00'::TIMESTAMPTZ,
    '2025-02-01 00:00:00'::TIMESTAMPTZ
);

-- Faturamento do último trimestre
SELECT get_billing_by_period(
    'sua-inbox-uuid',
    NOW() - INTERVAL '3 months',
    NOW()
);
```

### Exemplo Prático: Dashboard de Faturamento

```sql
-- Faturamento de hoje, últimos 7 dias e mês atual
SELECT
    'Hoje' as periodo,
    (get_billing_today('sua-inbox')->>'total_billing_currency')::NUMERIC as valor,
    (get_billing_today('sua-inbox')->>'completed_count')::INT as atendimentos
UNION ALL
SELECT
    'Últimos 7 dias',
    (get_billing_last_n_days('sua-inbox', 7)->>'total_billing_currency')::NUMERIC,
    (get_billing_last_n_days('sua-inbox', 7)->>'completed_count')::INT
UNION ALL
SELECT
    'Mês atual',
    (get_billing_specific_month('sua-inbox', 2025, 11)->>'total_billing_currency')::NUMERIC,
    (get_billing_specific_month('sua-inbox', 2025, 11)->>'completed_count')::INT;
```

**Resultado:**
```
   periodo    | valor  | atendimentos
--------------+--------+--------------
 Hoje         | 150.00 |  5
 Últimos 7 dias | 850.00 | 28
 Mês atual    | 3200.00| 102
```

---

## LTV por Cliente

### 1. LTV de um Cliente Específico

```sql
SELECT get_customer_ltv(123);  -- root_id do cliente
```

**Exemplo de retorno:**
```json
{
  "root_id": 123,
  "client_id": "CT456",
  "treatment_name": "João Silva",
  "total_spent_cents": 60000,              // R$ 600,00
  "total_spent_currency": 600.00,
  "total_completed_appointments": 3,       // 3 atendimentos
  "average_ticket_cents": 20000,           // R$ 200,00
  "average_ticket_currency": 200.00,
  "first_purchase_at": "2025-01-15T10:00:00Z",
  "last_purchase_at": "2025-11-10T14:30:00Z",
  "customer_lifetime_days": 299            // 299 dias de cliente
}
```

### 2. Top Clientes por LTV

```sql
-- Top 10 clientes
SELECT get_top_customers_by_ltv('sua-inbox-uuid', 10);

-- Top 50 clientes
SELECT get_top_customers_by_ltv('sua-inbox-uuid', 50);
```

### 3. View Consolidada de Clientes

```sql
-- Ver todos os clientes com LTV > 0, ordenados por valor
SELECT *
FROM vw_customer_billing_summary
WHERE inbox_id = 'sua-inbox-uuid'
ORDER BY total_spent_cents DESC
LIMIT 20;
```

**Colunas disponíveis na view:**
- `root_id`, `client_id`, `treatment_name`
- `total_spent_cents`, `total_spent_currency`
- `total_completed_appointments`
- `average_ticket_cents`, `average_ticket_currency`
- `first_purchase_at`, `last_purchase_at`
- `customer_lifetime_days`

### Exemplo Prático: Perfil Completo do Cliente

```sql
-- Ver tudo sobre um cliente específico
SELECT
    treatment_name as nome,
    total_spent_currency as total_gasto,
    total_completed_appointments as atendimentos,
    average_ticket_currency as ticket_medio,
    customer_lifetime_days as dias_como_cliente,
    first_purchase_at as primeira_compra,
    last_purchase_at as ultima_compra
FROM vw_customer_billing_summary
WHERE root_id = 123;
```

**Resultado:**
```
    nome     | total_gasto | atendimentos | ticket_medio | dias_como_cliente | primeira_compra      | ultima_compra
-------------+-------------+--------------+--------------+-------------------+---------------------+---------------------
 João Silva  | 600.00      | 3            | 200.00       | 299               | 2025-01-15 10:00:00 | 2025-11-10 14:30:00
```

---

## Atualização Automática

O LTV é atualizado **automaticamente** quando um atendimento é marcado como `'Completed'`.

### Como Funciona o Fluxo do Operador

#### 1. Criação do Atendimento

```sql
INSERT INTO "4a_customer_service_history" (
    service_id,
    inbox_id,
    root_id,
    service_datetime_start,
    service_datetime_end,
    service_status,
    value_cents,
    scheduled_at,
    created_at
) VALUES (
    'AT123',
    'sua-inbox-uuid',
    456,  -- root_id do cliente
    NOW(),
    NOW() + INTERVAL '1 hour',
    'Scheduled',
    20000,  -- R$ 200,00
    NOW(),
    NOW()
);
```

#### 2. Finalização do Atendimento

```sql
-- Operador marca como completado
UPDATE "4a_customer_service_history"
SET
    service_status = 'Completed',
    completed_at = NOW()
WHERE service_id = 'AT123';
```

#### 3. O Trigger Atualiza Automaticamente

O trigger faz AUTOMATICAMENTE:
- ✅ Soma R$ 200,00 ao `total_spent_cents` do cliente
- ✅ Incrementa `total_completed_appointments`
- ✅ Atualiza `last_purchase_at`
- ✅ Define `first_purchase_at` (se for a primeira compra)

#### 4. Verificar o LTV Atualizado

```sql
SELECT get_customer_ltv(456);
```

### Importante: Proteção Contra Duplicação

O trigger é inteligente e **NÃO duplica valores**:

❌ Se você atualizar um atendimento que JÁ está `'Completed'`, não soma novamente
❌ Se você atualizar apenas outros campos (notes, attachments), não afeta o LTV
❌ Se `value_cents` for `NULL` ou `0`, não atualiza o LTV

---

## Casos de Uso Práticos

### 1. Dashboard Diário

```sql
-- Visão geral do dia
SELECT
    (get_billing_today('inbox-uuid')->>'total_billing_currency')::NUMERIC as faturamento_hoje,
    (get_billing_today('inbox-uuid')->>'completed_count')::INT as atendimentos_hoje,
    (get_billing_today('inbox-uuid')->>'average_ticket_currency')::NUMERIC as ticket_medio_hoje;
```

### 2. Comparativo Mensal

```sql
-- Comparar faturamento mês a mês de 2025
SELECT
    to_char(make_date(2025, mes, 1), 'Month') as mes,
    (get_billing_specific_month('inbox-uuid', 2025, mes)->>'total_billing_currency')::NUMERIC as faturamento,
    (get_billing_specific_month('inbox-uuid', 2025, mes)->>'completed_count')::INT as atendimentos
FROM generate_series(1, 12) as mes
ORDER BY mes;
```

**Resultado:**
```
    mes     | faturamento | atendimentos
------------+-------------+--------------
 January    | 2500.00     | 85
 February   | 3200.00     | 102
 March      | 2800.00     | 91
 ...
```

### 3. Top Clientes

```sql
-- Extrair top 10 clientes de forma legível
SELECT
    (cliente->>'treatment_name')::TEXT as nome,
    (cliente->>'total_spent_currency')::NUMERIC as total_gasto,
    (cliente->>'total_completed_appointments')::INT as atendimentos,
    (cliente->>'average_ticket_currency')::NUMERIC as ticket_medio,
    (cliente->>'last_purchase_at')::TIMESTAMPTZ as ultima_compra
FROM (
    SELECT jsonb_array_elements(
        get_top_customers_by_ltv('inbox-uuid', 10)
    ) as cliente
) sub
ORDER BY (cliente->>'total_spent_cents')::BIGINT DESC;
```

### 4. Clientes VIP (mais de R$ 1000)

```sql
SELECT
    treatment_name as nome,
    total_spent_currency as total_gasto,
    total_completed_appointments as atendimentos,
    average_ticket_currency as ticket_medio
FROM vw_customer_billing_summary
WHERE inbox_id = 'inbox-uuid'
  AND total_spent_currency > 1000
ORDER BY total_spent_cents DESC;
```

### 5. Clientes Frequentes (mais de 10 atendimentos)

```sql
SELECT
    treatment_name as nome,
    total_completed_appointments as atendimentos,
    total_spent_currency as total_gasto,
    average_ticket_currency as ticket_medio
FROM vw_customer_billing_summary
WHERE inbox_id = 'inbox-uuid'
  AND total_completed_appointments > 10
ORDER BY total_completed_appointments DESC;
```

### 6. Clientes com Maior Ticket Médio

```sql
SELECT
    treatment_name as nome,
    average_ticket_currency as ticket_medio,
    total_completed_appointments as atendimentos,
    total_spent_currency as total_gasto
FROM vw_customer_billing_summary
WHERE inbox_id = 'inbox-uuid'
  AND total_completed_appointments >= 3  -- Pelo menos 3 atendimentos
ORDER BY average_ticket_cents DESC
LIMIT 10;
```

### 7. Clientes Inativos (sem compra há mais de 90 dias)

```sql
SELECT
    treatment_name as nome,
    last_purchase_at as ultima_compra,
    total_spent_currency as total_gasto,
    EXTRACT(DAY FROM (NOW() - last_purchase_at))::INT as dias_sem_comprar
FROM vw_customer_billing_summary
WHERE inbox_id = 'inbox-uuid'
  AND last_purchase_at < NOW() - INTERVAL '90 days'
ORDER BY last_purchase_at ASC;
```

---

## Queries Avançadas

### 1. Faturamento por Dia da Semana

```sql
-- Descobrir qual dia da semana fatura mais
SELECT
    to_char(completed_at, 'Day') as dia_semana,
    COUNT(*) as atendimentos,
    SUM(value_cents) / 100.0 as faturamento
FROM "4a_customer_service_history"
WHERE inbox_id = 'inbox-uuid'
  AND service_status = 'Completed'
  AND completed_at >= NOW() - INTERVAL '30 days'
GROUP BY to_char(completed_at, 'Day'), EXTRACT(DOW FROM completed_at)
ORDER BY EXTRACT(DOW FROM completed_at);
```

### 2. Taxa de Crescimento Mensal

```sql
-- Comparar faturamento do mês atual com o anterior
WITH mes_atual AS (
    SELECT (get_billing_specific_month('inbox-uuid', 2025, 11)->>'total_billing_cents')::BIGINT as valor
),
mes_anterior AS (
    SELECT (get_billing_specific_month('inbox-uuid', 2025, 10)->>'total_billing_cents')::BIGINT as valor
)
SELECT
    (mes_atual.valor / 100.0) as faturamento_atual,
    (mes_anterior.valor / 100.0) as faturamento_anterior,
    ROUND(((mes_atual.valor - mes_anterior.valor)::NUMERIC / mes_anterior.valor * 100), 2) as crescimento_percentual
FROM mes_atual, mes_anterior;
```

**Resultado:**
```
 faturamento_atual | faturamento_anterior | crescimento_percentual
-------------------+----------------------+------------------------
 3200.00           | 2500.00              | 28.00
```

### 3. Segmentação de Clientes por LTV

```sql
-- Classificar clientes em categorias
SELECT
    CASE
        WHEN total_spent_currency >= 2000 THEN 'VIP (R$ 2000+)'
        WHEN total_spent_currency >= 1000 THEN 'Premium (R$ 1000-2000)'
        WHEN total_spent_currency >= 500 THEN 'Regular (R$ 500-1000)'
        ELSE 'Novo (< R$ 500)'
    END as categoria,
    COUNT(*) as quantidade_clientes,
    SUM(total_spent_currency) as faturamento_total
FROM vw_customer_billing_summary
WHERE inbox_id = 'inbox-uuid'
GROUP BY categoria
ORDER BY SUM(total_spent_cents) DESC;
```

**Resultado:**
```
      categoria      | quantidade_clientes | faturamento_total
---------------------+---------------------+-------------------
 VIP (R$ 2000+)      | 15                  | 45000.00
 Premium (R$ 1000-2000)| 42                | 52000.00
 Regular (R$ 500-1000) | 78                | 58500.00
 Novo (< R$ 500)       | 235               | 47000.00
```

### 4. Análise de Retenção (Cliente Voltou?)

```sql
-- Clientes que compraram mais de uma vez
SELECT
    CASE
        WHEN total_completed_appointments = 1 THEN '1 compra (novo)'
        WHEN total_completed_appointments BETWEEN 2 AND 3 THEN '2-3 compras'
        WHEN total_completed_appointments BETWEEN 4 AND 10 THEN '4-10 compras'
        ELSE '10+ compras (fiel)'
    END as frequencia,
    COUNT(*) as quantidade_clientes,
    ROUND(AVG(total_spent_currency), 2) as ltv_medio
FROM vw_customer_billing_summary
WHERE inbox_id = 'inbox-uuid'
GROUP BY frequencia
ORDER BY MIN(total_completed_appointments);
```

---

## Funções Auxiliares

### 1. Recalcular LTV de um Cliente

Use quando precisar corrigir dados ou sincronizar valores:

```sql
SELECT recalculate_customer_ltv(123);  -- root_id do cliente
```

**Retorna:**
```json
{
  "root_id": 123,
  "total_spent_cents": 60000,
  "total_spent_currency": 600.00,
  "total_completed_appointments": 3,
  "first_purchase_at": "2025-01-15T10:00:00Z",
  "last_purchase_at": "2025-11-10T14:30:00Z"
}
```

### 2. Recalcular LTV de Todos os Clientes de uma Inbox

Use para inicialização ou correção em massa:

```sql
SELECT recalculate_all_ltv_for_inbox('inbox-uuid');
```

**Retorna:**
```json
{
  "inbox_id": "inbox-uuid",
  "customers_processed": 150,
  "total_billing_cents": 1500000,
  "total_billing_currency": 15000.00,
  "recalculated_at": "2025-11-15T14:30:00Z"
}
```

---

## Troubleshooting

### Problema 1: LTV não está sendo atualizado

**Possíveis causas:**

1. Trigger não está criado
2. Status não mudou para `'Completed'`
3. Campo `value_cents` está NULL ou 0
4. Campo `completed_at` não foi preenchido

**Como diagnosticar:**

```sql
-- 1. Verificar se trigger existe
\d+ "4a_customer_service_history"
-- Deve aparecer: trigger_update_customer_ltv

-- 2. Verificar dados do atendimento
SELECT
    service_id,
    service_status,
    value_cents,
    completed_at
FROM "4a_customer_service_history"
WHERE service_id = 'AT123';

-- 3. Ver logs do trigger (ative antes)
SET client_min_messages TO NOTICE;
```

**Solução:**

```sql
-- Recalcular manualmente
SELECT recalculate_customer_ltv(123);
```

### Problema 2: Valores duplicados

Se você acidentalmente contou o mesmo atendimento duas vezes:

```sql
-- Recalcular do zero
SELECT recalculate_customer_ltv(123);
```

### Problema 3: Valores inconsistentes

```sql
-- Recalcular todos os clientes
SELECT recalculate_all_ltv_for_inbox('inbox-uuid');
```

### Problema 4: Performance lenta em queries

```sql
-- Verificar se índices existem
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = '3a_customer_root_record'
  AND indexname LIKE '%ltv%';

-- Devem aparecer:
-- idx_customer_total_spent
-- idx_customer_last_purchase
-- idx_customer_completed_count
```

---

## Resumo Rápido

### Faturamento por Tempo

```sql
-- Hoje
SELECT get_billing_today('inbox-uuid');

-- Últimos N dias
SELECT get_billing_last_n_days('inbox-uuid', 7);

-- Mês específico
SELECT get_billing_specific_month('inbox-uuid', 2025, 1);

-- Período customizado
SELECT get_billing_by_period('inbox-uuid', data_inicio, data_fim);
```

### LTV por Cliente

```sql
-- Cliente específico
SELECT get_customer_ltv(123);

-- Top clientes
SELECT get_top_customers_by_ltv('inbox-uuid', 10);

-- View consolidada
SELECT * FROM vw_customer_billing_summary
WHERE inbox_id = 'inbox-uuid'
ORDER BY total_spent_cents DESC;
```

### Funções Auxiliares

```sql
-- Recalcular um cliente
SELECT recalculate_customer_ltv(123);

-- Recalcular todos
SELECT recalculate_all_ltv_for_inbox('inbox-uuid');
```

---

## Dicas Finais

1. ✅ Valores sempre em **centavos** no banco
2. ✅ Use `_currency` para exibir ao usuário
3. ✅ Trigger atualiza **automaticamente**
4. ✅ Funções de recálculo são **seguras**
5. ✅ Sistema é **multi-moeda** (BRL, USD, EUR, etc.)

---

**Versão:** 1.0
**Data:** 2025-11-15
**Sistema:** AGES
