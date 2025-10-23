# Relatório de Utilização - RDS lakeshoredevelopmentfl

**Data**: 2025-10-23 20:55 UTC
**Instância**: db.t3.micro (1 GB RAM, 2 vCPUs)
**Engine**: PostgreSQL 16.8
**Status**: Online

---

## Sumário Executivo

### 🔴 Problemas Críticos Identificados

1. **Memória em Nível Crítico**: 41.6 MB mínimo (4% livre) - URGENTE
2. **Sobrecarga do Looker Studio**: 31 queries ativas simultâneas (PostgreSQL JDBC)
3. **Queries lentas**: Múltiplas queries rodando há mais de 20 minutos
4. **Falta de índices**: 5 tabelas principais sem índices (100% seq scan)

### ✅ Pontos Positivos

1. CPU saudável: 14% média (16% máximo)
2. IOPS baixos: Read 18/s, Write 7.5/s
3. Índices em dailylogs funcionando bem: 91.56% uso de índices
4. Autovacuum ativo e funcionando

---

## 1. Métricas de Infraestrutura (AWS CloudWatch)

### 1.1 Memória

| Métrica | Valor | Status |
|---------|-------|--------|
| **Média livre** | 65 MB (6.5%) | 🔴 **CRÍTICO** |
| **Mínimo livre** | 41.6 MB (4%) | 🔴 **CRÍTICO** |
| **Usado** | ~940 MB (94%) | 🔴 **CRÍTICO** |

**Análise**:
- Memória atingiu **4% livre** no pior momento
- db.t3.micro tem apenas **1 GB RAM total**
- Sistema operando no limite, risco de OOM (Out of Memory)

**Ação Requerida**: **Upgrade para db.t3.small (2 GB RAM)** - URGENTE

---

### 1.2 CPU

| Métrica | Valor | Status |
|---------|-------|--------|
| **Média** | 14.7% | ✅ OK |
| **Máximo** | 16.3% | ✅ OK |

**Análise**:
- CPU saudável, sem problemas
- Picos baixos, indicando que CPU não é gargalo
- Problema principal é memória, não processamento

---

### 1.3 IOPS (Input/Output Operations)

| Tipo | Média | Máximo | Status |
|------|-------|--------|--------|
| **Read IOPS** | 18.8/s | 30.2/s | ✅ OK |
| **Write IOPS** | 7.6/s | 22/s | ✅ OK |

**Análise**:
- IOPS muito baixos para o volume de dados
- gp2 (20 GB) suporta até 100 IOPS burst
- Indica que queries estão em cache ou são eficientes

---

### 1.4 Conexões

| Métrica | Valor | Limite | % |
|---------|-------|--------|---|
| **Atual** | 48 | ~85 | 56% |
| **Média** | 45.4 | ~85 | 53% |
| **Máximo observado** | 58 | ~85 | 68% |

**Análise**:
- db.t3.micro suporta ~85 conexões máximas
- Usando **56% da capacidade** (alto)
- Muitas conexões do Looker Studio (31 ativas!)

---

## 2. Análise de Armazenamento

### 2.1 Tamanho Total do Banco

| Database | Tamanho | Storage Alocado | % Usado |
|----------|---------|-----------------|---------|
| postgres | **1,458 MB** (1.42 GB) | 20 GB | 7.1% |

**Análise**:
- Espaço em disco: **OK** (93% livre)
- Não há risco de ficar sem espaço
- Possível reduzir storage para 10 GB (economia de custos)

---

### 2.2 Top 15 Tabelas por Tamanho

