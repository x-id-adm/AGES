# Taxas de Conversão - Documentação

## Visão Geral

O sistema calcula automaticamente as taxas de conversão baseadas nos contadores de status de agendamentos. As taxas são atualizadas **em tempo real** sempre que um agendamento muda de status.

## Tabela: `0b_inbox_counters`

### Contadores de Status

| Campo | Tipo | Descrição | Mudado Por |
|-------|------|-----------|------------|
| `scheduled_count` | INT | Total de agendamentos com status "Scheduled" | Agente de IA |
| `confirmed_count` | INT | Total de agendamentos com status "Confirmed" | Agente de IA |
| `completed_count` | INT | Total de agendamentos com status "Completed" | Humano |
| `cancelled_count` | INT | Total de agendamentos com status "Cancelled" | Humano/IA |
| `rescheduled_count` | INT | Total de agendamentos com status "Rescheduled" | Humano |
| `no_show_count` | INT | Total de agendamentos com status "No_Show" | Humano |

### Taxas de Conversão (Calculadas Automaticamente)

| Campo | Tipo | Fórmula | Exemplo |
|-------|------|---------|---------|
| `confirmed_rate` | DECIMAL(5,4) | `confirmed_count / scheduled_count` | 0.8500 (85%) |
| `completed_rate` | DECIMAL(5,4) | `completed_count / scheduled_count` | 0.7500 (75%) |
| `cancelled_rate` | DECIMAL(5,4) | `cancelled_count / scheduled_count` | 0.1000 (10%) |
| `rescheduled_rate` | DECIMAL(5,4) | `rescheduled_count / scheduled_count` | 0.0500 (5%) |
| `no_show_rate` | DECIMAL(5,4) | `no_show_count / scheduled_count` | 0.0500 (5%) |

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

Quando não há agendamentos (`scheduled_count = 0`), todas as taxas retornam `0.0000`:

```sql
CASE
    WHEN scheduled_count > 0
    THEN ROUND(confirmed_count::DECIMAL / scheduled_count, 4)
    ELSE 0
END
```

## Exemplos de Uso

### Consultar Taxas de uma Inbox

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

## Métricas de Negócio

### Taxa de Conversão Ideal

| Métrica | Meta Recomendada | Crítico |
|---------|------------------|---------|
| Taxa de Confirmação | > 80% | < 60% |
| Taxa de Conclusão | > 70% | < 50% |
| Taxa de Cancelamento | < 10% | > 20% |
| Taxa de No-Show | < 5% | > 15% |

### Interpretação das Taxas

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

### 2025-11-15
- ✨ Adicionadas colunas de taxa de conversão automática
- ✨ Criados testes de validação
- 📝 Documentação criada

### 2025-11-14
- ✨ Implementados contadores de status de agendamentos
- ✨ Criado trigger para atualização automática dos contadores

## Referências

- **Schema**: `schema.sql` (linhas 96-112)
- **Testes**: `test_conversion_rates.sql`
- **Trigger relacionado**: `func_update_appointment_status_counter()` em `functions.SQL`
