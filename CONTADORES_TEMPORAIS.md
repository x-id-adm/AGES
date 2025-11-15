# 📊 Contadores Temporais - Documentação

Sistema de contadores baseados em tempo para rastreamento de agendamentos e mudanças de status.

## 🎯 Objetivo

Permitir consultas como:
- "Quantos agendamentos tivemos nos últimos 7 dias?"
- "Quantos clientes cancelaram em Janeiro?"
- "Qual a taxa de conversão de agendados para confirmados no mês passado?"

---

## 🏗️ Arquitetura

### Antes (Contadores Simples)
```sql
-- Apenas totalizadores globais (desde sempre)
0b_inbox_counters:
  - scheduled_count: 150    -- Total desde sempre
  - confirmed_count: 120    -- Total desde sempre
  - cancelled_count: 30     -- Total desde sempre
```

❌ **Problema**: Não é possível saber QUANDO cada status foi aplicado.

### Depois (Contadores Temporais)
```sql
-- Cada agendamento guarda QUANDO cada status foi aplicado
4a_customer_service_history:
  - scheduled_at: '2025-01-15 10:00:00'   -- Quando foi agendado
  - confirmed_at: '2025-01-20 14:30:00'   -- Quando foi confirmado
  - cancelled_at: '2025-02-01 09:15:00'   -- Quando foi cancelado
  - completed_at: NULL                    -- Não completado ainda
```

✅ **Solução**: Timestamps específicos permitem filtros por período!

---

## 📁 Arquivos da Implementação

| Arquivo | Descrição |
|---------|-----------|
| `migration_add_status_timestamps.sql` | Adiciona colunas de timestamp à tabela de agendamentos |
| `functions.SQL` | Contém `func_set_status_timestamp()` (trigger function) |
| `triggers.SQL` | Contém `trg_set_status_timestamp` (trigger) |
| `functions_time_based_counters.sql` | Funções para consultas por período |
| `test_time_based_counters.sql` | Testes e exemplos de uso |
| `CONTADORES_TEMPORAIS.md` | Esta documentação |

---

## 🚀 Instalação

### 1. Aplicar Migration (Adiciona Colunas)
```bash
psql -d seu_banco -f migration_add_status_timestamps.sql
```

Isso irá:
- ✅ Adicionar 6 colunas de timestamp na tabela `4a_customer_service_history`
- ✅ Criar índices para performance
- ✅ Popular dados históricos (usando `created_at` como estimativa)

### 2. Aplicar Funções e Triggers
```bash
# Atualizar funções e triggers existentes
psql -d seu_banco -f functions.SQL
psql -d seu_banco -f triggers.SQL

# Adicionar novas funções de consulta por período
psql -d seu_banco -f functions_time_based_counters.sql
```

### 3. Testar (Opcional)
```bash
psql -d seu_banco -f test_time_based_counters.sql
```

---

## 📚 Como Usar

### 1️⃣ Contadores dos Últimos N Dias

```sql
-- Últimos 7 dias
SELECT func_get_counters_last_n_days('uuid-da-inbox', 7);

-- Últimos 30 dias
SELECT func_get_counters_last_n_days('uuid-da-inbox', 30);
```

**Resultado:**
```json
{
  "total_appointments": 45,
  "scheduled_count": 15,
  "confirmed_count": 20,
  "completed_count": 8,
  "cancelled_count": 2,
  "rescheduled_count": 0,
  "no_show_count": 0,
  "period": {
    "start": "2025-11-08T10:30:00Z",
    "end": "2025-11-15T10:30:00Z"
  }
}
```

---

### 2️⃣ Contadores de um Mês Específico

```sql
-- Janeiro de 2025
SELECT func_get_counters_specific_month('uuid-da-inbox', 2025, 1);

-- Fevereiro de 2025
SELECT func_get_counters_specific_month('uuid-da-inbox', 2025, 2);
```

---

### 3️⃣ Contar Status Específico em Período

```sql
-- Quantos CANCELARAM nos últimos 7 dias?
SELECT func_count_status_changes(
    'uuid-da-inbox',
    'Cancelled',
    NOW() - INTERVAL '7 days',
    NOW()
);

-- Quantos CONFIRMARAM em Janeiro?
SELECT func_count_status_changes(
    'uuid-da-inbox',
    'Confirmed',
    '2025-01-01'::TIMESTAMPTZ,
    '2025-02-01'::TIMESTAMPTZ
);
```

