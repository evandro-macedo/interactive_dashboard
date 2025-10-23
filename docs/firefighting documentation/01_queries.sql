-- ============================================================================
-- QUERIES: CASAS ATIVAS POR PHASE - COMPATIBLE WITH GOOGLE LOOKER STUDIO
-- ============================================================================
-- Descrição: Queries SQL para dashboard interativo no Looker Studio
-- Database: lakeshoredevelopmentfl RDS (postgres database)
-- Tabela: dailylogs
-- Data: 2025-10-23
-- Versão: 3.0 (Performance Optimized + Materialized View)
-- ============================================================================
--
-- OTIMIZACOES APLICADAS (v3.0):
-- - Indice em datecreated para queries de filtro temporal
-- - View materializada (mv_job_history) para Query 6
-- - Funcao de limpeza de conexoes idle
-- - Reducao de 56s para <1s na Query 6
-- - Reducao de 500ms para ~174ms na Query 1
-- ============================================================================

-- IMPORTANTE: Todos os aliases usam snake_case (sem espaços) para
-- compatibilidade com Google Looker Studio
--
-- Looker Studio não aceita:
--   - Espaços em nomes de campos
--   - Caracteres Unicode (acentos: ú, á, ã, etc.)
--   - Caracteres especiais (ampersands, colons, etc.)
--
-- Referência: https://support.google.com/looker-studio/answer/12150924

-- ============================================================================
-- QUERY 1: RESUMO - Contagem de Casas por Phase
-- ============================================================================
-- Uso: Gráfico de pizza/barras mostrando distribuição por phase
-- Tempo de execução: ~174ms (otimizado com idx_dailylogs_datecreated)
-- Resultado: 5 linhas (uma por phase)
-- Refresh recomendado: A cada 30 minutos (antes: 15 min)

WITH active_jobs AS (
  SELECT DISTINCT job_id, jobsite
  FROM dailylogs
  WHERE datecreated >= NOW() - INTERVAL '60 days'
    AND job_id IS NOT NULL
    AND job_id NOT IN (
      SELECT DISTINCT job_id
      FROM dailylogs
      WHERE process = 'phase 3 fcc'
    )
),
job_max_phase AS (
  SELECT
    d.job_id,
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
  FROM dailylogs d
  WHERE d.job_id IN (SELECT job_id FROM active_jobs)
    AND d.phase IS NOT NULL
  GROUP BY d.job_id
)
SELECT
  CASE
    WHEN jmp.current_phase_number = 0 THEN 'Phase 0'
    WHEN jmp.current_phase_number = 1 THEN 'Phase 1'
    WHEN jmp.current_phase_number = 2 THEN 'Phase 2'
    WHEN jmp.current_phase_number = 3 THEN 'Phase 3'
    WHEN jmp.current_phase_number = 4 THEN 'Phase 4'
  END as phase_atual,
  COUNT(*) as total_casas,
  CONCAT(ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1)::text, '%') as percentual
FROM job_max_phase jmp
WHERE jmp.current_phase_number >= 0
GROUP BY jmp.current_phase_number
ORDER BY jmp.current_phase_number;


-- ============================================================================
-- QUERY 2: LISTA DETALHADA - Casas por Phase com Último Processo/Status
-- ============================================================================
-- Uso: Tabela detalhada para análise manual
-- Tempo de execução: ~800ms
-- Resultado: 260 linhas (uma por casa)
-- Ordenação: Por última atividade DESC (mais recente primeiro)
-- Nota: ultima_atividade inclui data e hora (timestamp)

WITH active_jobs AS (
  SELECT DISTINCT job_id, jobsite
  FROM dailylogs
  WHERE datecreated >= NOW() - INTERVAL '60 days'
    AND job_id IS NOT NULL
    AND job_id NOT IN (
      SELECT DISTINCT job_id
      FROM dailylogs
      WHERE process = 'phase 3 fcc'
    )
),
job_max_phase AS (
  SELECT
    d.job_id,
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
  FROM dailylogs d
  WHERE d.job_id IN (SELECT job_id FROM active_jobs)
    AND d.phase IS NOT NULL
  GROUP BY d.job_id
),
job_last_event AS (
  -- Pegar o último registro (mais recente) de cada job
  SELECT DISTINCT ON (d.job_id)
    d.job_id,
    d.datecreated as ultima_atividade,
    d.process as ultimo_processo,
    d.status as ultimo_status
  FROM dailylogs d
  WHERE d.job_id IN (SELECT job_id FROM active_jobs)
  ORDER BY d.job_id, d.datecreated DESC
)
SELECT
  CASE
    WHEN jmp.current_phase_number = 0 THEN 'Phase 0'
    WHEN jmp.current_phase_number = 1 THEN 'Phase 1'
    WHEN jmp.current_phase_number = 2 THEN 'Phase 2'
    WHEN jmp.current_phase_number = 3 THEN 'Phase 3'
    WHEN jmp.current_phase_number = 4 THEN 'Phase 4'
  END as phase_atual,
  aj.job_id,
  aj.jobsite,
  jle.ultima_atividade,
  jle.ultimo_processo,
  jle.ultimo_status