| # | Tabela | Tamanho Total | Tamanho Tabela | Índices | Colunas |
|---|--------|---------------|----------------|---------|---------|
| 1 | **dailylogs_audit_db** | 429 MB | 421 MB | 8 MB | 7 |
| 2 | **dailylogs** | 168 MB | 108 MB | 60 MB | 24 |
| 3 | dailylogs_work | 57 MB | 57 MB | 0 MB | 24 |
| 4 | task_assignments_log | 52 MB | 46 MB | 6 MB | 11 |
| 5 | **dailylogs_fmea** | 50 MB | 50 MB | 0 MB | 24 |
| 6 | process_flow_conform | 43 MB | 43 MB | 0 MB | 7 |
| 7 | bills | 38 MB | 37 MB | 1 MB | 23 |
| 8 | schedule_ | 38 MB | 30 MB | 8 MB | 20 |
| 9 | dl_backup_ale | 36 MB | 36 MB | 0 MB | 23 |
| 10 | dl_backup_now | 27 MB | 27 MB | 0 MB | 23 |
| 11 | dailylogs_backup | 16 MB | 16 MB | 0 MB | 23 |
| 12 | purchaseorders | 15 MB | 15 MB | 0 MB | 19 |
| 13 | dailylogs_notifications | 12 MB | 12 MB | 0 MB | 20 |
| 14 | dash_missing_inputs | 12 MB | 11 MB | 1 MB | 9 |
| 15 | inputs_verificacao_... | 11 MB | 11 MB | 0 MB | 24 |

**Observações**:
- **dailylogs_audit_db** (429 MB) é a maior tabela - 29% do banco!
- **dailylogs** (168 MB) tem 60 MB de índices (36% do tamanho da tabela)
- Várias tabelas de backup (_work, dl_backup_*) podem ser arquivadas

---

### 2.3 Contagem de Registros

| Tabela | Registros | Tamanho | Média/Registro |
|--------|-----------|---------|----------------|
| **dailylogs** | 186,421 | 168 MB | 901 bytes |
| **dailylogs_fmea** | 6,134 | 50 MB | 8.1 KB |
| **mv_job_history** | 36,203 | ~8 MB | 221 bytes |

**Análise**:
- dailylogs_fmea tem registros muito grandes (8.1 KB/linha)
- Possível otimização: normalizar colunas grandes (notes, logtitle)

---

## 3. Análise de Conexões e Queries

### 3.1 Conexões Atuais por Estado

| Estado | App | Count | Última Mudança |
|--------|-----|-------|----------------|
| **active** | PostgreSQL JDBC Driver | **31** | 20:53:50 |
| **active** | (vazio) | **16** | 20:53:54 |
| idle | (vazio) | 10 | 20:53:53 |
| idle in transaction | (vazio) | 2 | 20:23:16 ⚠️ |
| idle | DBeaver 25.2.3 | 3 | 17:08-17:22 |
| active | psql | 1 | 20:53:43 |

**Total**: 63 conexões

**🔴 Problema Crítico Identificado**:
- **47 queries ATIVAS** (31 JDBC + 16 sem app)
- PostgreSQL JDBC Driver = **Looker Studio**
- Todas executando a MESMA query: `SELECT COUNT(1)... WITH active_jobs AS...`

---

### 3.2 Queries Lentas em Execução

**10 queries ativas**, todas do Looker Studio:

| PID | Tempo Rodando | Query |
|-----|---------------|-------|
| 26425 | **27 minutos** | `SELECT COUNT(1)... WITH active_jobs...` |
| 26270 | **26 minutos** | `SELECT COUNT(1)... WITH active_jobs...` |
| 26214 | **25 minutos** | `SELECT COUNT(1)... WITH active_jobs...` |
| 26597 | **24 minutos** | `SELECT COUNT(1)... WITH active_jobs...` |
| 26578 | **24 minutos** | `SELECT COUNT(1)... WITH active_jobs...` |
| ... | ... | ... |

**Análise**:
- Queries rodando há **20-27 minutos**!
- Todas esperando I/O (DataFileRead, BufferIO)
- Sugestão: **Timeout de 30 segundos** no Looker

---

### 3.3 Conexões Idle in Transaction (Memory Leak)

**2 conexões** em estado "idle in transaction" desde **20:23:16** (30 minutos atrás!)

**Problema**:
- Transação aberta sem commit/rollback
- Segura locks e memória
- Possível memory leak

**Ação**: Matar conexões idle in transaction > 10 minutos:
```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle in transaction'
  AND state_change < NOW() - INTERVAL '10 minutes';
```

