# Regras de Negócio - Sistema de Daily Logs
**Database**: lakeshoredevelopmentfl RDS (PostgreSQL 16.8)
**Versão**: 1.0
**Data**: 2025-10-23
**Queries**: 01_queries.sql (12 queries)

---

## Índice

1. [Glossário de Termos](#glossário-de-termos)
2. [Regras Globais](#regras-globais)
3. [Regras por Query](#regras-por-query)
4. [Fluxogramas de Decisão](#fluxogramas-de-decisão)
5. [Casos de Teste](#casos-de-teste)

---

## Glossário de Termos

### Entidades Principais

| Termo | Definição | Exemplo |
|-------|-----------|---------|
| **Job / Casa** | Unidade de construção identificada por `job_id` | job_id = 557 |
| **Process** | Etapa específica do processo de construção | "underground plumbing", "ac trim" |
| **Status** | Estado atual de um processo | "report", "checklist done", "in progress" |
| **Phase** | Fase geral do projeto (0-4) | Phase 0, Phase 1, ..., Phase 4 |
| **Active Job** | Casa que teve atividade nos últimos 60 dias e não está finalizada | - |
| **FMEA** | Failure Mode and Effects Analysis - tabela auxiliar com regras de qualidade | dailylogs_fmea |

### Status Types

| Status | Significado | Quando Ocorre |
|--------|-------------|---------------|
| **report** | Problema identificado, aguardando resolução | Inspeção reprovou, encontrado defeito |
| **checklist done** | Processo concluído e aprovado | Checklist verificado OK |
| **inspection approved** | Inspeção oficial aprovada | Inspetor aprovou |
| **inspection disapproved** | Inspeção oficial reprovada | Inspetor reprovou |
| **rework scheduled** | Reparo agendado | Correção foi agendada |
| **rework requested** | Reparo solicitado | Solicitação de correção |
| **in progress** | Trabalho em andamento | Equipe trabalhando |
| **scheduled** | Trabalho agendado | Agendado para execução |
| **delayed** | Trabalho atrasado | Não executado no prazo |

### Phases

| Phase | Descrição | Processos Típicos |
|-------|-----------|-------------------|
| **Phase 0** | Preparação do terreno | stake lot, clear lot, site preparation |
| **Phase 1** | Fundação e infraestrutura | slab prep, underground plumbing |
| **Phase 2** | Estrutura | framing, rough plumbing, rough electric |
| **Phase 3** | Acabamento interno | drywall, interior paint, cabinets |
| **Phase 4** | Acabamento final | ac trim, final inspection |

---

## Regras Globais

### RG-001: Janela Temporal de Atividade
**Descrição**: Apenas jobs com atividade nos últimos 60 dias são considerados "ativos"
**Aplicação**: Todas as queries (1-12)
**SQL**:
```sql
WHERE datecreated >= NOW() - INTERVAL '60 days'
```
**Razão**: Filtrar projetos antigos/inativos

---

### RG-002: Exclusão de Jobs Finalizados
**Descrição**: Jobs com processo "phase 3 fcc" são considerados finalizados e excluídos
**Aplicação**: Queries 1-12 (via CTE active_jobs)
**SQL**:
```sql
WHERE job_id NOT IN (
  SELECT DISTINCT job_id
  FROM dailylogs
  WHERE process = 'phase 3 fcc'
)
```
**Razão**: "phase 3 fcc" = Final Certificate of Completion

---

### RG-003: Cálculo de Phase Atual
**Descrição**: Phase atual é o **MÁXIMO** entre Phase 0, 1, 2, 3, 4
**Aplicação**: Queries 1-2, 5, 7-12
**SQL**:
```sql
MAX(
  CASE
    WHEN d.phase = 'phase 0' THEN 0
    WHEN d.phase = 'phase 1' THEN 1
    WHEN d.phase = 'phase 2' THEN 2
    WHEN d.phase = 'phase 3' THEN 3
    WHEN d.phase = 'phase 4' THEN 4
    ELSE -1
  END
) as current_phase_number
```
**Razão**: Casa pode ter registros em múltiplas phases, a atual é a mais avançada

---

### RG-004: Job ID Válido
**Descrição**: `job_id` deve ser não-nulo
**Aplicação**: Todas as queries
**SQL**:
```sql
WHERE job_id IS NOT NULL
```

---

## Regras por Query

### Queries 1-6: Casas Ativas e Histórico

#### Query 1: Resumo - Contagem por Phase
**Objetivo**: Mostrar quantas casas estão em cada phase (Phase 0-4)

**Regras Específicas**:
- **RQ1-001**: Conta apenas casas com phase definida (phase IS NOT NULL)
- **RQ1-002**: Agrupa por current_phase_number
- **RQ1-003**: Calcula percentual: `COUNT(*) * 100.0 / SUM(COUNT(*)) OVER ()`

**Saída**:
```
phase_atual | total_casas | percentual
Phase 0     | 25          | 9.6%
Phase 1     | 44          | 16.9%
...
```

---

#### Query 2: Lista Detalhada por Phase
**Objetivo**: Listar cada casa com seu último processo e status

**Regras Específicas**:
- **RQ2-001**: Para cada job, pega o **último evento** (MAX(datecreated))
- **RQ2-002**: Usa DISTINCT ON (job_id) para uma linha por casa
- **RQ2-003**: Ordena por última atividade DESC (mais recente primeiro)

**Saída**:
```
phase_atual | job_id | jobsite | ultima_atividade    | ultimo_processo | ultimo_status
Phase 2     | 557    | c1-0557 | 2025-10-23 12:46:00 | update phase    | inspection dis...
```

---

#### Query 3: Total de Casas Ativas
**Objetivo**: Contar total de casas ativas (validação)

**Regras Específicas**:
- **RQ3-001**: `COUNT(DISTINCT job_id)` de active_jobs
- **RQ3-002**: Usado para validação: Query 1 soma = Query 3 total

---

#### Query 4: Lista de Jobs Finalizados
**Objetivo**: Mostrar jobs com "phase 3 fcc" (finalizados)

**Regras Específicas**:
- **RQ4-001**: Filtra `process = 'phase 3 fcc'`
- **RQ4-002**: Mostra data de finalização: `MAX(datecreated)::date`
- **RQ4-003**: Ordena por data_finalizacao DESC

---

#### Query 5: Lista Individual (Looker Studio)
**Objetivo**: Cada casa em uma linha, clicável para filtrar Query 6

**Regras Específicas**:
- **RQ5-001**: Identica à Query 2, mas ordenação diferente
- **RQ5-002**: Ordena por `current_phase_number, job_id` (para agrupamento)
- **RQ5-003**: Campo `job_id` configurado como filtro cross-table no Looker

---

#### Query 6: Histórico de Uma Casa
**Objetivo**: Mostrar todos os eventos de um job_id específico

**Regras Específicas**:
- **RQ6-001**: Usa view `mv_job_history` (últimos 90 dias)
- **RQ6-002**: **SEMPRE** filtrar por `job_id` (parâmetro obrigatório)
- **RQ6-003**: Ordena por data_registro DESC (mais recente primeiro)
- **RQ6-004**: Converte `servicedate` vazio para NULL

**IMPORTANTE**: Query sem filtro job_id pode levar 50+ segundos!

**SQL**:
```sql
SELECT * FROM mv_job_history
WHERE job_id = @DS_FILTER_job_id  -- OBRIGATÓRIO no Looker
ORDER BY data_registro DESC
```

---

### Queries 7-8: Inspeções Reprovadas

#### Query 7: Inspeções Reprovadas - Resumo
**Objetivo**: Contar casas com inspeções reprovadas "ativas" por phase

**Regras de Definição**: O que é uma "inspeção reprovada ativa"?

**RQ7-001**: Processo contém "inspection" (`process LIKE '%inspection%'`)

**RQ7-002**: Status = "inspection disapproved"

**RQ7-003**: **NÃO** existe aprovação posterior:
- Ou: Nunca houve aprovação (`last_approval_date IS NULL`)
- Ou: A reprovação é **APÓS** a última aprovação (`disapproved_date > last_approval_date`)

**Lógica SQL**:
```sql
-- CTE: inspection_failures (todas as reprovações)
WHERE d.process LIKE '%inspection%'
  AND d.status = 'inspection disapproved'

-- CTE: inspection_approvals (última aprovação de cada inspeção)
WHERE d.process LIKE '%inspection%'
  AND d.status = 'inspection approved'
GROUP BY job_id, process  -- MAX(datecreated)

-- CTE: active_failures (reprovações sem aprovação posterior)
WHERE ia.last_approval_date IS NULL
   OR if.datecreated > ia.last_approval_date
```

**Exemplo**:
```
job_id=557, process="rough plumbing inspection"
  - 2025-10-01: inspection disapproved
  - 2025-10-05: inspection approved
  - 2025-10-10: inspection disapproved  ← ATIVA (após aprovação)

job_id=558, process="final inspection"
  - 2025-10-15: inspection disapproved  ← ATIVA (nunca aprovada)
```

---

#### Query 8: Inspeções Reprovadas - Lista Detalhada
**Objetivo**: Listar cada inspeção reprovada ativa com detalhes

**Regras Específicas**:
- **RQ8-001**: Mesma lógica da Query 7 (active_failures)
- **RQ8-002**: Mostra a **última** reprovação: `DISTINCT ON (job_id, process)`
- **RQ8-003**: Calcula `dias_pendente`: `EXTRACT(DAYS FROM NOW() - datecreated)`
- **RQ8-004**: Ordena por dias_pendente DESC (mais antigos primeiro)

**Saída**:
```
phase_atual | job_id | jobsite | processo                    | data_reprovacao     | dias_pendente
Phase 2     | 557    | c1-0557 | rough plumbing inspection   | 2025-10-10 11:30:00 | 13
```

---

### Queries 9-10: Reports sem Checklist Done

#### Query 9: Reports Pendentes - Resumo
**Objetivo**: Contar casas com reports pendentes por phase

**Regras de Definição**: O que é um "report pendente"?

**RQ9-001**: Status = "report"

**RQ9-002**: **NÃO** existe "checklist done" posterior:
- Ou: Nunca houve checklist done (`first_checklist_done_date IS NULL`)
- Ou: O report é **APÓS** o checklist done (`report_date > first_checklist_done_date`)

**RQ9-003**: Total de reports pendentes: `COUNT(*)` (não DISTINCT, pois um job pode ter múltiplos reports)

**Lógica SQL**:
```sql
-- CTE: reports (todos os reports)
WHERE d.status = 'report'

-- CTE: checklist_done (primeiro checklist done de cada processo)
WHERE d.status = 'checklist done'
GROUP BY job_id, process  -- MIN(datecreated)

-- CTE: pending_reports (reports sem checklist done posterior)
WHERE cd.first_checklist_done_date IS NULL
   OR r.report_date > cd.first_checklist_done_date
```

---

#### Query 10: Reports Pendentes - Lista Detalhada
**Objetivo**: Listar cada report pendente com filtros avançados de limpeza

**Regras de Definição**: Report é considerado **pendente** se:
1. Passou pelas regras básicas da Query 9 (sem checklist done posterior)
2. **E** passou por 5 regras de exclusão (0-4):

---

##### **REGRA 0**: Processos Marcados como "não precisa report" no FMEA

**RQ10-R0-001**: Excluir se `dailylogs_fmea.not_report = TRUE`

**Critério**:
```sql
WHERE fmea.process = report.process
  AND fmea.status = report.status
  AND fmea.not_report = TRUE
```

**Exemplo**:
```
process="ac trim", status="report"
→ Na tabela dailylogs_fmea: not_report = TRUE
→ Processo não precisa de report, EXCLUIR
```

**Redução**: -38 registros (-7%)

---

##### **REGRA 1**: Rework Agendado APÓS o Report

**RQ10-R1-001**: Excluir se existe `status = 'rework scheduled'` com data **APÓS** report_date

**Critério**:
```sql
WHERE dl.job_id = report.job_id
  AND dl.process = report.process
  AND dl.status = 'rework scheduled'
  AND dl.datecreated > report.report_date
```

**Razão**: Se o rework já foi agendado, o report foi endereçado

**Exemplo**:
```
job_id=557, process="ac trim"
  - 2025-10-01: status="report"  ← Report inicial
  - 2025-10-05: status="rework scheduled"  ← Rework agendado APÓS
→ Report já endereçado, EXCLUIR
```

**Redução**: -111 registros (**-23%**) - Maior impacto!

---

##### **REGRA 2**: Checklist Done com FMEA APÓS o Report

**RQ10-R2-001**: Excluir se existe na `dailylogs_fmea`:
- Mesmo `job_id` + `process`
- Status = "checklist done"
- `failure_group` contém "fmea" (case-insensitive)
- Data **APÓS** report_date

**Critério**:
```sql
WHERE fmea.job_id = report.job_id
  AND fmea.process = report.process
  AND fmea.status = 'checklist done'
  AND fmea.failure_group ILIKE '%fmea%'
  AND fmea.datecreated::timestamp > report.report_date
```

**Razão**: Checklist done registrado em FMEA significa que foi resolvido via análise FMEA

**Exemplo**:
```
job_id=557, process="interior paint"
  - dailylogs: 2025-10-01, status="report"
  - dailylogs_fmea: 2025-10-03, status="checklist done", failure_group="fmea report: erro de sub"
→ Resolvido via FMEA, EXCLUIR
```

**Redução**: -5 registros (-1%)

---

##### **REGRA 3**: Rework Requested com FMEA APÓS o Report

**RQ10-R3-001**: Excluir se existe na `dailylogs_fmea`:
- Mesmo `job_id` + `process`
- Status = "rework requested"
- `failure_group` contém "fmea"
- Data **APÓS** report_date

**Critério**:
```sql
WHERE fmea.job_id = report.job_id
  AND fmea.process = report.process
  AND fmea.status = 'rework requested'
  AND fmea.failure_group ILIKE '%fmea%'
  AND fmea.datecreated::timestamp > report.report_date
```

**Razão**: Rework solicitado via FMEA significa que o problema foi identificado e ação foi tomada

**Exemplo**:
```
job_id=557, process="rough plumbing"
  - dailylogs: 2025-10-01, status="report"
  - dailylogs_fmea: 2025-10-02, status="rework requested", failure_group="fmea report: erro de sub"
→ Ação tomada via FMEA, EXCLUIR
```

**Redução**: -2 registros (-0.5%)

---

##### **REGRA 4**: Trabalho em Progresso APÓS o Report

**RQ10-R4-001**: Excluir se existe `status = 'in progress'` com data **APÓS** report_date

**Critério**:
```sql
WHERE dl.job_id = report.job_id
  AND dl.process = report.process
  AND dl.status = 'in progress'
  AND dl.datecreated > report.report_date
```

**Razão**: Se o trabalho está em progresso, o report está sendo endereçado

**Exemplo**:
```
job_id=557, process="drywall and texture"
  - 2025-10-01: status="report"  ← Problema reportado
  - 2025-10-08: status="in progress"  ← Correção em andamento
→ Sendo endereçado, EXCLUIR
```

**Redução**: -46 registros (**-12%**) - Segundo maior impacto

---

##### Resumo da Filtragem Query 10

| Etapa | Registros | Redução | % |
|-------|-----------|---------|---|
| **Inicial** (reports sem checklist done) | 524 | - | 100% |
| Após Regra 0 (FMEA not_report) | 486 | -38 | 93% |
| Após Regra 1 (rework scheduled) | 375 | -111 | 72% |
| Após Regra 2 (checklist done FMEA) | 370 | -5 | 71% |
| Após Regra 3 (rework requested FMEA) | 368 | -2 | 70% |
| **Após Regra 4 (in progress)** | **322** | **-46** | **61%** |

**Total de redução**: 524 → 322 (**-38.5%**)

**Interpretação**: Dos 524 reports iniciais sem checklist done, **202 já foram endereçados** de alguma forma (agendado, em progresso, resolvido via FMEA, etc.), restando **322 reports verdadeiramente pendentes**.

---

### Queries 11-12: Scheduled sem Checklist Done

#### Query 11: Scheduled Pendentes - Resumo
**Objetivo**: Contar processos "scheduled" que ainda não foram concluídos

**Regras de Definição**: O que é um "scheduled aberto"?

**RQ11-001**: Status = "scheduled"

**RQ11-002**: **NÃO** existe "checklist done" posterior:
- Ou: Nunca houve checklist done
- Ou: O scheduled é **APÓS** o checklist done

**Lógica**: Similar à Query 9, mas para status "scheduled"

---

#### Query 12: Scheduled Pendentes - Lista Detalhada
**Objetivo**: Listar cada processo scheduled pendente

**Regras Específicas**:
- **RQ12-001**: Mesma lógica da Query 11
- **RQ12-002**: Mostra último scheduled de cada job+process
- **RQ12-003**: Calcula `dias_pendente`
- **RQ12-004**: Ordena por dias_pendente DESC

---

## Fluxogramas de Decisão

### Fluxo: "Este Report está Pendente?"

```
┌─────────────────────────────────┐
│  Report encontrado              │
│  (status = 'report')            │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Existe checklist done           │
│ APÓS este report?               │
└────────┬────────────┬───────────┘
         │ SIM        │ NÃO
         │            │
         ▼            ▼
    ┌───────┐   ┌──────────────────┐
    │ FIM   │   │ Continuar análise│
    │ (OK)  │   └────────┬─────────┘
    └───────┘            │
                         ▼
                ┌─────────────────────────────────┐
                │ REGRA 0: Processo está na FMEA  │
                │ com not_report = TRUE?          │
                └────────┬────────────┬───────────┘
                         │ SIM        │ NÃO
                         │            │
                         ▼            ▼
                    ┌───────┐   ┌──────────────────┐
                    │ FIM   │   │ Continuar...     │
                    │ (OK)  │   └────────┬─────────┘
                    └───────┘            │
                                         ▼
                                ┌─────────────────────────────────┐
                                │ REGRA 1: Existe rework          │
                                │ scheduled APÓS report?          │
                                └────────┬────────────┬───────────┘
                                         │ SIM        │ NÃO
                                         │            │
                                         ▼            ▼
                                    ┌───────┐   ┌──────────────────┐
                                    │ FIM   │   │ Continuar...     │
                                    │ (OK)  │   └────────┬─────────┘
                                    └───────┘            │
                                                         ▼
                                                    [Regras 2, 3, 4...]
                                                         │
                                                         ▼
                                                ┌─────────────────┐
                                                │ REPORT          │
                                                │ PENDENTE!       │
                                                │ (Mostrar na     │
                                                │  Query 10)      │
                                                └─────────────────┘
```

---

### Fluxo: "Esta Inspeção está Ativa (Reprovada)?"

```
┌─────────────────────────────────┐
│ Inspeção encontrada             │
│ (process LIKE '%inspection%')   │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Status = 'inspection            │
│ disapproved'?                   │
└────────┬────────────┬───────────┘
         │ SIM        │ NÃO
         │            │
         ▼            ▼
┌─────────────────┐  ┌────────┐
│ Existe aprovação│  │ FIM    │
│ POSTERIOR?      │  │ (N/A)  │
└────┬────────┬───┘  └────────┘
     │ SIM    │ NÃO
     │        │
     ▼        ▼
┌────────┐  ┌─────────────────┐
│ FIM    │  │ INSPEÇÃO ATIVA! │
│ (OK)   │  │ (Mostrar na     │
└────────┘  │  Query 7/8)     │
            └─────────────────┘
```

---

## Casos de Teste

### Caso 1: Report que deve aparecer na Query 10

**Setup**:
```
job_id: 999
process: "ac trim"

Histórico (dailylogs):
  2025-10-01 10:00 | status="scheduled"
  2025-10-05 11:00 | status="in progress"
  2025-10-08 14:30 | status="report"  ← Este report
  [sem mais registros]

dailylogs_fmea: (vazio para este processo)
```

**Análise**:
- ✅ Report sem checklist done posterior
- ✅ Regra 0: não_report não está TRUE
- ✅ Regra 1: sem rework scheduled após
- ✅ Regra 2: sem checklist done FMEA após
- ✅ Regra 3: sem rework requested FMEA após
- ✅ Regra 4: sem in progress após

**Resultado**: **APARECE** na Query 10 ✓

---

### Caso 2: Report que NÃO deve aparecer (Regra 1)

**Setup**:
```
job_id: 1000
process: "drywall and texture"

Histórico (dailylogs):
  2025-10-01 10:00 | status="report"  ← Report inicial
  2025-10-03 15:00 | status="rework scheduled"  ← Rework agendado
```

**Análise**:
- ✅ Report sem checklist done posterior
- ✅ Regra 0: OK
- ❌ **Regra 1: rework scheduled APÓS report** → EXCLUIR

**Resultado**: **NÃO APARECE** na Query 10 (filtrado pela Regra 1) ✓

---

### Caso 3: Report que NÃO deve aparecer (Regra 2 - FMEA)

**Setup**:
```
job_id: 1001
process: "interior paint"

dailylogs:
  2025-10-05 09:00 | status="report"

dailylogs_fmea:
  2025-10-06 14:00 | status="checklist done"
                   | failure_group="fmea report: erro de sub"
```

**Análise**:
- ✅ Report sem checklist done posterior (na tabela dailylogs)
- ✅ Regra 0: OK
- ✅ Regra 1: OK
- ❌ **Regra 2: checklist done FMEA APÓS report** → EXCLUIR

**Resultado**: **NÃO APARECE** na Query 10 (filtrado pela Regra 2) ✓

---

### Caso 4: Inspeção Ativa

**Setup**:
```
job_id: 1002
process: "rough plumbing inspection"

Histórico:
  2025-09-15 | status="inspection disapproved"  ← Reprovação 1
  2025-09-20 | status="inspection approved"     ← Aprovação
  2025-10-10 | status="inspection disapproved"  ← Reprovação 2 (ATUAL)
```

**Análise**:
- ✅ Processo contém "inspection"
- ✅ Status = "inspection disapproved"
- ✅ Reprovação 2 é **APÓS** última aprovação (10-10 > 09-20)

**Resultado**: **APARECE** na Query 7/8 (inspeção ativa) ✓

---

### Caso 5: Inspeção Resolvida

**Setup**:
```
job_id: 1003
process: "final inspection"

Histórico:
  2025-10-01 | status="inspection disapproved"
  2025-10-05 | status="inspection approved"  ← Aprovação final
```

**Análise**:
- ✅ Processo contém "inspection"
- ✅ Status = "inspection disapproved"
- ❌ Existe aprovação POSTERIOR (10-05 > 10-01)

**Resultado**: **NÃO APARECE** na Query 7/8 (resolvida) ✓

---

## Manutenção e Evolução

### Quando Adicionar Nova Regra à Query 10?

Adicione nova regra de exclusão quando identificar um **padrão consistente** de reports que já foram endereçados mas ainda aparecem na lista.

**Processo**:
1. Identificar padrão (ex: todos têm status X após o report)
2. Validar com amostra de dados
3. Estimar impacto (quantos registros serão excluídos?)
4. Adicionar regra como NOT EXISTS
5. Testar redução progressiva
6. Atualizar esta documentação

### Quando Remover Regra?

Remova regra quando:
- Processo de trabalho mudou
- Regra tem **zero impacto** (nenhum registro excluído)
- Falsos negativos (reports reais sendo excluídos)

---

## Histórico de Alterações

### v1.0 (2025-10-23)
- Documentação inicial
- 12 queries documentadas
- Query 10: 5 regras de exclusão
- Casos de teste criados

---

## Referências

- **Arquivo SQL**: `firefighting/01_queries.sql`
- **Otimizações RDS**: `firefighting/OTIMIZACOES_RDS.md`
- **Database**: lakeshoredevelopmentfl.ch88as8s0tio.us-east-2.rds.amazonaws.com
- **Looker Studio**: [Dashboard URL]

---

## Contato

**DBA**: postgres_admin
**AWS Account**: 460044121130
**Última Atualização**: 2025-10-23