**Status válidos:**
- `'Scheduled'`
- `'Confirmed'`
- `'Completed'`
- `'Cancelled'`
- `'Rescheduled'`
- `'No_Show'`

---

### 4️⃣ Contadores de Período Customizado

```sql
-- Entre duas datas específicas
SELECT func_get_appointment_counters_by_period(
    'uuid-da-inbox',
    '2025-02-01 00:00:00'::TIMESTAMPTZ,  -- Início
    '2025-02-15 23:59:59'::TIMESTAMPTZ   -- Fim
);
```

---

### 5️⃣ View: Timeline de Agendamentos

```sql
-- Ver todos agendamentos com seus timestamps
SELECT * FROM vw_appointment_status_timeline
WHERE inbox_id = 'uuid-da-inbox'
ORDER BY created_at DESC
LIMIT 10;

-- Ver cancelamentos de Fevereiro
SELECT service_id, cancelled_at, service_status
FROM vw_appointment_status_timeline
WHERE cancelled_at >= '2025-02-01'
  AND cancelled_at < '2025-03-01';
```

---

## 🔍 Queries Avançadas

### Taxa de Conversão (Agendado → Confirmado)

```sql
SELECT
    COUNT(*) FILTER (WHERE confirmed_at IS NOT NULL) AS confirmados,
    COUNT(*) AS total_agendados,
    ROUND(
        COUNT(*) FILTER (WHERE confirmed_at IS NOT NULL)::DECIMAL /
        NULLIF(COUNT(*), 0) * 100,
        2
    ) AS taxa_conversao_pct
FROM "4a_customer_service_history"
WHERE inbox_id = 'uuid-da-inbox'
  AND scheduled_at >= NOW() - INTERVAL '30 days';
```

### Taxa de Cancelamento

```sql
SELECT
    COUNT(*) FILTER (WHERE cancelled_at IS NOT NULL) AS cancelados,
    COUNT(*) AS total,
    ROUND(
        COUNT(*) FILTER (WHERE cancelled_at IS NOT NULL)::DECIMAL /
        NULLIF(COUNT(*), 0) * 100,
        2
    ) AS taxa_cancelamento_pct
FROM "4a_customer_service_history"
WHERE inbox_id = 'uuid-da-inbox'
  AND created_at >= NOW() - INTERVAL '30 days';
```

### Top Dias com Mais Agendamentos

```sql
SELECT
    DATE(created_at) AS dia,
    COUNT(*) AS total_agendamentos,
    COUNT(*) FILTER (WHERE service_status = 'Confirmed') AS confirmados,
    COUNT(*) FILTER (WHERE service_status = 'Cancelled') AS cancelados
FROM "4a_customer_service_history"
WHERE inbox_id = 'uuid-da-inbox'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY DATE(created_at)
ORDER BY total_agendamentos DESC
LIMIT 10;
```

### Tempo Médio para Confirmação

```sql
SELECT
    AVG(EXTRACT(EPOCH FROM (confirmed_at - scheduled_at)) / 3600) AS horas_media
FROM "4a_customer_service_history"
WHERE inbox_id = 'uuid-da-inbox'
  AND scheduled_at IS NOT NULL
  AND confirmed_at IS NOT NULL
  AND scheduled_at >= NOW() - INTERVAL '30 days';
```

---

## 🔄 Como Funciona Automaticamente

### Quando você CRIA um agendamento:

```sql
INSERT INTO "4a_customer_service_history" (
    inbox_id,
    root_id,
    service_datetime_start,
    service_datetime_end,
    service_status  -- 'Scheduled'
) VALUES (...);
```

**Trigger automático preenche:**
```sql
scheduled_at = NOW()  -- ✅ Automaticamente!
```

### Quando você MUDA o status:

```sql
UPDATE "4a_customer_service_history"
SET service_status = 'Confirmed'
WHERE id = 123;
```

**Trigger automático preenche:**
```sql
confirmed_at = NOW()  -- ✅ Automaticamente!
-- scheduled_at permanece inalterado (histórico preservado)
```

---

## ⚡ Performance

### Índices Criados

Todos os campos de timestamp têm índices parciais para otimizar consultas:

```sql
CREATE INDEX idx_appointment_scheduled_at ON "4a_customer_service_history"(scheduled_at)
WHERE scheduled_at IS NOT NULL;

CREATE INDEX idx_appointment_confirmed_at ON "4a_customer_service_history"(confirmed_at)
WHERE confirmed_at IS NOT NULL;

-- ... (e assim por diante para todos status)
```