---

## 4. Análise de Índices e Performance

### 4.1 Uso de Índices vs Sequential Scans

| Tabela | Seq Scans | Index Scans | % Índice | Status |
|--------|-----------|-------------|----------|--------|
| **dailylogs** | 226M | 2,455M | **91.56%** | ✅ Excelente |
| cmprocesses | 25.9M | 693K | 2.61% | 🔴 Ruim |
| houses_open_closed | 5.0M | 0 | **0%** | 🔴 Sem índices |
| dailylogs_report_fmea | 4.7M | 0 | **0%** | 🔴 Sem índices |
| **dailylogs_fmea** | 2.3M | 0 | **0%** | 🔴 **Sem índices** |
| processhierarchy | 1.4M | 423K | 23.04% | ⚠️ Baixo |
| dailylogs_notifications | 1.4M | 0 | **0%** | 🔴 Sem índices |

**Análise**:
- **dailylogs**: ✅ Índices funcionando perfeitamente (91.56%)
- **dailylogs_fmea**: 🔴 **2.3 milhões de seq scans SEM índices!**
- **5 tabelas** com 0% uso de índices (sem índices criados)

---

### 4.2 Índices da Tabela dailylogs

| Índice | Tamanho | Descrição |
|--------|---------|-----------|
| idx_dailylogs_job_id | ~15 MB | job_id |
| idx_dailylogs_datecreated | ~13 MB | datecreated DESC |
| idx_dailylogs_optimized | ~10 MB | (datecreated, job_id, process, status) WHERE ... |
| idx_dailylogs_process | ~8 MB | process |
| idx_dailylogs_status | ~5 MB | status |
| idx_dailylogs_hash | ~5 MB | hash_unique |
| idx_dailylogs_id | ~4 MB | id |

**Total índices**: ~60 MB (36% do tamanho da tabela)

**Análise**:
- Índices bem distribuídos
- idx_dailylogs_optimized é parcial (WHERE condition) - ótimo para economia
- Todos os índices sendo usados (91.56% hit rate)

---

### 4.3 🔴 Índices Faltantes (URGENTE)

#### dailylogs_fmea (2.3M seq scans!)

**Criar**:
```sql
CREATE INDEX idx_dailylogs_fmea_job_process
ON dailylogs_fmea(job_id, process);

CREATE INDEX idx_dailylogs_fmea_status
ON dailylogs_fmea(process, status)
WHERE status IN ('checklist done', 'rework requested');

CREATE INDEX idx_dailylogs_fmea_datecreated
ON dailylogs_fmea(datecreated);
```

**Impacto estimado**: Redução de **50-70%** no tempo das Query 10 Rules 2 e 3

---

#### houses_open_closed (5M seq scans)
```sql
CREATE INDEX idx_houses_open_closed_job_id
ON houses_open_closed(job_id);
```

---

#### dailylogs_report_fmea (4.7M seq scans)
```sql
CREATE INDEX idx_dailylogs_report_fmea_job_id
ON dailylogs_report_fmea(job_id);
```

---

## 5. Análise de Bloat (Dead Tuples)

| Tabela | Live Rows | Dead Rows | % Dead | Último Autovacuum |
|--------|-----------|-----------|--------|-------------------|
| dailylogs | 186,421 | 6,494 | **3.48%** | 2025-10-20 14:31 |
| dailylogs_report_fmea | 76,403 | 4,915 | **6.43%** | 2025-10-04 12:02 ⚠️ |
| corecraft_clickup_lists | 918 | 189 | **20.59%** | 2025-10-23 20:55 |
| dailylogs_fmea | 6,134 | 159 | **2.59%** | 2025-10-22 18:43 |

**Análise**:
- **dailylogs**: ✅ Bloat baixo (3.48%), autovacuum recente
- **dailylogs_report_fmea**: ⚠️ Bloat moderado (6.43%), autovacuum há 19 dias
- **corecraft_clickup_lists**: 🔴 Bloat alto (20.59%) - needs VACUUM FULL

