# Especificações Técnicas - Queries de Pendências por Phase

**Data Criação:** 2025-10-23
**Última Atualização:** 2025-10-23
**Versão:** 3.1 (em desenvolvimento)
**Status:** Aguardando Upgrade RDS

---

## 📊 Visão Geral do Projeto

### Objetivo
Criar queries SQL para identificar problemas/pendências em casas ativas, organizadas por phase, para dashboard no Google Looker Studio com refresh a cada 5 minutos.

### Escopo
- **6 queries novas** (Queries 7-12): 3 categorias × 2 níveis (resumo + detalhado)
- **Integração** com queries existentes (1-6)
- **Performance alvo:** < 25 segundos por query
- **Compatibilidade:** Google Looker Studio (snake_case, sem Unicode)

---

## 🗂️ Estrutura das Queries

### Queries Existentes (v3.0)
| Query | Descrição | Performance Atual |
|-------|-----------|-------------------|
| Query 1 | Resumo de casas por phase | 174ms ✅ |
| Query 2 | Lista detalhada por phase | ~800ms ✅ |
| Query 3 | Total de casas ativas | ~300ms ✅ |
| Query 4 | Jobs finalizados | ~200ms ✅ |
| Query 5 | Lista individual (Looker) | ~800ms ✅ |
| Query 6 | Histórico por casa | 0.5ms (mat view) ✅ |

### Queries Novas (v3.1)
| Query | Categoria | Tipo | Performance Atual | Meta |
|-------|-----------|------|-------------------|------|
| Query 7 | Inspeções Reprovadas | Resumo | 88s ⚠️ | < 25s |
| Query 8 | Inspeções Reprovadas | Detalhado | Não testada | < 30s |
| Query 9 | Reports Pendentes | Resumo | Não testada | < 20s |
| Query 10 | Reports Pendentes | Detalhado | Não testada | < 25s |
| Query 11 | Scheduled Aberto | Resumo | Não testada | < 20s |
| Query 12 | Scheduled Aberto | Detalhado | Não testada | < 30s |

---

## 🔍 Especificações Detalhadas por Query

### Query 7: Inspeções Reprovadas - Resumo

**Propósito:** Contar quantas casas têm inspeções reprovadas ativas por phase

**Lógica de Negócio:**
- Filtrar processos com `process LIKE '%inspection%'`
- Status = `'inspection disapproved'`
- Excluir se existe `'inspection approved'` mais recente para o mesmo job+process
- Agrupar por phase atual da casa

**Colunas Retornadas:**
```sql
phase_atual              -- Phase 0, Phase 1, etc.
total_casas              -- Contagem distinct de job_id
total_inspections_reprovadas  -- Contagem total (pode ser > total_casas)
percentual               -- Percentual sobre total de casas ativas
```

**Performance:**
- **Atual:** 88 segundos (RDS 1GB, sem índices)
- **Meta:** < 25 segundos
- **Resultado Teste:** 24 casas com inspeções reprovadas (Phase 2: 5, Phase 3: 11, Phase 4: 8)

**Índices Necessários:**
- `idx_dailylogs_process_pattern` - Para LIKE '%inspection%'
- `idx_dailylogs_status` - Para filtro de status
- `idx_dailylogs_job_process_date` - Para JOIN job+process

---

### Query 8: Inspeções Reprovadas - Detalhado

**Propósito:** Listar cada inspeção reprovada ativa com detalhes

**Colunas Retornadas:**
```sql
phase_atual              -- Phase da casa
job_id                   -- ID da casa
jobsite                  -- Nome da casa
processo_inspecao        -- Nome do processo de inspeção
data_reprovacao          -- Quando foi reprovada
dias_em_aberto          -- Dias desde a reprovação
ultimo_status           -- Último status do processo
data_ultimo_status      -- Data do último status
```

**Ordenação:** Por phase, depois por dias_em_aberto DESC (mais antigas primeiro)

**Performance Meta:** < 30 segundos

---

### Query 9: Reports sem Checklist Done - Resumo

**Propósito:** Contar quantas casas têm reports pendentes por phase

**Lógica de Negócio:**
- Filtrar registros com `status = 'report'`
- Excluir se existe `status = 'checklist done'` cronologicamente posterior
- Agrupar por phase

**Colunas Retornadas:**
```sql
phase_atual              -- Phase da casa
total_casas              -- Contagem distinct de job_id
total_reports_pendentes  -- Contagem total de reports
percentual               -- Percentual sobre total ativo
```

**Performance Meta:** < 20 segundos

---

### Query 10: Reports sem Checklist Done - Detalhado

**Propósito:** Listar cada report pendente com regras de negócio complexas

**Lógica de Negócio (REGRAS FMEA):**

