# Métricas de Faturamento e LTV (Lifetime Value)

## 📊 Visão Geral

Este módulo implementa rastreamento completo de faturamento com duas funcionalidades principais:

1. **Faturamento por Tempo**: Quanto foi faturado em períodos específicos (hoje, últimos 7 dias, janeiro, etc.)
2. **Faturamento por Cliente (LTV)**: Quanto cada cliente já gastou ao longo do tempo

---

## 🚀 Instalação

Execute os arquivos SQL na seguinte ordem:

```bash
# 1. Schema principal (se ainda não executou)
psql -d seu_banco < schema.sql

# 2. Adicionar campos de LTV
psql -d seu_banco < schema_billing_ltv.sql

# 3. Criar funções de faturamento
psql -d seu_banco < functions_billing_metrics.sql

# 4. Criar trigger de atualização automática
psql -d seu_banco < trigger_update_customer_ltv.sql

# 5. (Opcional) Executar testes
psql -d seu_banco < test_billing_metrics.sql
```

---

## 📋 O que foi criado?

### 1. Novos Campos na Tabela `3a_customer_root_record`

| Campo | Tipo | Descrição |
|-------|------|-----------|
| `total_spent_cents` | INTEGER | Valor total gasto pelo cliente (em centavos) |
| `total_completed_appointments` | INTEGER | Quantidade de atendimentos completados |
| `first_purchase_at` | TIMESTAMPTZ | Data da primeira compra |
| `last_purchase_at` | TIMESTAMPTZ | Data da última compra |

### 2. Funções de Faturamento por Tempo

#### Faturamento de hoje
```sql
SELECT func_get_billing_today('uuid-da-inbox');
```

**Retorna:**
```json
{
  "total_billing_cents": 45000,
  "total_billing_reais": 450.00,
  "completed_count": 15,
  "average_ticket_cents": 3000,
  "average_ticket_reais": 30.00,
  "period": {
    "start": "2025-11-15T00:00:00Z",
    "end": "2025-11-15T14:30:00Z"
  }
}
```

#### Faturamento dos últimos N dias
```sql
-- Últimos 7 dias
SELECT func_get_billing_last_n_days('uuid-da-inbox', 7);

-- Últimos 30 dias
SELECT func_get_billing_last_n_days('uuid-da-inbox', 30);
```

#### Faturamento de um mês específico
```sql
-- Janeiro de 2025
SELECT func_get_billing_specific_month('uuid-da-inbox', 2025, 1);

-- Dezembro de 2024
SELECT func_get_billing_specific_month('uuid-da-inbox', 2024, 12);
```

#### Faturamento de um período customizado
```sql
SELECT func_get_billing_by_period(
    'uuid-da-inbox',
    '2025-01-01 00:00:00'::TIMESTAMPTZ,
    '2025-01-31 23:59:59'::TIMESTAMPTZ
);
```

### 3. Funções de LTV por Cliente

#### LTV de um cliente específico
```sql
SELECT func_get_customer_ltv(123);  -- root_id do cliente
```

**Retorna:**
```json
{
  "root_id": 123,
  "client_id": "CT456",
  "treatment_name": "João Silva",
  "total_spent_cents": 60000,
  "total_spent_reais": 600.00,
  "total_completed_appointments": 3,
  "average_ticket_cents": 20000,
  "average_ticket_reais": 200.00,
  "first_purchase_at": "2025-01-15T10:00:00Z",
  "last_purchase_at": "2025-11-10T14:30:00Z",
  "customer_lifetime_days": 299
}
```

#### Top clientes por LTV
```sql
-- Top 10 clientes
SELECT func_get_top_customers_by_ltv('uuid-da-inbox', 10);

-- Top 50 clientes
SELECT func_get_top_customers_by_ltv('uuid-da-inbox', 50);
```

### 4. View de Resumo

#### Ver todos os clientes ordenados por LTV
```sql
SELECT *
FROM vw_customer_billing_summary
WHERE inbox_id = 'uuid-da-inbox'
ORDER BY total_spent_cents DESC
LIMIT 20;
```

#### Filtrar clientes que gastaram mais de R$ 1000
```sql
SELECT *
FROM vw_customer_billing_summary
WHERE total_spent_reais > 1000
  AND inbox_id = 'uuid-da-inbox'
ORDER BY total_spent_cents DESC;
```

---

## 🔄 Atualização Automática (Trigger)

O LTV é atualizado **automaticamente** quando:

1. Um atendimento é criado já com status `'Completed'`
2. Um atendimento tem seu status alterado para `'Completed'`

### Como funciona o operador humano:

```sql
-- 1. Operador cria o atendimento
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
    'uuid-da-inbox',
    456,  -- root_id do cliente
    NOW(),
    NOW() + INTERVAL '1 hour',
    'Scheduled',
    20000,  -- R$ 200.00
    NOW(),
    NOW()
);

-- 2. Quando o atendimento termina, operador muda o status
UPDATE "4a_customer_service_history"
SET
    service_status = 'Completed',
    completed_at = NOW()
WHERE service_id = 'AT123';

-- 3. O trigger AUTOMATICAMENTE atualiza o LTV do cliente:
--    - Soma R$ 200.00 ao total_spent_cents
--    - Incrementa total_completed_appointments
--    - Atualiza last_purchase_at
--    - Se for a primeira compra, define first_purchase_at
```

### Importante: Evita Duplicação

O trigger é inteligente e **NÃO duplica valores**:

- Se você atualizar um atendimento que JÁ está `'Completed'`, não soma novamente
- Se você atualizar apenas outros campos (notes, attachments), não afeta o LTV
- Se `value_cents` for `NULL` ou `0`, não atualiza o LTV

---

## 🛠️ Funções Auxiliares

### Recalcular LTV de um cliente

Se você precisar recalcular o LTV de um cliente (para corrigir inconsistências):

```sql
SELECT func_recalculate_customer_ltv(123);  -- root_id do cliente
```

### Recalcular LTV de todos os clientes de uma inbox

```sql
SELECT func_recalculate_all_ltv_for_inbox('uuid-da-inbox');
```

**Retorna:**
```json
{
  "inbox_id": "uuid-da-inbox",
  "customers_processed": 150,
  "total_billing_cents": 1500000,
  "total_billing_reais": 15000.00,
  "recalculated_at": "2025-11-15T14:30:00Z"
}
```

---

## 📊 Exemplos de Uso

### Dashboard de Faturamento

```sql
-- Faturamento de hoje
SELECT
    (result->>'total_billing_reais')::NUMERIC as hoje,
    (result->>'completed_count')::INT as atendimentos_hoje
FROM (
    SELECT func_get_billing_today('uuid-da-inbox') as result
) sub;

-- Faturamento dos últimos 7 dias
SELECT
    (result->>'total_billing_reais')::NUMERIC as ultimos_7_dias,
    (result->>'average_ticket_reais')::NUMERIC as ticket_medio
FROM (
    SELECT func_get_billing_last_n_days('uuid-da-inbox', 7) as result
) sub;

-- Faturamento do mês atual
SELECT
    (result->>'total_billing_reais')::NUMERIC as mes_atual,
    (result->>'completed_count')::INT as atendimentos_mes
FROM (
    SELECT func_get_billing_specific_month(
        'uuid-da-inbox',
        EXTRACT(YEAR FROM NOW())::INT,
        EXTRACT(MONTH FROM NOW())::INT
    ) as result
) sub;
```

### Dashboard de Clientes (LTV)

```sql
-- Top 10 clientes
SELECT
    (customer->>'treatment_name')::TEXT as cliente,
    (customer->>'total_spent_reais')::NUMERIC as total_gasto,
    (customer->>'total_completed_appointments')::INT as atendimentos,
    (customer->>'average_ticket_reais')::NUMERIC as ticket_medio
FROM (
    SELECT jsonb_array_elements(
        func_get_top_customers_by_ltv('uuid-da-inbox', 10)
    ) as customer
) sub;
```

### Análise de Cliente Individual

```sql
-- Ver tudo sobre um cliente específico
SELECT
    treatment_name,
    total_spent_reais,
    total_completed_appointments,
    average_ticket_reais,
    customer_lifetime_days,
    first_purchase_at,
    last_purchase_at
FROM vw_customer_billing_summary
WHERE root_id = 123;
```

---

## 🔍 Queries Úteis

### Clientes com maior LTV
```sql
SELECT
    treatment_name,
    total_spent_reais,
    total_completed_appointments,
    average_ticket_reais
FROM vw_customer_billing_summary
WHERE inbox_id = 'uuid-da-inbox'
ORDER BY total_spent_cents DESC
LIMIT 10;
```

### Clientes mais frequentes
```sql
SELECT
    treatment_name,
    total_completed_appointments,
    total_spent_reais,
    average_ticket_reais
FROM vw_customer_billing_summary
WHERE inbox_id = 'uuid-da-inbox'
ORDER BY total_completed_appointments DESC
LIMIT 10;
```