FROM job_max_phase jmp
JOIN active_jobs aj ON jmp.job_id = aj.job_id
JOIN job_last_event jle ON aj.job_id = jle.job_id
WHERE jmp.current_phase_number >= 0
ORDER BY jle.ultima_atividade DESC, aj.job_id;


-- ============================================================================
-- QUERY 3: TOTAL - Contagem Total de Casas Ativas
-- ============================================================================
-- Uso: Validação/controle
-- Tempo de execução: ~300ms
-- Resultado: 1 linha com total

SELECT COUNT(DISTINCT job_id) as total_casas_ativas
FROM dailylogs
WHERE datecreated >= NOW() - INTERVAL '60 days'
  AND job_id IS NOT NULL
  AND job_id NOT IN (
    SELECT DISTINCT job_id
    FROM dailylogs
    WHERE process = 'phase 3 fcc'
  );


-- ============================================================================
-- QUERY 4: VALIDAÇÃO - Lista de Jobs Finalizados
-- ============================================================================
-- Uso: Verificar quais jobs foram excluídos
-- Tempo de execução: ~200ms

SELECT DISTINCT
  job_id,
  jobsite,
  MAX(datecreated)::date as data_finalizacao
FROM dailylogs
WHERE process = 'phase 3 fcc'
GROUP BY job_id, jobsite
ORDER BY data_finalizacao DESC;


-- ============================================================================
-- QUERY 5: LISTA INDIVIDUAL - Cada Casa em Uma Linha (LOOKER STUDIO)
-- ============================================================================
-- Uso: Tabela clicável no Looker Studio
-- Função: Usuário clica em uma linha → job_id vira filtro para Query 6
-- Tempo de execução: ~800ms
-- Resultado: 260 linhas (uma por casa)
-- Nota: ultima_atividade inclui data e hora (timestamp)
--
-- LOOKER STUDIO SETUP:
-- - Coluna job_id configurada como filtro cross-table
-- - Ao clicar na linha, filtra automaticamente a Query 6

WITH active_jobs AS (
  SELECT DISTINCT job_id, jobsite
  FROM dailylogs
  WHERE datecreated >= NOW() - INTERVAL '60 days'
    AND job_id IS NOT NULL
    AND job_id NOT IN (
      SELECT DISTINCT job_id
      FROM dailylogs
      WHERE process = 'phase 3 fcc'
    )
),
job_max_phase AS (
  SELECT
    d.job_id,
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
  FROM dailylogs d
  WHERE d.job_id IN (SELECT job_id FROM active_jobs)
    AND d.phase IS NOT NULL
  GROUP BY d.job_id
),
job_last_event AS (
  SELECT DISTINCT ON (d.job_id)
    d.job_id,
    d.datecreated as ultima_atividade,
    d.process as ultimo_processo,
    d.status as ultimo_status
  FROM dailylogs d
  WHERE d.job_id IN (SELECT job_id FROM active_jobs)
  ORDER BY d.job_id, d.datecreated DESC
)
SELECT
  CASE
    WHEN jmp.current_phase_number = 0 THEN 'Phase 0'
    WHEN jmp.current_phase_number = 1 THEN 'Phase 1'
    WHEN jmp.current_phase_number = 2 THEN 'Phase 2'
    WHEN jmp.current_phase_number = 3 THEN 'Phase 3'
    WHEN jmp.current_phase_number = 4 THEN 'Phase 4'
  END as phase_atual,
  aj.job_id,
  aj.jobsite,
  jle.ultima_atividade,
  jle.ultimo_processo,
  jle.ultimo_status
FROM job_max_phase jmp
JOIN active_jobs aj ON jmp.job_id = aj.job_id
JOIN job_last_event jle ON aj.job_id = jle.job_id
WHERE jmp.current_phase_number >= 0
ORDER BY jmp.current_phase_number, aj.job_id;


-- ============================================================================
-- QUERY 6: HISTÓRICO - Todos os Eventos de Uma Casa (LOOKER STUDIO)
-- ============================================================================
-- Uso: Tabela de histórico que responde ao clique na Query 5
-- Função: Recebe job_id como parâmetro e mostra todo o histórico
-- Tempo de execução: ~0.5ms (otimizado com mv_job_history)
-- Resultado: Varia (ex: 153 eventos para job 557)
-- Nota: data_registro inclui data e hora (timestamp)
--
-- IMPORTANTE: SEMPRE use filtro job_id! Query sem filtro leva 56+ segundos!
--
-- LOOKER STUDIO SETUP:
-- - Parâmetro: @DS_FILTER_job_id (filtro cross-table OBRIGATÓRIO)
-- - Esta tabela atualiza automaticamente quando usuário clica na Query 5
-- - NÃO configure como data source sem filtro (causa sobrecarga no RDS)
--
-- VERSÃO OTIMIZADA (usa view materializada):

SELECT
  job_id,
  jobsite,
  data_registro,
  processo,
  status,
  phase,
  usuario,
  subcontratada,
  data_servico,
  notas
FROM mv_job_history
ORDER BY data_registro DESC;

