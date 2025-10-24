class ConstructionOverviewController < ApplicationController
  def index
    @service = ConstructionOverviewService.new

    # Query 1: Dados para o gráfico de pizza
    @phase_summary = @service.phase_summary

    # Query 2: Dados para a tabela
    @active_houses = @service.active_houses_detailed

    # Filtro opcional por phase
    @selected_phase = params[:phase]

    # Aplicar filtro se phase selecionada
    if @selected_phase.present?
      @active_houses = @active_houses.select { |h| h['phase_atual'] == @selected_phase }
    end

    # Dados de sync (já existentes)
    @last_sync = Dailylog.last_sync_info
    @total_records = Dailylog.count
  end
end