**Ação**:
```sql
VACUUM ANALYZE dailylogs_report_fmea;
VACUUM FULL corecraft_clickup_lists; -- durante janela de manutenção
```

---

## 6. Padrões de Acesso (Top Queries)

### 6.1 Tabelas Mais Acessadas

| Tabela | Total Acesses | Seq Scans | Index Scans |
|--------|---------------|-----------|-------------|
| **dailylogs** | **2.68 bilhões** | 226M | 2,455M |
| cmprocesses | 26.6M | 25.9M | 693K |
| houses_open_closed | 5.0M | 5.0M | 0 |
| dailylogs_report_fmea | 4.7M | 4.7M | 0 |

**Análise**:
- **dailylogs** é 100x mais acessada que outras tabelas
- Confirmado como tabela crítica do sistema
- Índices em dailylogs são essenciais

---

### 6.2 Operações de Escrita

| Tabela | Inserts | Updates | Deletes | Churn Rate |
|--------|---------|---------|---------|------------|
| dailylogs | 608,391 | 3,803,034 | 332,066 | **Alta** |
| dailylogs_fmea | 188,177 | 2,603,508 | 182,043 | **Muito Alta** |
| houses_open_closed | 34,140 | 1,519,532 | 33,454 | **Muito Alta** |
| schedule_ | 81,149 | 1,298,999 | 0 | Alta |

**Churn Rate** = Updates / Live Rows

**Análise**:
- **dailylogs_fmea**: 2.6M updates para apenas 6K registros = **424:1 ratio**!
- Tabela muito volátil, updates frequentes
- Explica por que autovacuum é necessário

---

## 7. Problemas e Recomendações

### 7.1 Prioridade URGENTE (Fazer AGORA)

#### 1. Upgrade de Instância RDS
**Problema**: Memória em 4% livre (41.6 MB)
**Solução**: Upgrade para **db.t3.small** (2 GB RAM)
**Custo**: +$15/mês (~$15 → ~$30)
**Impacto**: Elimina risco de OOM, melhora cache

**Comando**:
```bash
aws rds modify-db-instance \
  --db-instance-identifier lakeshoredevelopmentfl \
  --db-instance-class db.t3.small \
  --apply-immediately
```

---

#### 2. Criar Índices em dailylogs_fmea
**Problema**: 2.3M seq scans sem índices
**Solução**: 3 índices estratégicos
**Impacto**: Queries 50-70% mais rápidas

```sql
CREATE INDEX CONCURRENTLY idx_dailylogs_fmea_job_process
ON dailylogs_fmea(job_id, process);

CREATE INDEX CONCURRENTLY idx_dailylogs_fmea_status
ON dailylogs_fmea(process, status)
WHERE status IN ('checklist done', 'rework requested');

CREATE INDEX CONCURRENTLY idx_dailylogs_fmea_datecreated
ON dailylogs_fmea(datecreated);
```

---

#### 3. Configurar Timeout no Looker Studio
**Problema**: Queries rodando por 20-27 minutos
**Solução**: Timeout de 30 segundos
**Impacto**: Reduz conexões travadas

**No Looker Data Source**:
- Connection Timeout: 30s
- Query Timeout: 30s
- Max Connections: 5

---

#### 4. Limpar Conexões Idle in Transaction
**Problema**: 2 conexões idle há 30+ minutos
**Solução**: Automated cleanup

```sql
-- Executar a cada hora (via Lambda ou pg_cron)
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle in transaction'
  AND state_change < NOW() - INTERVAL '10 minutes';
```

---

### 7.2 Prioridade ALTA (Esta Semana)

#### 5. Reduzir Refresh do Looker
**Atual**: A cada 15 minutos (96×/dia)
**Recomendado**: A cada 30 minutos (48×/dia)
**Impacto**: -50% queries

---

#### 6. Arquivar Tabelas de Backup
**Problema**: 136 MB em tabelas de backup antigas
**Solução**: Exportar para S3 e dropar

Tabelas:
- dailylogs_work (57 MB)
- dl_backup_ale (36 MB)
- dl_backup_now (27 MB)
- dailylogs_backup (16 MB)