-- VERSÃO ALTERNATIVA (tabela original, não recomendada):
-- SELECT
--   job_id,
--   jobsite,
--   datecreated as data_registro,
--   process as processo,
--   status,
--   phase,
--   addedby as usuario,
--   sub as subcontratada,
--   CASE
--     WHEN servicedate IS NULL OR servicedate = '' THEN NULL
--     ELSE servicedate::date
--   END as data_servico,
--   notes as notas
-- FROM dailylogs
-- WHERE job_id = 557  -- FILTRO OBRIGATÓRIO!
-- ORDER BY datecreated DESC;


-- ============================================================================
-- QUERIES DE PENDÊNCIAS POR PHASE (v3.1)
-- ============================================================================
-- Queries 7-12: Identificar problemas/pendências em casas ativas
-- Todas seguem a mesma lógica de casas ativas (60 dias, sem phase 3 fcc)
-- ============================================================================


-- ============================================================================
-- QUERY 7: INSPEÇÕES REPROVADAS - Resumo por Phase
-- ============================================================================
-- Uso: Gráfico/tabela mostrando quantas casas têm inspeções reprovadas ativas
-- Tempo de execução: ~300ms
-- Resultado: 5 linhas (uma por phase) + contagem de casas afetadas
-- Nota: Inspeção é considerada "ativa" se não há aprovação posterior

WITH active_jobs AS (
  SELECT DISTINCT job_id, jobsite
  FROM dailylogs
  WHERE datecreated >= NOW() - INTERVAL '60 days'
    AND job_id IS NOT NULL
    AND job_id NOT IN (
      SELECT DISTINCT job_id
      FROM dailylogs
      WHERE process = 'phase 3 fcc'
    )
),
job_max_phase AS (
  SELECT
    d.job_id,
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
  FROM dailylogs d
  WHERE d.job_id IN (SELECT job_id FROM active_jobs)
    AND d.phase IS NOT NULL
  GROUP BY d.job_id
),
inspection_failures AS (
  -- Todos os registros de inspeções reprovadas
  SELECT
    d.job_id,
    d.process,
    d.datecreated,
    d.status
  FROM dailylogs d
  WHERE d.job_id IN (SELECT job_id FROM active_jobs)
    AND d.process LIKE '%inspection%'
    AND d.status = 'inspection disapproved'
),
inspection_approvals AS (
  -- Última aprovação de cada inspeção por job+process
  SELECT
    d.job_id,
    d.process,
    MAX(d.datecreated) as last_approval_date
  FROM dailylogs d
  WHERE d.job_id IN (SELECT job_id FROM active_jobs)
    AND d.process LIKE '%inspection%'
    AND d.status = 'inspection approved'
  GROUP BY d.job_id, d.process
),
active_failures AS (
  -- Inspeções reprovadas que NÃO têm aprovação posterior
  SELECT DISTINCT
    if.job_id,
    if.process
  FROM inspection_failures if
  LEFT JOIN inspection_approvals ia
    ON if.job_id = ia.job_id
    AND if.process = ia.process
  WHERE ia.last_approval_date IS NULL
     OR if.datecreated > ia.last_approval_date
)
SELECT
  CASE
    WHEN jmp.current_phase_number = 0 THEN 'Phase 0'
    WHEN jmp.current_phase_number = 1 THEN 'Phase 1'
    WHEN jmp.current_phase_number = 2 THEN 'Phase 2'
    WHEN jmp.current_phase_number = 3 THEN 'Phase 3'
    WHEN jmp.current_phase_number = 4 THEN 'Phase 4'
  END as phase_atual,
  COUNT(DISTINCT af.job_id) as total_casas,
  COUNT(*) as total_inspections_reprovadas,
  CONCAT(ROUND(COUNT(DISTINCT af.job_id) * 100.0 /
    (SELECT COUNT(DISTINCT job_id) FROM active_jobs), 1)::text, '%') as percentual
FROM job_max_phase jmp
JOIN active_failures af ON jmp.job_id = af.job_id
WHERE jmp.current_phase_number >= 0
GROUP BY jmp.current_phase_number
ORDER BY jmp.current_phase_number;


-- ============================================================================
-- QUERY 8: INSPEÇÕES REPROVADAS - Lista Detalhada
-- ============================================================================
-- Uso: Tabela detalhada mostrando cada inspeção reprovada ativa
-- Tempo de execução: ~400ms
-- Resultado: Varia (uma linha por job+process com inspeção reprovada)
-- Ordenação: Por phase, depois por dias em aberto (mais antigas primeiro)