**Vantagem:** Queries por período são extremamente rápidas! ⚡

---

## 📊 Exemplo de Fluxo Completo

### Cenário: Agendamento que passa por vários status

```sql
-- 1. Cliente agenda (15/Jan às 10h)
INSERT INTO "4a_customer_service_history" (...)
VALUES (..., 'Scheduled', ...);
-- → scheduled_at = '2025-01-15 10:00:00'

-- 2. Cliente confirma (20/Jan às 14h30)
UPDATE "4a_customer_service_history"
SET service_status = 'Confirmed'
WHERE id = 123;
-- → confirmed_at = '2025-01-20 14:30:00'
-- → scheduled_at = '2025-01-15 10:00:00' (preservado!)

-- 3. Cliente cancela (01/Fev às 09h15)
UPDATE "4a_customer_service_history"
SET service_status = 'Cancelled'
WHERE id = 123;
-- → cancelled_at = '2025-02-01 09:15:00'
-- → confirmed_at = '2025-01-20 14:30:00' (preservado!)
-- → scheduled_at = '2025-01-15 10:00:00' (preservado!)
```

### Resultado Final:

| Campo | Valor |
|-------|-------|
| `service_status` | `'Cancelled'` |
| `scheduled_at` | `2025-01-15 10:00:00` |
| `confirmed_at` | `2025-01-20 14:30:00` |
| `cancelled_at` | `2025-02-01 09:15:00` |
| `completed_at` | `NULL` |

**Agora você pode responder:**
- ✅ Foi agendado em Janeiro? **SIM** (scheduled_at em Janeiro)
- ✅ Foi confirmado em Janeiro? **SIM** (confirmed_at em Janeiro)
- ✅ Foi cancelado em Fevereiro? **SIM** (cancelled_at em Fevereiro)

---

## 🐛 Troubleshooting

### Problema: "Column does not exist"
**Solução:** Execute a migration primeiro:
```bash
psql -d seu_banco -f migration_add_status_timestamps.sql
```

### Problema: "Function does not exist"
**Solução:** Execute os arquivos de funções:
```bash
psql -d seu_banco -f functions.SQL
psql -d seu_banco -f triggers.SQL
psql -d seu_banco -f functions_time_based_counters.sql
```

### Problema: Timestamps não preenchendo automaticamente
**Solução:** Verifique se o trigger está ativo:
```sql
SELECT * FROM information_schema.triggers
WHERE trigger_name = 'trg_set_status_timestamp';
```

---

## 📝 Notas Importantes

1. **Dados Históricos**: A migration popula timestamps de dados existentes usando `created_at` como estimativa
2. **Novos Registros**: Todos os novos agendamentos terão timestamps precisos via trigger
3. **Histórico Preservado**: Timestamps anteriores NUNCA são sobrescritos
4. **Performance**: Índices garantem queries rápidas mesmo com milhões de registros

---

## 🎓 Casos de Uso Reais

### Dashboard: KPIs dos Últimos 30 Dias
```sql
SELECT
    func_get_counters_last_n_days(inbox_id, 30)
FROM "0a_inbox_whatsapp";
```

### Relatório Mensal
```sql
SELECT
    func_get_counters_specific_month(inbox_id, 2025, 2)
FROM "0a_inbox_whatsapp";
```

### Análise de Cancelamentos
```sql
SELECT
    DATE_TRUNC('day', cancelled_at) AS dia,
    COUNT(*) AS total_cancelamentos
FROM "4a_customer_service_history"
WHERE cancelled_at >= NOW() - INTERVAL '90 days'
GROUP BY DATE_TRUNC('day', cancelled_at)
ORDER BY dia DESC;
```

---

## ✅ Checklist de Instalação

- [ ] Migration aplicada (`migration_add_status_timestamps.sql`)
- [ ] Funções atualizadas (`functions.SQL`)
- [ ] Triggers atualizados (`triggers.SQL`)
- [ ] Funções de consulta instaladas (`functions_time_based_counters.sql`)
- [ ] Testes executados com sucesso (`test_time_based_counters.sql`)

---

## 📞 Suporte

Para dúvidas ou problemas:
1. Verifique os testes em `test_time_based_counters.sql`
2. Consulte esta documentação
3. Verifique os logs do PostgreSQL para erros

---

**Desenvolvido em:** 2025-11-15
**Versão:** 1.0
**Compatível com:** PostgreSQL 12+
