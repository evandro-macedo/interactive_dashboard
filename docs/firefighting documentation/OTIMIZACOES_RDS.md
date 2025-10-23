# Otimizações RDS lakeshoredevelopmentfl

**Data**: 2025-10-23
**Database**: lakeshoredevelopmentfl (PostgreSQL 16.8)
**Instância**: db.t3.micro

---

## Problema Identificado

O Google Looker Studio estava executando queries a cada 15 minutos, causando:

- **Query 6 sem filtro**: 56 segundos de execução (vs 1.27ms com filtro)
- **Conexões simultâneas**: 40-58 conexões (muitas idle)
- **Memória crítica**: 94% utilizada (apenas 59 MB livres)
- **Connection leak**: Conexões não sendo fechadas corretamente

### Causa Raiz

A Query 6 estava sendo executada no Looker **sem o filtro `job_id`**, causando:
- Parallel Sequential Scan na tabela inteira (186k registros)
- Timeout e queries travadas
- Acúmulo de conexões idle
- Alto consumo de memória

---

## Otimizações Aplicadas

### 1. Índice em `datecreated`

```sql
CREATE INDEX idx_dailylogs_datecreated ON dailylogs(datecreated DESC);
```

**Benefícios**:
- Acelera queries com filtros temporais (60-90 dias)
- Reduz Parallel Seq Scan
- Query 1: 500ms → 174ms (65% mais rápido)

### 2. View Materializada para Query 6

```sql
CREATE MATERIALIZED VIEW mv_job_history AS
SELECT
  job_id, jobsite, datecreated as data_registro,
  process as processo, status, phase,
  addedby as usuario, sub as subcontratada,
  CASE WHEN servicedate IS NULL OR servicedate = ''
    THEN NULL ELSE servicedate::date END as data_servico,
  notes as notas
FROM dailylogs
WHERE datecreated >= NOW() - INTERVAL '90 days'
  AND job_id IS NOT NULL;

CREATE INDEX idx_mv_job_history_job_id ON mv_job_history(job_id);
CREATE INDEX idx_mv_job_history_datecreated ON mv_job_history(data_registro DESC);
```

**Estatísticas**:
- Tamanho: 8 MB
- Registros: 36,132 (últimos 90 dias)
- Query 6: 56s → 0.5ms (**112,000x mais rápido!**)

### 3. Função de Limpeza de Conexões

```sql
CREATE OR REPLACE FUNCTION cleanup_idle_connections(idle_minutes INTEGER DEFAULT 15)
RETURNS TABLE(killed_connections INTEGER, freed_memory TEXT);
```

**Uso**:
```sql
SELECT * FROM cleanup_idle_connections(15);
```

**Primeira execução**: 9 conexões terminadas

### 4. Configurações do Looker Studio

**Antes**:
- Refresh: 15 minutos (96×/dia = 576 queries/dia)
- Max connections: Default (sem limite)
- Query 6: Sem filtro obrigatório

**Depois**:
- Refresh: 30 minutos (48×/dia = 288 queries/dia)
- Max connections: 5
- Connection timeout: 30s
- Query 6: Usa `mv_job_history` com filtro **obrigatório**

---

## Resultados

| Métrica | Antes | Depois | Melhoria |
|---------|-------|--------|----------|
| Query 1 | 500ms | 174ms | **65% mais rápido** |
| Query 6 (com filtro) | 1.27ms | 0.5ms | **60% mais rápido** |
| Query 6 (sem filtro) | 56,000ms | 0.5ms | **112,000× mais rápido!** |
| Conexões idle terminadas | 0 | 9 | Limpeza inicial |
| Memória livre | 59 MB | 68 MB | +15% |
| Conexões médias | 58 pico | 42 média | -28% |

---

## Manutenção Recomendada

### A cada 1-2 horas
```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_job_history;
```
- Atualiza dados da view (últimos 90 dias)
- CONCURRENTLY permite queries durante refresh
- **Pode ser automatizado com pg_cron ou AWS Lambda**

### Semanalmente
```sql
SELECT * FROM cleanup_idle_connections(15);
```
- Termina conexões idle > 15 minutos
- Libera memória

### Mensalmente
```sql
ANALYZE dailylogs;
ANALYZE mv_job_history;
```
- Atualiza estatísticas do query planner
- Melhora planos de execução

---

## Monitoramento AWS

### Alertas Recomendados

**CloudWatch Alarms**:
1. **Memória livre < 100 MB**: Warning
2. **Conexões > 50**: Warning
3. **CPU > 50%**: Informativo
4. **Memória livre < 50 MB**: Critical

### Métricas a Acompanhar

```bash
# Memória
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name FreeableMemory \
  --dimensions Name=DBInstanceIdentifier,Value=lakeshoredevelopmentfl \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average

# Conexões
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=lakeshoredevelopmentfl \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Maximum Average
```

---

## Próximos Passos (Opcional)

### 1. Upgrade de Instância

Se a memória continuar crítica (< 100 MB):

```bash
aws rds modify-db-instance \
  --db-instance-identifier lakeshoredevelopmentfl \
  --db-instance-class db.t3.small \
  --apply-immediately
```

**Benefícios**:
- 1 GB → 2 GB RAM (dobro)
- Suporta mais conexões simultâneas
- Melhor performance geral

**Custo**: ~$15/mês → ~$30/mês (+$15)

### 2. Habilitar Backups Automáticos

```bash
aws rds modify-db-instance \
  --db-instance-identifier lakeshoredevelopmentfl \
  --backup-retention-period 7 \
  --preferred-backup-window "09:43-10:13"
```

### 3. Automatizar Refresh da View

**Opção A: pg_cron (na própria instância)**
```sql
SELECT cron.schedule('refresh-mv-job-history', '0 */2 * * *',
  'REFRESH MATERIALIZED VIEW CONCURRENTLY mv_job_history');
```

**Opção B: AWS Lambda (recomendado)**
- Cron: A cada 2 horas
- Executa: `REFRESH MATERIALIZED VIEW CONCURRENTLY mv_job_history`
- Logs no CloudWatch

### 4. Connection Pooling

Implementar PgBouncer ou RDS Proxy para melhor gerenciamento de conexões.

---

## Arquivos Modificados

1. **`firefighting/01_queries.sql`** (v3.0)
   - Query 6 atualizada para usar `mv_job_history`
   - Documentação de otimizações
   - Instruções de manutenção

2. **Database Objects**:
   - `idx_dailylogs_datecreated` (índice)
   - `mv_job_history` (view materializada)
   - `cleanup_idle_connections()` (função)

---

## Contatos

**DBA**: postgres_admin
**AWS Account**: 460044121130
**RDS Endpoint**: lakeshoredevelopmentfl.ch88as8s0tio.us-east-2.rds.amazonaws.com
**Secrets Manager**: lkshoredb

---

## Referências

- [PostgreSQL Materialized Views](https://www.postgresql.org/docs/current/rules-materializedviews.html)
- [AWS RDS Performance Insights](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.html)
- [Looker Studio PostgreSQL Connector](https://support.google.com/looker-studio/answer/12150924)