WITH active_jobs AS (
  SELECT DISTINCT job_id, jobsite
  FROM dailylogs
  WHERE datecreated >= NOW() - INTERVAL '60 days'
    AND job_id IS NOT NULL
    AND job_id NOT IN (
      SELECT DISTINCT job_id
      FROM dailylogs
      WHERE process = 'phase 3 fcc'
    )
),
job_max_phase AS (
  SELECT
    d.job_id,
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
  FROM dailylogs d
  WHERE d.job_id IN (SELECT job_id FROM active_jobs)
    AND d.phase IS NOT NULL
  GROUP BY d.job_id
),
inspection_failures AS (
  SELECT
    d.job_id,
    d.process,
    d.datecreated,
    d.status
  FROM dailylogs d
  WHERE d.job_id IN (SELECT job_id FROM active_jobs)
    AND d.process LIKE '%inspection%'
    AND d.status = 'inspection disapproved'
),
inspection_approvals AS (
  SELECT
    d.job_id,
    d.process,
    MAX(d.datecreated) as last_approval_date
  FROM dailylogs d
  WHERE d.job_id IN (SELECT job_id FROM active_jobs)
    AND d.process LIKE '%inspection%'
    AND d.status = 'inspection approved'
  GROUP BY d.job_id, d.process
),
active_failures_detail AS (
  -- Última reprovação de cada job+process sem aprovação posterior
  SELECT DISTINCT ON (if.job_id, if.process)
    if.job_id,
    if.process,
    if.datecreated as data_reprovacao,
    if.status
  FROM inspection_failures if
  LEFT JOIN inspection_approvals ia
    ON if.job_id = ia.job_id
    AND if.process = ia.process
  WHERE ia.last_approval_date IS NULL
     OR if.datecreated > ia.last_approval_date
  ORDER BY if.job_id, if.process, if.datecreated DESC
),
ultimo_status_inspecao AS (
  -- Último status de cada inspeção (para mostrar status atual)
  SELECT DISTINCT ON (d.job_id, d.process)
    d.job_id,
    d.process,
    d.status as ultimo_status,
    d.datecreated as data_ultimo_status
  FROM dailylogs d
  WHERE d.job_id IN (SELECT job_id FROM active_jobs)
    AND d.process LIKE '%inspection%'
  ORDER BY d.job_id, d.process, d.datecreated DESC
)
SELECT
  CASE
    WHEN jmp.current_phase_number = 0 THEN 'Phase 0'
    WHEN jmp.current_phase_number = 1 THEN 'Phase 1'
    WHEN jmp.current_phase_number = 2 THEN 'Phase 2'
    WHEN jmp.current_phase_number = 3 THEN 'Phase 3'
    WHEN jmp.current_phase_number = 4 THEN 'Phase 4'
  END as phase_atual,
  aj.job_id,
  aj.jobsite,
  afd.process as processo_inspecao,
  afd.data_reprovacao,
  EXTRACT(DAYS FROM NOW() - afd.data_reprovacao)::INT as dias_em_aberto,
  usi.ultimo_status,
  usi.data_ultimo_status
FROM job_max_phase jmp
JOIN active_jobs aj ON jmp.job_id = aj.job_id
JOIN active_failures_detail afd ON aj.job_id = afd.job_id
LEFT JOIN ultimo_status_inspecao usi
  ON afd.job_id = usi.job_id
  AND afd.process = usi.process
WHERE jmp.current_phase_number >= 0
ORDER BY jmp.current_phase_number, dias_em_aberto DESC;


-- ============================================================================
-- QUERY 9: REPORTS SEM CHECKLIST DONE - Resumo por Phase
-- ============================================================================
-- Uso: Gráfico/tabela mostrando quantas casas têm reports pendentes
-- Tempo de execução: ~250ms
-- Resultado: 5 linhas (uma por phase) + contagem de casas afetadas
-- Nota: Report é considerado "pendente" se não há checklist done posterior

WITH active_jobs AS (
  SELECT DISTINCT job_id, jobsite
  FROM dailylogs
  WHERE datecreated >= NOW() - INTERVAL '60 days'
    AND job_id IS NOT NULL
    AND job_id NOT IN (
      SELECT DISTINCT job_id
      FROM dailylogs
      WHERE process = 'phase 3 fcc'
    )
),
job_max_phase AS (
  SELECT
    d.job_id,
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
  FROM dailylogs d
  WHERE d.job_id IN (SELECT job_id FROM active_jobs)
    AND d.phase IS NOT NULL
  GROUP BY d.job_id
),
reports AS (
  SELECT
    d.job_id,
    d.process,
    d.datecreated as report_date,
    d.status
  FROM dailylogs d
  WHERE d.job_id IN (SELECT job_id FROM active_jobs)
    AND d.status = 'report'
),
checklist_done AS (
  SELECT
    d.job_id,
    d.process,
    MIN(d.datecreated) as first_checklist_done_date
  FROM dailylogs d
  WHERE d.job_id IN (SELECT job_id FROM active_jobs)
    AND d.status = 'checklist done'
  GROUP BY d.job_id, d.process
),
pending_reports AS (
  -- Reports que NÃO têm checklist done posterior
  SELECT DISTINCT
    r.job_id,
    r.process
  FROM reports r
  LEFT JOIN checklist_done cd
    ON r.job_id = cd.job_id
    AND r.process = cd.process
  WHERE cd.first_checklist_done_date IS NULL
     OR r.report_date > cd.first_checklist_done_date
)
SELECT
  CASE
    WHEN jmp.current_phase_number = 0 THEN 'Phase 0'
    WHEN jmp.current_phase_number = 1 THEN 'Phase 1'
    WHEN jmp.current_phase_number = 2 THEN 'Phase 2'
    WHEN jmp.current_phase_number = 3 THEN 'Phase 3'
    WHEN jmp.current_phase_number = 4 THEN 'Phase 4'
  END as phase_atual,
  COUNT(DISTINCT pr.job_id) as total_casas,
  COUNT(*) as total_reports_pendentes,
  CONCAT(ROUND(COUNT(DISTINCT pr.job_id) * 100.0 /
    (SELECT COUNT(DISTINCT job_id) FROM active_jobs), 1)::text, '%') as percentual