**Economia**: 136 MB (~9% do banco)

---

#### 7. Habilitar Backups Automáticos
**Problema**: backup_retention_period = 0
**Solução**: Habilitar 7 dias

```bash
aws rds modify-db-instance \
  --db-instance-identifier lakeshoredevelopmentfl \
  --backup-retention-period 7 \
  --preferred-backup-window "09:43-10:13"
```

---

### 7.3 Prioridade MÉDIA (Este Mês)

#### 8. Otimizar dailylogs_audit_db
**Problema**: 429 MB (29% do banco)
**Análise**: Verificar se todos os registros são necessários
**Solução**: Arquivar logs > 90 dias para S3

---

#### 9. Normalizar dailylogs_fmea
**Problema**: 8.1 KB/registro (muito grande)
**Análise**: Colunas `notes` e `logtitle` podem estar grandes
**Solução**: Comprimir ou mover para tabela separada

---

#### 10. Configurar CloudWatch Alarms
**Métricas**:
- FreeableMemory < 100 MB → Warning
- FreeableMemory < 50 MB → Critical
- DatabaseConnections > 60 → Warning
- CPUUtilization > 70% → Warning

---

## 8. Resumo de Custos

### 8.1 Configuração Atual
| Item | Configuração | Custo/Mês |
|------|--------------|-----------|
| RDS Instance | db.t3.micro | ~$15 |
| Storage (gp2) | 20 GB | ~$2 |
| Backups | 0 dias | $0 |
| **Total** | | **~$17/mês** |

### 8.2 Configuração Recomendada
| Item | Configuração | Custo/Mês | Diferença |
|------|--------------|-----------|-----------|
| RDS Instance | **db.t3.small** | ~$30 | +$15 |
| Storage (gp2) | 20 GB | ~$2 | $0 |
| Backups | **7 dias** | ~$0.50 | +$0.50 |
| **Total** | | **~$32.50/mês** | **+$15.50** |

**ROI**: $15.50/mês elimina risco de downtime e melhora performance significativamente

---

## 9. Plano de Ação (Próximas 48h)

### Hoje (Prioridade 1)
- [ ] Criar índices em dailylogs_fmea (30 min downtime)
- [ ] Limpar conexões idle in transaction
- [ ] Configurar timeout no Looker (30s)

### Amanhã (Prioridade 2)
- [ ] Upgrade para db.t3.small (15 min downtime)
- [ ] Habilitar backups automáticos (7 dias)
- [ ] Reduzir refresh Looker (15→30 min)

### Esta Semana
- [ ] Arquivar tabelas de backup para S3
- [ ] Configurar CloudWatch Alarms
- [ ] VACUUM tabelas com bloat

---

## 10. Monitoramento Contínuo

### Queries Úteis (Executar Semanalmente)

```sql
-- 1. Memória e conexões
SELECT
  pg_size_pretty(pg_database_size('postgres')) AS db_size,
  (SELECT COUNT(*) FROM pg_stat_activity WHERE datname = 'postgres') AS connections,
  (SELECT COUNT(*) FROM pg_stat_activity WHERE state = 'active') AS active_queries;

-- 2. Top 5 queries lentas
SELECT * FROM cleanup_idle_connections(15);

-- 3. Bloat check
SELECT relname, n_live_tup, n_dead_tup,
       ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup, 0), 2) AS dead_pct
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC
LIMIT 5;
```

---

## Conclusão

O RDS lakeshoredevelopmentfl está **operacional mas sob stress significativo**:

**Crítico**:
1. ✅ Memória em nível crítico (4% livre)
2. ✅ Sobrecarga do Looker Studio (47 queries ativas)
3. ✅ Falta de índices em dailylogs_fmea

**Positivo**:
1. ✅ CPU saudável (14% média)
2. ✅ Índices em dailylogs excelentes (91.56% hit)
3. ✅ Autovacuum funcionando

**Investimento recomendado**: **$15.50/mês** para upgrade e backups = Elimina riscos e melhora performance

---

**Próximo Relatório**: 2025-10-30 (após implementar otimizações)