**REGRA 0: Exclusão por FMEA not_report**
```sql
-- Excluir se processo+status está marcado como not_report na tabela FMEA
WHERE NOT EXISTS (
  SELECT 1 FROM dailylogs_fmea
  WHERE process = prd.process
    AND status = prd.status
    AND not_report = TRUE
)
```

**REGRA 1: Rework Scheduled Posterior**
```sql
-- Excluir se existe 'rework scheduled' APÓS o report
WHERE NOT EXISTS (
  SELECT 1 FROM dailylogs
  WHERE job_id = prd.job_id
    AND process = prd.process
    AND status = 'rework scheduled'
    AND datecreated > prd.report_date
)
```

**REGRA 2: Checklist Done com FMEA**
```sql
-- Excluir se existe 'checklist done' com FMEA APÓS o report
WHERE NOT EXISTS (
  SELECT 1 FROM dailylogs_fmea
  WHERE job_id = prd.job_id
    AND process = prd.process
    AND status = 'checklist done'
    AND failure_group ILIKE '%fmea%'
    AND datecreated::timestamp > prd.report_date
)
```

**REGRA 3: Rework Requested com FMEA**
```sql
-- Excluir se existe 'rework requested' com FMEA APÓS o report
WHERE NOT EXISTS (
  SELECT 1 FROM dailylogs_fmea
  WHERE job_id = prd.job_id
    AND process = prd.process
    AND status = 'rework requested'
    AND failure_group ILIKE '%fmea%'
    AND datecreated::timestamp > prd.report_date
)
```

**REGRA 4: In Progress Posterior**
```sql
-- Excluir se existe 'in progress' APÓS o report
WHERE NOT EXISTS (
  SELECT 1 FROM dailylogs
  WHERE job_id = prd.job_id
    AND process = prd.process
    AND status = 'in progress'
    AND datecreated > prd.report_date
)
```

**Colunas Retornadas:**
```sql
phase_atual              -- Phase da casa
job_id                   -- ID da casa
jobsite                  -- Nome da casa
processo                 -- Nome do processo
data_report              -- Data do report
dias_pendente           -- Dias desde o report
tem_checklist_done_anterior  -- Boolean (teve checklist antes?)
```

**Tabelas Utilizadas:**
- `dailylogs` - Tabela principal
- `dailylogs_fmea` - Tabela de FMEA (Failure Mode and Effects Analysis)

**Performance Meta:** < 25 segundos

**Complexidade:** ALTA (5 subqueries NOT EXISTS)

---

### Query 11: Scheduled sem Checklist Done - Resumo

**Propósito:** Contar quantos processos scheduled estão abertos por phase

**Lógica de Negócio:**
- Filtrar registros com `status = 'scheduled'`
- Verificar se NÃO existe `status = 'checklist done'` para o mesmo job+process
- Agrupar por phase

**Colunas Retornadas:**
```sql
phase_atual              -- Phase da casa
total_casas              -- Contagem distinct de job_id
total_items_scheduled_abertos  -- Contagem de items
percentual               -- Percentual sobre total ativo
```

**Performance Meta:** < 20 segundos

---

### Query 12: Scheduled sem Checklist Done - Detalhado

**Propósito:** Listar cada scheduled aberto com status atual do item

**Lógica de Negócio:**
- Buscar processos com `status = 'scheduled'` sem `'checklist done'`
- Retornar o último status APÓS o scheduled (status atual do item)

**Colunas Retornadas:**
```sql
phase_atual              -- Phase da casa
job_id                   -- ID da casa
jobsite                  -- Nome da casa
processo                 -- Nome do processo
data_scheduled          -- Quando foi scheduled
status_atual_do_item    -- Último status após scheduled
data_ultimo_status      -- Data do último status
dias_em_aberto          -- Dias desde scheduled
```

**Ordenação:** Por phase, depois por dias_em_aberto DESC

**Performance Meta:** < 30 segundos

---

## 🏗️ Infraestrutura

### RDS Atual (db.t3.micro)
```
RAM: 1 GB
vCPUs: 2
Storage: [verificar]
Custo: ~$15/mês
Status: NO LIMITE ⚠️
```

### RDS Planejado (db.t3.small)
```
RAM: 2 GB (DOBRO)
vCPUs: 2
Storage: [manter]
Custo: ~$30/mês (+$15)
Status: UPGRADE AGENDADO ✅
```

### Índices Existentes
```sql
idx_dailylogs_optimized       -- (datecreated, job_id)
idx_dailylogs_job_id          -- (job_id)
idx_dailylogs_process         -- (process)
idx_dailylogs_datecreated     -- (datecreated DESC) [v3.0]
idx_dailylogs_status          -- (status) [v3.0 - já existe]
```