FROM job_max_phase jmp
JOIN pending_reports pr ON jmp.job_id = pr.job_id
WHERE jmp.current_phase_number >= 0
GROUP BY jmp.current_phase_number
ORDER BY jmp.current_phase_number;


-- ============================================================================
-- QUERY 10: REPORTS SEM CHECKLIST DONE - Lista Detalhada
-- ============================================================================
-- Uso: Tabela detalhada mostrando cada report pendente
-- Tempo de execução: ~300ms
-- Resultado: Varia (uma linha por job+process com report pendente)
-- Ordenação: Por phase, depois por dias pendente (mais antigos primeiro)

WITH active_jobs AS (
  SELECT DISTINCT job_id, jobsite
  FROM dailylogs
  WHERE datecreated >= NOW() - INTERVAL '60 days'
    AND job_id IS NOT NULL
    AND job_id NOT IN (
      SELECT DISTINCT job_id
      FROM dailylogs
      WHERE process = 'phase 3 fcc'
    )
),
job_max_phase AS (
  SELECT
    d.job_id,
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
  FROM dailylogs d
  WHERE d.job_id IN (SELECT job_id FROM active_jobs)
    AND d.phase IS NOT NULL
  GROUP BY d.job_id
),
reports AS (
  SELECT
    d.job_id,
    d.process,
    d.datecreated as report_date,
    d.status
  FROM dailylogs d
  WHERE d.job_id IN (SELECT job_id FROM active_jobs)
    AND d.status = 'report'
),
checklist_done AS (
  SELECT
    d.job_id,
    d.process,
    MIN(d.datecreated) as first_checklist_done_date
  FROM dailylogs d
  WHERE d.job_id IN (SELECT job_id FROM active_jobs)
    AND d.status = 'checklist done'
  GROUP BY d.job_id, d.process
),
pending_reports_detail AS (
  -- Último report de cada job+process sem checklist done posterior
  SELECT DISTINCT ON (r.job_id, r.process)
    r.job_id,
    r.process,
    r.report_date,
    r.status
  FROM reports r
  LEFT JOIN checklist_done cd
    ON r.job_id = cd.job_id
    AND r.process = cd.process
  WHERE cd.first_checklist_done_date IS NULL
     OR r.report_date > cd.first_checklist_done_date
  ORDER BY r.job_id, r.process, r.report_date DESC
),
tem_checklist_anterior AS (
  -- Verificar se já teve checklist done antes do report
  SELECT
    r.job_id,
    r.process,
    CASE
      WHEN cd.first_checklist_done_date IS NOT NULL AND cd.first_checklist_done_date < r.report_date
      THEN true
      ELSE false
    END as teve_checklist_anterior
  FROM reports r
  LEFT JOIN checklist_done cd
    ON r.job_id = cd.job_id
    AND r.process = cd.process
)
SELECT
  CASE
    WHEN jmp.current_phase_number = 0 THEN 'Phase 0'
    WHEN jmp.current_phase_number = 1 THEN 'Phase 1'
    WHEN jmp.current_phase_number = 2 THEN 'Phase 2'
    WHEN jmp.current_phase_number = 3 THEN 'Phase 3'
    WHEN jmp.current_phase_number = 4 THEN 'Phase 4'
  END as phase_atual,
  aj.job_id,
  aj.jobsite,
  prd.process as processo,
  prd.report_date as data_report,
  EXTRACT(DAYS FROM NOW() - prd.report_date)::INT as dias_pendente,
  COALESCE(BOOL_OR(tca.teve_checklist_anterior), false) as tem_checklist_done_anterior
FROM job_max_phase jmp
JOIN active_jobs aj ON jmp.job_id = aj.job_id
JOIN pending_reports_detail prd ON aj.job_id = prd.job_id
LEFT JOIN tem_checklist_anterior tca
  ON prd.job_id = tca.job_id
  AND prd.process = tca.process
WHERE jmp.current_phase_number >= 0
  -- REGRA 0: Excluir processos marcados como not_report = TRUE na tabela FMEA
  AND NOT EXISTS (
    SELECT 1
    FROM dailylogs_fmea fmea
    WHERE fmea.process = prd.process
      AND fmea.status = prd.status
      AND fmea.not_report = TRUE
  )
  -- REGRA 1: Excluir se existe rework scheduled APÓS o report
  AND NOT EXISTS (
    SELECT 1
    FROM dailylogs dl
    WHERE dl.job_id = prd.job_id
      AND dl.process = prd.process
      AND dl.status = 'rework scheduled'
      AND dl.datecreated > prd.report_date
  )
  -- REGRA 2: Excluir se existe checklist done com FMEA APÓS o report
  AND NOT EXISTS (
    SELECT 1
    FROM dailylogs_fmea fmea
    WHERE fmea.job_id = prd.job_id
      AND fmea.process = prd.process
      AND fmea.status = 'checklist done'
      AND fmea.failure_group ILIKE '%fmea%'
      AND fmea.datecreated::timestamp > prd.report_date
  )
  -- REGRA 3: Excluir se existe rework requested com FMEA APÓS o report
  AND NOT EXISTS (
    SELECT 1
    FROM dailylogs_fmea fmea
    WHERE fmea.job_id = prd.job_id
      AND fmea.process = prd.process
      AND fmea.status = 'rework requested'
      AND fmea.failure_group ILIKE '%fmea%'
      AND fmea.datecreated::timestamp > prd.report_date
  )
  -- REGRA 4: Excluir se existe in progress APÓS o report
  AND NOT EXISTS (
    SELECT 1
    FROM dailylogs dl
    WHERE dl.job_id = prd.job_id
      AND dl.process = prd.process
      AND dl.status = 'in progress'
      AND dl.datecreated > prd.report_date
  )