### Clientes com maior ticket médio
```sql
SELECT
    treatment_name,
    average_ticket_reais,
    total_completed_appointments,
    total_spent_reais
FROM vw_customer_billing_summary
WHERE inbox_id = 'uuid-da-inbox'
  AND total_completed_appointments >= 3  -- Apenas clientes com pelo menos 3 atendimentos
ORDER BY average_ticket_cents DESC
LIMIT 10;
```

### Faturamento comparativo mês a mês
```sql
SELECT
    to_char(make_date(2025, mes, 1), 'Month YYYY') as periodo,
    (func_get_billing_specific_month('uuid-da-inbox', 2025, mes)->>'total_billing_reais')::NUMERIC as faturamento,
    (func_get_billing_specific_month('uuid-da-inbox', 2025, mes)->>'completed_count')::INT as atendimentos
FROM generate_series(1, 12) as mes
ORDER BY mes;
```

---

## 🎯 Casos de Uso

### 1. Quanto estou faturando hoje?
```sql
SELECT func_get_billing_today('uuid-da-inbox');
```

### 2. Quanto faturei nos últimos 7 dias?
```sql
SELECT func_get_billing_last_n_days('uuid-da-inbox', 7);
```

### 3. Quanto faturei em Janeiro?
```sql
SELECT func_get_billing_specific_month('uuid-da-inbox', 2025, 1);
```

### 4. Quem são meus top 10 clientes?
```sql
SELECT func_get_top_customers_by_ltv('uuid-da-inbox', 10);
```

### 5. Quanto um cliente específico já gastou?
```sql
SELECT func_get_customer_ltv(123);  -- root_id do cliente
```

### 6. Listar clientes que gastaram mais de R$ 500
```sql
SELECT
    treatment_name,
    total_spent_reais,
    total_completed_appointments
FROM vw_customer_billing_summary
WHERE total_spent_reais > 500
  AND inbox_id = 'uuid-da-inbox'
ORDER BY total_spent_reais DESC;
```

---

## ⚙️ Detalhes Técnicos

### Valores em Centavos

Todos os valores monetários são armazenados em **centavos** (INTEGER) para evitar problemas de arredondamento:

- R$ 100.00 = 10000 centavos
- R$ 50.50 = 5050 centavos
- R$ 1234.56 = 123456 centavos

As funções retornam tanto o valor em centavos quanto em reais para conveniência.

### Performance

- **Índices criados** para otimizar queries de LTV e ranking de clientes
- **Campos calculados** são armazenados (não recalculados a cada query)
- **Trigger otimizado** para evitar processamento desnecessário

### Segurança

- Todas as funções validam os parâmetros de entrada
- Transações são utilizadas para garantir consistência
- Não há risco de duplicação de valores

---

## 🧪 Testes

Execute o arquivo de testes para validar todas as funcionalidades:

```bash
psql -d seu_banco < test_billing_metrics.sql
```

Os testes cobrem:
- ✅ Trigger de LTV em INSERT
- ✅ Trigger de LTV em UPDATE
- ✅ Múltiplos clientes e atendimentos
- ✅ Funções de faturamento por tempo
- ✅ Funções de LTV por cliente
- ✅ View de resumo
- ✅ Recálculo de LTV
- ✅ Edge cases (valores nulos, zeros, duplicação)

---

## 📝 Notas Importantes

1. **Apenas atendimentos `'Completed'`** são considerados no faturamento
2. **O campo `value_cents`** deve ser preenchido pelo operador ao completar o atendimento
3. **O trigger é automático** - não é necessário atualizar o LTV manualmente
4. **Valores em centavos** evitam problemas de arredondamento
5. **Recalcular LTV** é seguro e pode ser feito a qualquer momento

---

## 🆘 Troubleshooting

### LTV não está sendo atualizado

Verifique se:
1. O trigger está criado: `\d+ "4a_customer_service_history"`
2. O status foi alterado para `'Completed'`
3. O campo `value_cents` tem um valor > 0
4. O campo `completed_at` foi preenchido

### Recalcular LTV de todos os clientes

```sql
SELECT func_recalculate_all_ltv_for_inbox('uuid-da-inbox');
```

### Ver logs do trigger

O trigger emite logs com `RAISE NOTICE`. Para ver:

```sql
SET client_min_messages TO NOTICE;
```

---

## 📚 Referências

- `schema_billing_ltv.sql` - Schema dos campos de LTV
- `functions_billing_metrics.sql` - Funções de faturamento e LTV
- `trigger_update_customer_ltv.sql` - Trigger de atualização automática
- `test_billing_metrics.sql` - Testes completos

---

**Versão:** 1.0
**Data:** 2025-11-15
**Autor:** Sistema AGES