### Índices a Criar (Pós-Upgrade)
```sql
-- 1. Para pattern matching em process
idx_dailylogs_process_pattern
  ON dailylogs(process text_pattern_ops)
  Impacto: Queries 7-8
  Tamanho: ~5-8 MB

-- 2. Para filtros de phase
idx_dailylogs_phase
  ON dailylogs(phase)
  Impacto: Todas as queries
  Tamanho: ~2-3 MB

-- 3. Para JOINs complexos
idx_dailylogs_job_process_date
  ON dailylogs(job_id, process, datecreated DESC)
  Impacto: Queries 7-12 (todas)
  Tamanho: ~10-15 MB

-- 4. Para último status
idx_dailylogs_job_status_date
  ON dailylogs(job_id, status, datecreated DESC)
  Impacto: Queries com DISTINCT ON
  Tamanho: ~10-12 MB

-- 5. Para inspeções
idx_dailylogs_process_status
  ON dailylogs(process, status)
  Impacto: Queries 7-8
  Tamanho: ~5-7 MB

Total Adicional: ~35-50 MB
```

---

## 📋 Plano de Ação

### FASE 1: Upgrade RDS ✅ AGENDADO
**Responsável:** Usuário
**Prazo:** Em andamento
**Duração:** 5-10 minutos (downtime)

**Checklist:**
- [x] Upgrade solicitado via AWS Console
- [ ] Aguardar conclusão
- [ ] Verificar status: `db.t3.small`
- [ ] Avisar Claude quando completo

---

### FASE 2: Criação de Índices ⏳ AGUARDANDO
**Responsável:** Claude
**Pré-requisito:** Upgrade RDS completo
**Duração:** 15-20 minutos
**Arquivo:** `/firefighting/optimization_indexes.sql`

**Comando de Execução:**
```bash
export PGPASSWORD='[senha]'
psql -h lakeshoredevelopmentfl.ch88as8s0tio.us-east-2.rds.amazonaws.com \
     -U postgres_admin \
     -d postgres \
     -f optimization_indexes.sql
```

**Checklist:**
- [ ] Executar criação de índices
- [ ] Monitorar progresso (via CloudWatch)
- [ ] Verificar índices criados
- [ ] Executar ANALYZE dailylogs

---

### FASE 3: Testes de Performance ⏳ AGUARDANDO
**Responsável:** Claude
**Pré-requisito:** Índices criados
**Duração:** 30-40 minutos

**Testes Planejados:**

1. **Query 7 - Benchmark**
   - Executar com EXPLAIN ANALYZE
   - Comparar: 88s → ? (meta: <25s)
   - Documentar plano de execução

2. **Queries 8-12 - Primeira Execução**
   - Executar cada query
   - Medir tempo
   - Validar resultados

3. **Validação de Consistência**
   - Query 7 (resumo) vs Query 8 (detalhe): total_casas deve bater
   - Query 9 (resumo) vs Query 10 (detalhe): total_casas deve bater
   - Query 11 (resumo) vs Query 12 (detalhe): total_casas deve bater

4. **Regression Test**
   - Queries 1-6 não devem ter piorado
   - Performance mantida ou melhorada

**Checklist:**
- [ ] Testar Query 7 com EXPLAIN ANALYZE
- [ ] Testar Queries 8-12 individualmente
- [ ] Validar consistência resumo vs detalhe
- [ ] Verificar regression nas queries antigas
- [ ] Documentar todos os tempos

---

### FASE 4: Documentação Final ⏳ AGUARDANDO
**Responsável:** Claude
**Pré-requisito:** Testes completos

**Atualizações Necessárias:**

1. **`01_queries.sql`**
   - Atualizar cabeçalho para v3.1
   - Documentar tempos reais nas queries 7-12
   - Adicionar notas de performance

2. **`02_estrategia.md`** (opcional)
   - Documentar estratégia das queries de pendências
   - Explicar regras FMEA da Query 10

3. **`03_regras_de_negocio.md`** (opcional)
   - Adicionar regras 0-4 da Query 10
   - Documentar tabela dailylogs_fmea

4. **`ESPECIFICACOES_TECNICAS.md`** (este arquivo)
   - Atualizar com resultados finais
   - Marcar FASE 2-4 como completas

**Checklist:**
- [ ] Atualizar changelog em 01_queries.sql
- [ ] Atualizar tempos de performance
- [ ] Documentar regras FMEA
- [ ] Marcar projeto como completo

---

## 🎯 Métricas de Sucesso

### Performance Target

| Métrica | Valor Alvo | Como Medir |
|---------|------------|------------|
| **Query 7** | < 25s | EXPLAIN ANALYZE |
| **Query 8** | < 30s | EXPLAIN ANALYZE |
| **Query 9** | < 20s | EXPLAIN ANALYZE |
| **Query 10** | < 25s | EXPLAIN ANALYZE |
| **Query 11** | < 20s | EXPLAIN ANALYZE |
| **Query 12** | < 30s | EXPLAIN ANALYZE |
| **Média Geral** | < 25s | Média das 6 queries |
| **Todas < 30s?** | SIM | Looker timeout compliance |