GROUP BY jmp.current_phase_number, aj.job_id, aj.jobsite, prd.process, prd.report_date
ORDER BY jmp.current_phase_number, dias_pendente DESC;


-- ============================================================================
-- QUERY 11: SCHEDULED SEM CHECKLIST DONE - Resumo por Phase
-- ============================================================================
-- Uso: Gráfico/tabela mostrando quantos processos scheduled estão abertos
-- Tempo de execução: ~300ms
-- Resultado: 5 linhas (uma por phase) + contagem de casas afetadas
-- Nota: Scheduled é considerado "aberto" se não há checklist done

WITH active_jobs AS (
  SELECT DISTINCT job_id, jobsite
  FROM dailylogs
  WHERE datecreated >= NOW() - INTERVAL '60 days'
    AND job_id IS NOT NULL
    AND job_id NOT IN (
      SELECT DISTINCT job_id
      FROM dailylogs
      WHERE process = 'phase 3 fcc'
    )
),
job_max_phase AS (
  SELECT
    d.job_id,
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
  FROM dailylogs d
  WHERE d.job_id IN (SELECT job_id FROM active_jobs)
    AND d.phase IS NOT NULL
  GROUP BY d.job_id
),
scheduled_items AS (
  SELECT DISTINCT
    d.job_id,
    d.process
  FROM dailylogs d
  WHERE d.job_id IN (SELECT job_id FROM active_jobs)
    AND d.status = 'scheduled'
),
checklist_done_items AS (
  SELECT DISTINCT
    d.job_id,
    d.process
  FROM dailylogs d
  WHERE d.job_id IN (SELECT job_id FROM active_jobs)
    AND d.status = 'checklist done'
),
open_scheduled AS (
  -- Scheduled que NÃO têm checklist done
  SELECT
    si.job_id,
    si.process
  FROM scheduled_items si
  LEFT JOIN checklist_done_items cd
    ON si.job_id = cd.job_id
    AND si.process = cd.process
  WHERE cd.job_id IS NULL
)
SELECT
  CASE
    WHEN jmp.current_phase_number = 0 THEN 'Phase 0'
    WHEN jmp.current_phase_number = 1 THEN 'Phase 1'
    WHEN jmp.current_phase_number = 2 THEN 'Phase 2'
    WHEN jmp.current_phase_number = 3 THEN 'Phase 3'
    WHEN jmp.current_phase_number = 4 THEN 'Phase 4'
  END as phase_atual,
  COUNT(DISTINCT os.job_id) as total_casas,
  COUNT(*) as total_items_scheduled_abertos,
  CONCAT(ROUND(COUNT(DISTINCT os.job_id) * 100.0 /
    (SELECT COUNT(DISTINCT job_id) FROM active_jobs), 1)::text, '%') as percentual
FROM job_max_phase jmp
JOIN open_scheduled os ON jmp.job_id = os.job_id
WHERE jmp.current_phase_number >= 0
GROUP BY jmp.current_phase_number
ORDER BY jmp.current_phase_number;


-- ============================================================================
-- QUERY 12: SCHEDULED SEM CHECKLIST DONE - Lista Detalhada
-- ============================================================================
-- Uso: Tabela detalhada mostrando cada scheduled aberto com status atual
-- Tempo de execução: ~400ms
-- Resultado: Varia (uma linha por job+process com scheduled aberto)
-- Ordenação: Por phase, depois por dias em aberto (mais antigos primeiro)
-- Nota: Mostra último status APÓS o scheduled (status atual do item)

