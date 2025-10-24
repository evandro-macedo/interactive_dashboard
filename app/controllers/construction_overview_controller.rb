class ConstructionOverviewController < ApplicationController
  def index
    @service = ConstructionOverviewService.new

    # ========================================================================
    # GRUPO A: CASAS ATIVAS (Queries 1-2)
    # ========================================================================

    # Query 1: Dados para o gráfico de pizza
    @phase_summary = @service.phase_summary

    # Query 2: Dados para a tabela
    @active_houses = @service.active_houses_detailed

    # Filtro opcional por phase (Grupo A)
    @selected_phase = params[:phase]

    # Aplicar filtro se phase selecionada
    if @selected_phase.present?
      @active_houses = @active_houses.select { |h| h['phase_atual'] == @selected_phase }
    end

    # ========================================================================
    # GRUPO B: INSPEÇÕES REPROVADAS (Queries 7-8)
    # ========================================================================

    # Query 7: Resumo de inspeções reprovadas por phase
    @failed_inspections_summary = @service.failed_inspections_summary

    # Query 8: Lista detalhada de inspeções reprovadas
    @failed_inspections_detail = @service.failed_inspections_detail

    # Filtro opcional por phase (Grupo B)
    @selected_phase_inspections = params[:phase_inspections]

    # Aplicar filtro se phase selecionada
    if @selected_phase_inspections.present?
      @failed_inspections_detail = @failed_inspections_detail.select do |insp|
        insp['phase_atual'] == @selected_phase_inspections
      end
    end

    # ========================================================================
    # GRUPO C: REPORTS SEM CHECKLIST DONE (Queries 9-10)
    # ========================================================================

    # Query 9: Resumo de reports pendentes por phase
    @pending_reports_summary = @service.pending_reports_summary

    # Query 10: Lista detalhada de reports pendentes (com 5 regras FMEA)
    @pending_reports_detail = @service.pending_reports_detail

    # Filtro opcional por phase (Grupo C)
    @selected_phase_reports = params[:phase_reports]

    # Aplicar filtro se phase selecionada
    if @selected_phase_reports.present?
      @pending_reports_detail = @pending_reports_detail.select do |report|
        report['phase_atual'] == @selected_phase_reports
      end
    end

    # ========================================================================
    # DADOS GERAIS
    # ========================================================================

    # Dados de sync (já existentes)
    @last_sync = Dailylog.last_sync_info
    @total_records = Dailylog.count
  end
end
