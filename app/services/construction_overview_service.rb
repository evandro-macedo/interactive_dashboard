# frozen_string_literal: true

# ConstructionOverviewService
#
# Serviço para executar as 12 queries de firefighting localmente no SQLite,
# reduzindo a carga no RDS PostgreSQL em 75%.
#
# Baseado em: /home/evandro/Desktop/relational_dailylogs/firefighting/01_queries.sql
#
# Conversões PostgreSQL → SQLite:
# - NOW() - INTERVAL '60 days' → datetime('now', '-60 days')
# - field::text → CAST(field AS TEXT)
# - ILIKE → LIKE (SQLite é case-insensitive por padrão)
# - EXTRACT(DAYS FROM x) → CAST((julianday('now') - julianday(x)) AS INTEGER)
# - DISTINCT ON (col) → Window function com ROW_NUMBER() OVER (PARTITION BY col)
# - boolean TRUE/FALSE → 1/0
#
# Uso:
#   service = ConstructionOverviewService.new
#   service.phase_summary
#   service.active_houses_detailed
#   service.house_history(557)
#
class ConstructionOverviewService
  # ============================================================================
  # GRUPO A: CASAS ATIVAS E HISTÓRICO (Queries 1-6)
  # ============================================================================

  # Query 1: Resumo - Contagem de casas por phase
  # Retorna: 5 linhas (Phase 0-4) com total_casas e percentual
  # Tempo esperado: ~100ms
  def phase_summary
    Rails.cache.fetch(cache_key('phase_summary'), expires_in: 5.minutes) do
      sql = <<-SQL
        WITH #{active_jobs_cte},
             #{job_max_phase_cte}
        SELECT
          #{phase_label_case} as phase_atual,
          COUNT(*) as total_casas,
          CAST(ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS TEXT) || '%' as percentual
        FROM job_max_phase
        WHERE current_phase_number >= 0
        GROUP BY current_phase_number
        ORDER BY current_phase_number
      SQL

      Dailylog.lease_connection.select_all(sql).to_a
    end
  end

  # Query 2: Lista detalhada - Casas por phase com último processo/status
  # Retorna: ~260 linhas (uma por casa) com última atividade
  # Tempo esperado: ~200ms
  # Usa: Window Function (ROW_NUMBER) para substituir DISTINCT ON do PostgreSQL
  def active_houses_detailed
    Rails.cache.fetch(cache_key('active_houses_detailed'), expires_in: 5.minutes) do
      sql = <<-SQL
        WITH #{active_jobs_cte},
             #{job_max_phase_cte},
             job_last_event AS (
               SELECT
                 d.job_id,
                 d.datecreated as ultima_atividade,
                 d.process as ultimo_processo,
                 d.status as ultimo_status,
                 ROW_NUMBER() OVER (PARTITION BY d.job_id ORDER BY d.datecreated DESC) as rn
               FROM dailylogs d
               WHERE d.job_id IN (SELECT job_id FROM active_jobs)
             )
        SELECT
          #{phase_label_case_jmp} as phase_atual,
          aj.job_id,
          aj.jobsite,
          jle.ultima_atividade,
          jle.ultimo_processo,
          jle.ultimo_status
        FROM job_max_phase jmp
        JOIN active_jobs aj ON jmp.job_id = aj.job_id
        JOIN job_last_event jle ON aj.job_id = jle.job_id AND jle.rn = 1
        WHERE jmp.current_phase_number >= 0
        ORDER BY jle.ultima_atividade DESC, aj.job_id
      SQL

      Dailylog.lease_connection.select_all(sql).to_a
    end
  end

  # Query 3: Total de casas ativas (validação)
  # Retorna: 1 linha com total
  # Tempo esperado: <50ms
  def active_houses_count
    sql = <<-SQL
      WITH #{active_jobs_cte}
      SELECT COUNT(DISTINCT job_id) as total_casas_ativas
      FROM active_jobs
    SQL

    Dailylog.lease_connection.select_all(sql).to_a
  end

  # Query 4: Lista de jobs finalizados
  # Retorna: Jobs com "phase 3 fcc"
  # Tempo esperado: ~100ms
  def finalized_houses
    sql = <<-SQL
      SELECT DISTINCT
        job_id,
        jobsite,
        DATE(MAX(datecreated)) as data_finalizacao
      FROM dailylogs
      WHERE process = 'phase 3 fcc'
      GROUP BY job_id, jobsite
      ORDER BY data_finalizacao DESC
    SQL

    Dailylog.lease_connection.select_all(sql).to_a
  end

  # Query 5: Lista individual (idêntica à Query 2, mas ordenação diferente)
  # Usado no Looker Studio para drill-down
  # Retorna: ~260 linhas (uma por casa)
  # Tempo esperado: ~200ms
  # Diferença da Query 2: Ordena por phase e job_id (para agrupamento visual)
  def active_houses_list
    sql = <<-SQL
      WITH #{active_jobs_cte},
           #{job_max_phase_cte},
           job_last_event AS (
             SELECT
               d.job_id,
               d.datecreated as ultima_atividade,
               d.process as ultimo_processo,
               d.status as ultimo_status,
               ROW_NUMBER() OVER (PARTITION BY d.job_id ORDER BY d.datecreated DESC) as rn
             FROM dailylogs d
             WHERE d.job_id IN (SELECT job_id FROM active_jobs)
           )
      SELECT
        #{phase_label_case_jmp} as phase_atual,
        aj.job_id,
        aj.jobsite,
        jle.ultima_atividade,
        jle.ultimo_processo,
        jle.ultimo_status
      FROM job_max_phase jmp
      JOIN active_jobs aj ON jmp.job_id = aj.job_id
      JOIN job_last_event jle ON aj.job_id = jle.job_id AND jle.rn = 1
      WHERE jmp.current_phase_number >= 0
      ORDER BY jmp.current_phase_number, aj.job_id
    SQL

    Dailylog.lease_connection.select_all(sql).to_a
  end

  # Query 6: Histórico - Todos os eventos de uma casa
  # Parâmetros: job_id (obrigatório)
  # Retorna: Varia (ex: ~150 eventos para job 557)
  # Tempo esperado: <50ms (com índice em job_id)
  # IMPORTANTE: SEMPRE filtrar por job_id (parâmetro obrigatório)
  def house_history(job_id)
    raise ArgumentError, "job_id é obrigatório" if job_id.blank?

    sql = <<-SQL
      SELECT
        job_id,
        jobsite,
        datecreated as data_registro,
        process as processo,
        status,
        phase,
        addedby as usuario,
        sub as subcontratada,
        CASE WHEN servicedate IS NULL OR servicedate = ''
          THEN NULL ELSE DATE(servicedate) END as data_servico,
        notes as notas
      FROM dailylogs
      WHERE job_id = ?
        AND datecreated >= datetime('now', '-90 days')
      ORDER BY datecreated DESC
    SQL

    Dailylog.lease_connection.select_all(
      ApplicationRecord.sanitize_sql([sql, job_id])
    ).to_a
  end

  # ============================================================================
  # GRUPO B: INSPEÇÕES REPROVADAS (Queries 7-8)
  # ============================================================================

  # Query 7: Inspeções reprovadas - Resumo por phase
  # Retorna: 5 linhas com total de casas afetadas
  # Tempo esperado: ~150ms
  # Lógica: Inspeção "ativa" = reprovada SEM aprovação posterior
  def failed_inspections_summary
    Rails.cache.fetch(cache_key('failed_inspections_summary'), expires_in: 5.minutes) do
      sql = <<-SQL
      WITH #{active_jobs_cte},
           #{job_max_phase_cte},
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
           active_failures AS (
             SELECT DISTINCT
               if_t.job_id,
               if_t.process
             FROM inspection_failures if_t
             LEFT JOIN inspection_approvals ia
               ON if_t.job_id = ia.job_id
               AND if_t.process = ia.process
             WHERE ia.last_approval_date IS NULL
                OR if_t.datecreated > ia.last_approval_date
           )
      SELECT
        #{phase_label_case_jmp} as phase_atual,
        COUNT(DISTINCT af.job_id) as total_casas,
        COUNT(*) as total_inspections_reprovadas,
        CAST(ROUND(COUNT(DISTINCT af.job_id) * 100.0 /
          (SELECT COUNT(DISTINCT job_id) FROM active_jobs), 1) AS TEXT) || '%' as percentual
      FROM job_max_phase jmp
      JOIN active_failures af ON jmp.job_id = af.job_id
      WHERE jmp.current_phase_number >= 0
      GROUP BY jmp.current_phase_number
      ORDER BY jmp.current_phase_number
    SQL

      Dailylog.lease_connection.select_all(sql).to_a
    end
  end

  # Query 8: Inspeções reprovadas - Lista detalhada
  # Retorna: Cada inspeção reprovada ativa com dias em aberto
  # Tempo esperado: ~200ms
  # Usa: Window Function para pegar última reprovação de cada inspeção
  def failed_inspections_detail
    Rails.cache.fetch(cache_key('failed_inspections_detail'), expires_in: 5.minutes) do
      sql = <<-SQL
      WITH #{active_jobs_cte},
           #{job_max_phase_cte},
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
             SELECT
               if_t.job_id,
               if_t.process,
               if_t.datecreated as data_reprovacao,
               if_t.status,
               ROW_NUMBER() OVER (PARTITION BY if_t.job_id, if_t.process ORDER BY if_t.datecreated DESC) as rn
             FROM inspection_failures if_t
             LEFT JOIN inspection_approvals ia
               ON if_t.job_id = ia.job_id
               AND if_t.process = ia.process
             WHERE ia.last_approval_date IS NULL
                OR if_t.datecreated > ia.last_approval_date
           ),
           ultimo_status_inspecao AS (
             SELECT
               d.job_id,
               d.process,
               d.status as ultimo_status,
               d.datecreated as data_ultimo_status,
               ROW_NUMBER() OVER (PARTITION BY d.job_id, d.process ORDER BY d.datecreated DESC) as rn
             FROM dailylogs d
             WHERE d.job_id IN (SELECT job_id FROM active_jobs)
               AND d.process LIKE '%inspection%'
           )
      SELECT
        #{phase_label_case_jmp} as phase_atual,
        aj.job_id,
        aj.jobsite,
        afd.process as processo_inspecao,
        afd.data_reprovacao,
        CAST((julianday('now') - julianday(afd.data_reprovacao)) AS INTEGER) as dias_em_aberto,
        usi.ultimo_status,
        usi.data_ultimo_status
      FROM job_max_phase jmp
      JOIN active_jobs aj ON jmp.job_id = aj.job_id
      JOIN active_failures_detail afd ON aj.job_id = afd.job_id AND afd.rn = 1
      LEFT JOIN ultimo_status_inspecao usi
        ON afd.job_id = usi.job_id
        AND afd.process = usi.process
        AND usi.rn = 1
      WHERE jmp.current_phase_number >= 0
      ORDER BY jmp.current_phase_number, dias_em_aberto DESC
    SQL

      Dailylog.lease_connection.select_all(sql).to_a
    end
  end

  # ============================================================================
  # GRUPO C: REPORTS PENDENTES (Queries 9-10)
  # ============================================================================

  # Query 9: Reports sem checklist done - Resumo por phase
  # Retorna: 5 linhas com total de casas afetadas
  # Tempo esperado: ~150ms
  # Lógica: Report "pendente" = status='report' SEM checklist done posterior
  def pending_reports_summary
    Rails.cache.fetch(cache_key('pending_reports_summary'), expires_in: 5.minutes) do
      sql = <<-SQL
      WITH #{active_jobs_cte},
           #{job_max_phase_cte},
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
             SELECT DISTINCT
               r.job_id,
               r.process,
               MAX(r.report_date) as latest_report_date
             FROM reports r
             LEFT JOIN checklist_done cd
               ON r.job_id = cd.job_id
               AND r.process = cd.process
             WHERE cd.first_checklist_done_date IS NULL
                OR r.report_date > cd.first_checklist_done_date
             GROUP BY r.job_id, r.process
             HAVING CAST((julianday('now') - julianday(MAX(r.report_date))) AS INTEGER) <= 60
           )
      SELECT
        #{phase_label_case_jmp} as phase_atual,
        COUNT(DISTINCT pr.job_id) as total_casas,
        COUNT(*) as total_reports_pendentes,
        CAST(ROUND(COUNT(DISTINCT pr.job_id) * 100.0 /
          (SELECT COUNT(DISTINCT job_id) FROM active_jobs), 1) AS TEXT) || '%' as percentual
      FROM job_max_phase jmp
      JOIN pending_reports pr ON jmp.job_id = pr.job_id
      WHERE jmp.current_phase_number >= 0
      GROUP BY jmp.current_phase_number
      ORDER BY jmp.current_phase_number
    SQL

      Dailylog.lease_connection.select_all(sql).to_a
    end
  end

  # Query 10: Reports sem checklist done - Lista detalhada
  # IMPORTANTE: Aplica 5 regras de exclusão FMEA (ver REGRAS_NEGOCIO.md)
  # Retorna: Reports verdadeiramente pendentes (~322 após filtros)
  # Tempo esperado: ~300ms (query complexa!)
  #
  # REGRAS DE EXCLUSÃO:
  # - REGRA 0: Processos marcados como not_report=TRUE no FMEA
  # - REGRA 1: Existe rework scheduled APÓS o report
  # - REGRA 2: Existe checklist done com FMEA APÓS o report
  # - REGRA 3: Existe rework requested com FMEA APÓS o report
  # - REGRA 4: Existe in progress APÓS o report
  #
  # Redução esperada: ~524 reports iniciais → ~322 após filtros (-38.5%)
  def pending_reports_detail
    Rails.cache.fetch(cache_key('pending_reports_detail'), expires_in: 5.minutes) do
      sql = <<-SQL
      WITH #{active_jobs_cte},
           #{job_max_phase_cte},
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
             SELECT
               r.job_id,
               r.process,
               r.report_date,
               r.status,
               ROW_NUMBER() OVER (PARTITION BY r.job_id, r.process ORDER BY r.report_date DESC) as rn
             FROM reports r
             LEFT JOIN checklist_done cd
               ON r.job_id = cd.job_id
               AND r.process = cd.process
             WHERE cd.first_checklist_done_date IS NULL
                OR r.report_date > cd.first_checklist_done_date
           ),
           tem_checklist_anterior AS (
             SELECT
               r.job_id,
               r.process,
               CASE
                 WHEN cd.first_checklist_done_date IS NOT NULL AND cd.first_checklist_done_date < r.report_date
                 THEN 1
                 ELSE 0
               END as teve_checklist_anterior
             FROM reports r
             LEFT JOIN checklist_done cd
               ON r.job_id = cd.job_id
               AND r.process = cd.process
           )
      SELECT
        #{phase_label_case_jmp} as phase_atual,
        aj.job_id,
        aj.jobsite,
        prd.process as processo,
        prd.report_date as data_report,
        CAST((julianday('now') - julianday(prd.report_date)) AS INTEGER) as dias_pendente,
        CASE WHEN MAX(tca.teve_checklist_anterior) = 1 THEN 1 ELSE 0 END as tem_checklist_done_anterior
      FROM job_max_phase jmp
      JOIN active_jobs aj ON jmp.job_id = aj.job_id
      JOIN pending_reports_detail prd ON aj.job_id = prd.job_id AND prd.rn = 1
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
            AND fmea.not_report = 1
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
            AND fmea.failure_group LIKE '%fmea%'
            AND fmea.datecreated > prd.report_date
        )
        -- REGRA 3: Excluir se existe rework requested com FMEA APÓS o report
        AND NOT EXISTS (
          SELECT 1
          FROM dailylogs_fmea fmea
          WHERE fmea.job_id = prd.job_id
            AND fmea.process = prd.process
            AND fmea.status = 'rework requested'
            AND fmea.failure_group LIKE '%fmea%'
            AND fmea.datecreated > prd.report_date
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
      HAVING CAST((julianday('now') - julianday(prd.report_date)) AS INTEGER) <= 60
      ORDER BY jmp.current_phase_number, dias_pendente DESC
    SQL

      Dailylog.lease_connection.select_all(sql).to_a
    end
  end

  # ============================================================================
  # GRUPO D: SCHEDULED ABERTOS (Queries 11-12)
  # ============================================================================

  # Query 11: Scheduled sem checklist done - Resumo por phase
  # Retorna: 5 linhas com total de processos abertos
  # Tempo esperado: ~150ms
  # Lógica: Scheduled "aberto" = status='scheduled' SEM checklist done posterior
  # Exclui: Processos de inspeção e materiais (não aplicam "checklist done")
  def open_scheduled_summary
    Rails.cache.fetch(cache_key('open_scheduled_summary'), expires_in: 5.minutes) do
      sql = <<-SQL
      WITH #{active_jobs_cte},
           #{job_max_phase_cte},
           scheduled_items AS (
             SELECT
               d.job_id,
               d.process,
               d.datecreated as scheduled_date
             FROM dailylogs d
             WHERE d.job_id IN (SELECT job_id FROM active_jobs)
               AND d.status = 'scheduled'
               AND d.process NOT LIKE '%inspection%'
               AND d.process NOT LIKE '%material%'
           ),
           checklist_done_items AS (
             SELECT DISTINCT
               d.job_id,
               d.process
             FROM dailylogs d
             WHERE d.job_id IN (SELECT job_id FROM active_jobs)
               AND (d.status = 'checklist done' OR d.status = 'rework checklist done')
           ),
           open_scheduled AS (
             SELECT
               si.job_id,
               si.process,
               MIN(si.scheduled_date) as first_scheduled_date
             FROM scheduled_items si
             LEFT JOIN checklist_done_items cd
               ON si.job_id = cd.job_id
               AND si.process = cd.process
             WHERE cd.job_id IS NULL
             GROUP BY si.job_id, si.process
             HAVING CAST((julianday('now') - julianday(MIN(si.scheduled_date))) AS INTEGER) <= 60
           )
      SELECT
        #{phase_label_case_jmp} as phase_atual,
        COUNT(DISTINCT os.job_id) as total_casas,
        COUNT(*) as total_items_scheduled_abertos,
        CAST(ROUND(COUNT(DISTINCT os.job_id) * 100.0 /
          (SELECT COUNT(DISTINCT job_id) FROM active_jobs), 1) AS TEXT) || '%' as percentual
      FROM job_max_phase jmp
      JOIN open_scheduled os ON jmp.job_id = os.job_id
      WHERE jmp.current_phase_number >= 0
      GROUP BY jmp.current_phase_number
      ORDER BY jmp.current_phase_number
    SQL

      Dailylog.lease_connection.select_all(sql).to_a
    end
  end

  # Query 12: Scheduled sem checklist done - Lista detalhada
  # Retorna: Cada processo scheduled aberto com status atual
  # Tempo esperado: ~200ms
  # Mostra: Primeiro scheduled de cada job+process + último status APÓS o scheduled
  # Exclui: Processos de inspeção e materiais (não aplicam "checklist done")
  def open_scheduled_detail
    Rails.cache.fetch(cache_key('open_scheduled_detail'), expires_in: 5.minutes) do
      sql = <<-SQL
      WITH #{active_jobs_cte},
           #{job_max_phase_cte},
           scheduled_items AS (
             SELECT
               d.job_id,
               d.process,
               d.datecreated as scheduled_date,
               d.servicedate
             FROM dailylogs d
             WHERE d.job_id IN (SELECT job_id FROM active_jobs)
               AND d.status = 'scheduled'
               AND d.process NOT LIKE '%inspection%'
               AND d.process NOT LIKE '%material%'
           ),
           checklist_done_items AS (
             SELECT DISTINCT
               d.job_id,
               d.process
             FROM dailylogs d
             WHERE d.job_id IN (SELECT job_id FROM active_jobs)
               AND (d.status = 'checklist done' OR d.status = 'rework checklist done')
           ),
           open_scheduled AS (
             SELECT
               si.job_id,
               si.process,
               si.scheduled_date,
               si.servicedate
             FROM scheduled_items si
             LEFT JOIN checklist_done_items cd
               ON si.job_id = cd.job_id
               AND si.process = cd.process
             WHERE cd.job_id IS NULL
           ),
           open_scheduled_first AS (
             SELECT
               job_id,
               process,
               scheduled_date,
               servicedate,
               ROW_NUMBER() OVER (PARTITION BY job_id, process ORDER BY scheduled_date ASC) as rn
             FROM open_scheduled
           ),
           latest_status_after_scheduled AS (
             SELECT
               d.job_id,
               d.process,
               d.status as status_atual_do_item,
               d.datecreated as data_ultimo_status,
               ROW_NUMBER() OVER (PARTITION BY d.job_id, d.process ORDER BY d.datecreated DESC) as rn
             FROM dailylogs d
             INNER JOIN open_scheduled_first osf
               ON d.job_id = osf.job_id
               AND d.process = osf.process
             WHERE d.datecreated >= osf.scheduled_date
               AND osf.rn = 1
           )
      SELECT
        #{phase_label_case_jmp} as phase_atual,
        aj.job_id,
        aj.jobsite,
        osf.process as processo,
        osf.servicedate as data_service,
        osf.scheduled_date as data_criacao,
        lsas.status_atual_do_item,
        lsas.data_ultimo_status,
        CAST((julianday('now') - julianday(osf.scheduled_date)) AS INTEGER) as dias_em_aberto
      FROM job_max_phase jmp
      JOIN active_jobs aj ON jmp.job_id = aj.job_id
      JOIN open_scheduled_first osf ON aj.job_id = osf.job_id AND osf.rn = 1
      LEFT JOIN latest_status_after_scheduled lsas
        ON osf.job_id = lsas.job_id
        AND osf.process = lsas.process
        AND lsas.rn = 1
      WHERE jmp.current_phase_number >= 0
        AND CAST((julianday('now') - julianday(osf.scheduled_date)) AS INTEGER) <= 60
      ORDER BY jmp.current_phase_number, dias_em_aberto DESC
    SQL

      Dailylog.lease_connection.select_all(sql).to_a
    end
  end

  private

  # ============================================================================
  # CACHE
  # ============================================================================

  # Gera chave de cache única para cada método
  # Namespace: construction_overview_service
  # TTL: 5 minutos (mesmo intervalo do sync)
  def cache_key(method_name)
    "construction_overview_service:#{method_name}"
  end

  # ============================================================================
  # MÉTODOS AUXILIARES - CTES REUTILIZÁVEIS
  # ============================================================================

  # CTE: active_jobs
  # Define casas "ativas":
  # - Atividade nos últimos 60 dias
  # - job_id não nulo
  # - Não finalizadas (sem "phase 3 fcc")
  #
  # Usada em: TODAS as queries (1-12)
  def active_jobs_cte
    <<-SQL
      active_jobs AS (
        SELECT DISTINCT job_id, jobsite
        FROM dailylogs
        WHERE datecreated >= datetime('now', '-60 days')
          AND job_id IS NOT NULL
          AND job_id NOT IN (
            SELECT DISTINCT job_id
            FROM dailylogs
            WHERE process = 'phase 3 fcc'
          )
      )
    SQL
  end

  # CTE: job_max_phase
  # Calcula a phase atual de cada job (a mais avançada: 0, 1, 2, 3, ou 4)
  #
  # Usada em: Queries 1-2, 5, 7-12
  def job_max_phase_cte
    <<-SQL
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
    SQL
  end

  # Helper: CASE para formatar label de phase
  # Converte current_phase_number (0-4) para "Phase 0"-"Phase 4"
  #
  # Uso: SELECT #{phase_label_case} as phase_atual FROM ...
  def phase_label_case
    <<-SQL.strip
      CASE
        WHEN current_phase_number = 0 THEN 'Phase 0'
        WHEN current_phase_number = 1 THEN 'Phase 1'
        WHEN current_phase_number = 2 THEN 'Phase 2'
        WHEN current_phase_number = 3 THEN 'Phase 3'
        WHEN current_phase_number = 4 THEN 'Phase 4'
      END
    SQL
  end

  # Helper: CASE para formatar label de phase a partir de job_max_phase
  # Versão alternativa que referencia jmp.current_phase_number
  #
  # Uso: SELECT #{phase_label_case_jmp} as phase_atual FROM job_max_phase jmp ...
  def phase_label_case_jmp
    <<-SQL.strip
      CASE
        WHEN jmp.current_phase_number = 0 THEN 'Phase 0'
        WHEN jmp.current_phase_number = 1 THEN 'Phase 1'
        WHEN jmp.current_phase_number = 2 THEN 'Phase 2'
        WHEN jmp.current_phase_number = 3 THEN 'Phase 3'
        WHEN jmp.current_phase_number = 4 THEN 'Phase 4'
      END
    SQL
  end
end