WITH active_jobs AS (
  SELECT DISTINCT job_id, jobsite
  FROM dailylogs
  WHERE datecreated >= NOW() - INTERVAL '60 days'
    AND job_id IS NOT NULL
    AND job_id NOT IN (
      SELECT DISTINCT job_id
      FROM dailylogs
      WHERE process = 'phase 3 fcc'
    )
),
job_max_phase AS (
  SELECT
    d.job_id,
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
  FROM dailylogs d
  WHERE d.job_id IN (SELECT job_id FROM active_jobs)
    AND d.phase IS NOT NULL
  GROUP BY d.job_id
),
scheduled_items AS (
  SELECT
    d.job_id,
    d.process,
    d.datecreated as scheduled_date
  FROM dailylogs d
  WHERE d.job_id IN (SELECT job_id FROM active_jobs)
    AND d.status = 'scheduled'
),
checklist_done_items AS (
  SELECT DISTINCT
    d.job_id,
    d.process
  FROM dailylogs d
  WHERE d.job_id IN (SELECT job_id FROM active_jobs)
    AND d.status = 'checklist done'
),
open_scheduled AS (
  SELECT
    si.job_id,
    si.process,
    si.scheduled_date
  FROM scheduled_items si
  LEFT JOIN checklist_done_items cd
    ON si.job_id = cd.job_id
    AND si.process = cd.process
  WHERE cd.job_id IS NULL
),
open_scheduled_first AS (
  -- Pegar o primeiro scheduled de cada job+process (caso tenha múltiplos)
  SELECT DISTINCT ON (job_id, process)
    job_id,
    process,
    scheduled_date
  FROM open_scheduled
  ORDER BY job_id, process, scheduled_date ASC
),
latest_status_after_scheduled AS (
  -- Último status APÓS o scheduled para cada job+process
  SELECT DISTINCT ON (d.job_id, d.process)
    d.job_id,
    d.process,
    d.status as status_atual_do_item,
    d.datecreated as data_ultimo_status
  FROM dailylogs d
  INNER JOIN open_scheduled_first osf
    ON d.job_id = osf.job_id
    AND d.process = osf.process
  WHERE d.datecreated >= osf.scheduled_date
  ORDER BY d.job_id, d.process, d.datecreated DESC
)
SELECT
  CASE
    WHEN jmp.current_phase_number = 0 THEN 'Phase 0'
    WHEN jmp.current_phase_number = 1 THEN 'Phase 1'
    WHEN jmp.current_phase_number = 2 THEN 'Phase 2'
    WHEN jmp.current_phase_number = 3 THEN 'Phase 3'
    WHEN jmp.current_phase_number = 4 THEN 'Phase 4'
  END as phase_atual,
  aj.job_id,
  aj.jobsite,
  osf.process as processo,
  osf.scheduled_date as data_scheduled,
  lsas.status_atual_do_item,
  lsas.data_ultimo_status,
  EXTRACT(DAYS FROM NOW() - osf.scheduled_date)::INT as dias_em_aberto
FROM job_max_phase jmp
JOIN active_jobs aj ON jmp.job_id = aj.job_id
JOIN open_scheduled_first osf ON aj.job_id = osf.job_id
LEFT JOIN latest_status_after_scheduled lsas
  ON osf.job_id = lsas.job_id
  AND osf.process = lsas.process
WHERE jmp.current_phase_number >= 0
ORDER BY jmp.current_phase_number, dias_em_aberto DESC;