### Viabilidade Looker Studio

**Requisitos:**
- ✅ Refresh a cada 5 minutos
- ✅ Timeout: 30 segundos por query
- ✅ Cache habilitado (5 min)

**Cálculo de Carga:**
```
12 queries antigas + 6 queries novas = 18 queries total
18 queries × 25s média = 450s (7.5 min)

COM CACHE (5 min):
- Looker executa 1x a cada 5 min
- Usuários veem dados cacheados
- ✅ VIÁVEL
```

---

## 📊 Complexidade das Queries

### Análise de Complexidade

| Query | CTEs | JOINs | Subqueries | LIKE | NOT EXISTS | Complexidade |
|-------|------|-------|------------|------|------------|--------------|
| Q7 | 5 | 1 | 1 | 2 | 0 | MÉDIA |
| Q8 | 6 | 3 | 1 | 2 | 0 | MÉDIA-ALTA |
| Q9 | 5 | 1 | 1 | 0 | 0 | MÉDIA |
| Q10 | 5 | 3 | 1 | 0 | 5 | ALTA ⚠️ |
| Q11 | 5 | 1 | 1 | 0 | 0 | MÉDIA |
| Q12 | 7 | 3 | 1 | 0 | 0 | MÉDIA-ALTA |

**Query 10 é a mais complexa:**
- 5 CTEs aninhadas
- 3 JOINs
- **5 NOT EXISTS** (subqueries correlacionadas)
- Usa tabela `dailylogs_fmea` adicional
- Maior risco de performance ruim

---

## 🗄️ Schema de Dados

### Tabela: dailylogs (principal)
```sql
Colunas relevantes:
- job_id (integer) - PK composta
- process (text) - Nome do processo
- status (text) - Status do processo
- phase (text) - Phase 0-4
- datecreated (timestamp) - Data do registro
- jobsite (text) - Nome da casa
- addedby (text) - Usuário
- sub (text) - Subcontratada
- servicedate (text) - Data de serviço
- notes (text) - Observações

Tamanho: ~185K registros
```

### Tabela: dailylogs_fmea (FMEA)
```sql
Colunas relevantes:
- job_id (integer)
- process (text)
- status (text)
- failure_group (text) - Grupo de falha (ex: 'fmea')
- datecreated (timestamp)
- not_report (boolean) - Marcador de exclusão

Tamanho: [desconhecido]
Uso: Query 10 (regras de negócio FMEA)
```

---

## 🚨 Riscos e Mitigações

### Risco 1: Performance Insuficiente
**Probabilidade:** MÉDIA
**Impacto:** ALTO

**Se queries ainda estiverem > 30s após índices:**
- ✅ Otimizar CTEs (combinar, simplificar)
- ✅ Usar MATERIALIZED views (com Lambda refresh)
- ✅ Cache mais agressivo no Looker (10-15 min)
- ✅ Avaliar upgrade adicional (db.t3.medium - 4GB)

### Risco 2: Query 10 Muito Lenta
**Probabilidade:** ALTA ⚠️
**Impacto:** MÉDIO

**Devido a:**
- 5 NOT EXISTS (subqueries correlacionadas)
- JOIN com tabela dailylogs_fmea adicional

**Mitigações:**
- ✅ Criar índice em dailylogs_fmea (job_id, process, status)
- ✅ Reescrever NOT EXISTS como LEFT JOIN ... WHERE IS NULL
- ✅ Simplificar lógica se possível

### Risco 3: Tabela FMEA Inexistente
**Probabilidade:** BAIXA
**Impacto:** CRÍTICO

**Se dailylogs_fmea não existir:**
- Query 10 falhará com erro
- Verificar existência antes de deploy

**Comando de Verificação:**
```sql
SELECT EXISTS (
  SELECT 1 FROM information_schema.tables
  WHERE table_name = 'dailylogs_fmea'
);
```

---

## 📞 Comunicação

### Status Atual
**Última Atualização:** 2025-10-23
**Status:** Aguardando Upgrade RDS

### Próximos Marcos
1. ✅ Upgrade RDS completo → Avisar Claude
2. ⏳ Índices criados → Claude avisa
3. ⏳ Testes completos → Claude avisa
4. ⏳ Documentação final → Claude avisa

---

## 📁 Arquivos do Projeto

```
/firefighting/
├── 01_queries.sql                  # Queries 1-12 (v3.1)
├── 02_estrategia.md               # Estratégia das queries
├── 03_regras_de_negocio.md        # Regras de negócio
├── optimization_indexes.sql        # Script de índices
└── ESPECIFICACOES_TECNICAS.md     # Este arquivo
```

---

**Documento Mantido Por:** Claude Code
**Próxima Revisão:** Após conclusão FASE 4