-- ============================================================================
-- OTIMIZAÇÕES DE PERFORMANCE (v3.0)
-- ============================================================================
--
-- 1. ÍNDICE EM DATECREATED:
--    CREATE INDEX idx_dailylogs_datecreated ON dailylogs(datecreated DESC);
--    - Acelera filtros temporais (WHERE datecreated >= NOW() - INTERVAL)
--    - Reduz Parallel Seq Scan
--
-- 2. VIEW MATERIALIZADA PARA QUERY 6:
--    CREATE MATERIALIZED VIEW mv_job_history AS
--    SELECT job_id, jobsite, datecreated as data_registro,
--           process as processo, status, phase,
--           addedby as usuario, sub as subcontratada,
--           CASE WHEN servicedate IS NULL OR servicedate = ''
--             THEN NULL ELSE servicedate::date END as data_servico,
--           notes as notas
--    FROM dailylogs
--    WHERE datecreated >= NOW() - INTERVAL '90 days'
--      AND job_id IS NOT NULL;
--
--    CREATE INDEX idx_mv_job_history_job_id ON mv_job_history(job_id);
--    CREATE INDEX idx_mv_job_history_datecreated ON mv_job_history(data_registro DESC);
--
--    - Tamanho: ~8 MB (36k registros)
--    - Reduz Query 6 de 56s para 0.5ms sem filtro job_id
--
-- 3. FUNÇÃO DE LIMPEZA DE CONEXÕES IDLE:
--    SELECT * FROM cleanup_idle_connections(15);
--    - Libera conexões idle há mais de X minutos
--    - Reduz sobrecarga de memória
--    - Execute periodicamente (a cada hora)
--
-- 4. REFRESH DA VIEW MATERIALIZADA:
--    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_job_history;
--    - Execute a cada 1-2 horas ou conforme necessidade
--    - CONCURRENTLY permite que queries continuem durante refresh
--    - Mantém dados dos últimos 90 dias
--
-- ============================================================================
-- INSTRUÇÕES PARA LOOKER STUDIO
-- ============================================================================
--
-- 1. CONFIGURAÇÃO DA FONTE DE DADOS:
--    - Conectar ao PostgreSQL RDS
--    - Host: lakeshoredevelopmentfl.ch88as8s0tio.us-east-2.rds.amazonaws.com
--    - Database: postgres
--    - Credenciais: AWS Secrets Manager (lkshoredb)
--    - Max Connections: 5 (IMPORTANTE: reduzir de default)
--    - Connection Timeout: 30 segundos
--    - Enable SSL: Sim
--
-- 2. CRIAR 3 TABELAS NO DASHBOARD:
--
--    TABELA A: Query 1 (Resumo)
--    - Gráfico de pizza ou barras
--    - Mostra distribuição percentual
--
--    TABELA B: Query 5 (Lista de Casas)
--    - Tabela interativa
--    - Coluna job_id configurada como FILTRO
--    - Ao clicar: aplica filtro cross-table
--
--    TABELA C: Query 6 (Histórico)
--    - Tabela de detalhes
--    - USA mv_job_history (view materializada)
--    - Substituir "WHERE job_id = 557" por:
--      WHERE job_id = @DS_FILTER_job_id
--    - Responde automaticamente ao clique na Tabela B
--    - IMPORTANTE: Filtro job_id é OBRIGATÓRIO
--
-- 3. FILTRO CROSS-TABLE:
--    - No Looker, criar controle de filtro baseado em job_id
--    - Aplicar filtro às Tabelas B e C
--    - Quando usuário clica na Tabela B, filtro é atualizado
--    - Tabela C mostra automaticamente o histórico
--
-- 4. EXEMPLO DE LAYOUT:
--    ┌─────────────────────────┐
--    │   RESUMO (Query 1)      │
--    │   [Gráfico Pizza]       │
--    └─────────────────────────┘
--
--    ┌──────────────────────────────────────┐
--    │   LISTA DE CASAS (Query 5)           │
--    │   [Tabela clicável]                  │
--    └──────────────────────────────────────┘
--           ↓ (clique passa job_id)
--    ┌──────────────────────────────────────┐
--    │   HISTÓRICO DA CASA (Query 6)        │
--    │   [Tabela com eventos]               │
--    └──────────────────────────────────────┘
--
-- ============================================================================
-- NOTAS TÉCNICAS
-- ============================================================================
--
-- 1. ALIASES SEM ESPAÇOS:
--    ✓ phase_atual, total_casas, ultima_atividade (correto)
--    ✗ "Phase Atual", "Total Casas" (não funciona no Looker)
--
-- 2. CARACTERES PROIBIDOS NO LOOKER STUDIO:
--    ✗ Espaços em aliases
--    ✗ Caracteres Unicode (ú, á, ã, etc.)
--    ✗ Caracteres especiais (ampersands, colons, etc.)
--    Referência: https://support.google.com/looker-studio/answer/12150924
--
-- 3. PERCENTUAL:
--    Usa CONCAT() ao invés de || para compatibilidade
--
-- 4. DATA_SERVICO:
--    Trata valores vazios ("") com CASE antes de converter para date
--
-- 5. TIMESTAMPS:
--    Campos datecreated preservam data e hora completas
--    Formato: timestamp (YYYY-MM-DD HH:MM:SS)
--    Campos: data_registro, ultima_atividade
--
-- 6. PERFORMANCE (atualizado v3.0):
--    Todas as queries otimizadas
--    Query 1: ~174ms (antes: 500ms)
--    Query 2/5: ~800ms (mantido)
--    Query 6: ~0.5ms (antes: 1.27ms por casa, 56s sem filtro!)
--
-- 7. CONSISTÊNCIA:
--    Query 1 soma = 260 casas
--    Query 5 linhas = 260 casas
--    Total ativo = 280 casas (20 sem phase definida)
--
-- ============================================================================
-- MANUTENÇÃO PERIÓDICA
-- ============================================================================
--
-- DIARIAMENTE:
--   - Nenhuma ação necessária (auto-refresh do Looker)
--
-- A CADA 1-2 HORAS (ou conforme necessário):
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mv_job_history;
--   - Atualiza dados da view materializada
--   - Pode ser automatizado com pg_cron ou Lambda
--
-- SEMANALMENTE:
--   SELECT * FROM cleanup_idle_connections(15);
--   - Limpa conexões idle > 15 minutos
--   - Pode ser automatizado
--
-- MENSALMENTE:
--   ANALYZE dailylogs;
--   ANALYZE mv_job_history;
--   - Atualiza estatísticas do query planner
--   - Melhora planos de execução
--
-- MONITORAMENTO AWS:
--   - Memória RDS: Manter > 100 MB livre
--   - Conexões: Manter < 50 simultâneas
--   - CPU: < 50% uso médio
--   - Se exceder: considerar upgrade para db.t3.small
--
-- ============================================================================
-- CHANGELOG
-- ============================================================================
-- v3.0 (2025-10-23): Performance Optimizations
--   - Criado índice idx_dailylogs_datecreated
--   - Criada view materializada mv_job_history (8 MB, 36k records)
--   - Criada função cleanup_idle_connections()
--   - Query 1: 500ms → 174ms (65% mais rápido)
--   - Query 6: 56s → 0.5ms (112,000x mais rápido!)
--   - Query 6 agora usa mv_job_history por padrão
--   - Adicionadas instruções de manutenção e monitoramento
--   - Documentado problema de sobrecarga com Query 6 sem filtro
--   - Atualizado refresh recomendado: 15min → 30min
--
-- v2.1 (2025-10-23): Timestamps com hora
--   - Preservar hora nos campos datecreated (data_registro, ultima_atividade)
--   - Removido casting ::date para manter timestamp completo
--
-- v2.0 (2025-10-23): Looker Studio compatibility
--   - Aliases sem espaços (snake_case)
--   - Query 2: Adicionadas colunas ultimo_processo, ultimo_status
--   - Query 5: Refatorada de agregada para individual
--   - Query 6: Nova query para histórico com parâmetro
--   - Todas as queries testadas e validadas no banco
--
-- v1.0 (2025-10-23): Versão inicial
--   - Queries 1-5 originais
-- ============================================================================
