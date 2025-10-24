class SyncDailylogsJob < ApplicationJob
  queue_as :default

  def perform
    start_time = Time.current
    records_synced = 0
    records_added = 0
    new_record_ids = []

    begin
      # Capturar IDs existentes ANTES da sincronização
      existing_job_ids = Dailylog.pluck(:job_id).to_set

      # Buscar última sincronização BEM-SUCEDIDA para comparação
      last_sync = SyncLog.where(table_name: "dailylogs")
                         .where(error_message: nil)
                         .order(synced_at: :desc)
                         .first
      previous_count = last_sync&.records_synced || 0

      # Buscar registros do PostgreSQL externo
      postgres_records = PostgresSourceDailylog.all.to_a

      Rails.logger.info "Syncing #{postgres_records.size} records from PostgreSQL to SQLite..."

      # Sincronizar dados
      ActiveRecord::Base.transaction do
        # Limpar tabela SQLite local
        Dailylog.delete_all

        # Preparar dados para inserção em batch
        records_to_insert = postgres_records.map do |pg_record|
          {
            job_id: pg_record.job_id,
            site_number: pg_record.site_number,
            logtitle: pg_record.logtitle,
            notes: pg_record.notes,
            process: pg_record.process,
            status: pg_record.status,
            phase: pg_record.phase,
            jobsite: pg_record.jobsite,
            county: pg_record.county,
            sector: pg_record.sector,
            site: pg_record.site,
            permit: pg_record.permit,
            parcel: pg_record.parcel,
            model_code: pg_record.model_code,
            addedby: pg_record.addedby,
            cell: pg_record.cell,
            datecreated: pg_record.datecreated,
            dateonly: pg_record.dateonly,
            enddate: pg_record.enddate,
            servicedate: pg_record.servicedate,
            startdate: pg_record.startdate,
            sub: pg_record.sub,
            hash_unique: pg_record.hash_unique,
            created_at: Time.current,
            updated_at: Time.current
          }
        end

        # Inserir todos de uma vez usando insert_all (muito mais rápido)
        unless records_to_insert.empty?
          Dailylog.insert_all(records_to_insert)
          records_synced = records_to_insert.size
        end
      end

      # Identificar novos registros (job_ids que não existiam antes)
      if records_synced > 0
        new_job_ids = postgres_records.map(&:job_id) - existing_job_ids.to_a

        if new_job_ids.any?
          new_records = Dailylog.where(job_id: new_job_ids)
          new_record_ids = new_records.pluck(:id)
          records_added = new_records.count

          Rails.logger.info "Detected #{records_added} new records with job_ids: #{new_job_ids.first(10).inspect}..."
        else
          records_added = 0
        end
      else
        records_added = 0
      end

      # Registrar sucesso
      duration = ((Time.current - start_time) * 1000).to_i
      SyncLog.create!(
        table_name: "dailylogs",
        records_synced: records_synced,
        records_added: records_added,
        synced_at: Time.current,
        duration_ms: duration
      )

      Rails.logger.info "Dailylogs synced: #{records_synced} records (#{records_added} new) in #{duration}ms"

      # Sync dailylogs_fmea table
      sync_dailylogs_fmea

      # Clear cache after sync completes (both dailylogs and fmea)
      # This ensures fresh data is loaded on next request
      clear_construction_overview_cache

      # Broadcast Turbo Stream update to Construction Overview page
      broadcast_construction_overview_update

    rescue StandardError => e
      # Registrar erro
      duration = ((Time.current - start_time) * 1000).to_i
      SyncLog.create!(
        table_name: "dailylogs",
        records_synced: 0,
        records_added: 0,
        synced_at: Time.current,
        duration_ms: duration,
        error_message: e.message
      )

      Rails.logger.error "Dailylogs sync failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      # Re-raise para Solid Queue retry
      raise e
    end
  end

  private

  def sync_dailylogs_fmea
    start_time = Time.current
    records_synced = 0

    begin
      # Buscar registros FMEA do PostgreSQL externo
      postgres_fmea_records = PostgresSourceDailylogFmea.all.to_a

      Rails.logger.info "Syncing #{postgres_fmea_records.size} FMEA records from PostgreSQL to SQLite..."

      # Sincronizar dados
      ActiveRecord::Base.transaction do
        # Limpar tabela SQLite local
        DailylogFmea.delete_all

        # Preparar dados para inserção em batch
        fmea_records_to_insert = postgres_fmea_records.map do |pg_record|
          {
            job_id: pg_record.job_id,
            site_number: pg_record.site_number,
            process: pg_record.process,
            status: pg_record.status,
            phase: pg_record.phase,
            failure_group: pg_record.failure_group,
            failure_item: pg_record.failure_item,
            is_multitag: pg_record.is_multitag,
            not_report: pg_record.not_report,
            checklist_done: pg_record.checklist_done,
            fees: pg_record.fees,
            datecreated: pg_record.datecreated,
            addedby: pg_record.addedby,
            logtitle: pg_record.logtitle,
            notes: pg_record.notes,
            county: pg_record.county,
            sector: pg_record.sector,
            cell: pg_record.cell,
            jobsite: pg_record.jobsite,
            site: pg_record.site,
            permit: pg_record.permit,
            parcel: pg_record.parcel,
            model_code: pg_record.model_code,
            created_at: Time.current,
            updated_at: Time.current
          }
        end

        # Inserir todos de uma vez usando insert_all (muito mais rápido)
        unless fmea_records_to_insert.empty?
          DailylogFmea.insert_all(fmea_records_to_insert)
          records_synced = fmea_records_to_insert.size
        end
      end

      # Registrar sucesso
      duration = ((Time.current - start_time) * 1000).to_i
      SyncLog.create!(
        table_name: "dailylogs_fmea",
        records_synced: records_synced,
        synced_at: Time.current,
        duration_ms: duration
      )

      Rails.logger.info "Dailylogs FMEA synced: #{records_synced} records in #{duration}ms"
    rescue StandardError => e
      # Registrar erro
      duration = ((Time.current - start_time) * 1000).to_i
      SyncLog.create!(
        table_name: "dailylogs_fmea",
        records_synced: 0,
        synced_at: Time.current,
        duration_ms: duration,
        error_message: e.message
      )

      Rails.logger.error "Dailylogs FMEA sync failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      # Don't re-raise - FMEA sync failure shouldn't fail the whole job
    end
  end

  def clear_construction_overview_cache
    # Clear all cached queries from ConstructionOverviewService
    # This invalidates the 5-minute cache after sync completes
    cache_keys = %w[
      phase_summary
      active_houses_detailed
      failed_inspections_summary
      failed_inspections_detail
      pending_reports_summary
      pending_reports_detail
      open_scheduled_summary
      open_scheduled_detail
    ]

    cache_keys.each do |key|
      Rails.cache.delete("construction_overview_service:#{key}")
    end

    Rails.logger.info "Cache cleared for Construction Overview (#{cache_keys.size} keys)"
  end

  def broadcast_construction_overview_update
    # Instanciar service e executar queries
    service = ConstructionOverviewService.new

    phase_summary = service.phase_summary
    active_houses = service.active_houses_detailed
    failed_inspections_summary = service.failed_inspections_summary
    failed_inspections_detail = service.failed_inspections_detail
    total_records = Dailylog.count

    # Usar renderer do controller para ter contexto correto de partials
    # Isso garante que render "phase_table" funcione dentro de construction_overview/_content
    html = ConstructionOverviewController.render(
      partial: "construction_overview/content",
      locals: {
        total_records: total_records,
        phase_summary: phase_summary,
        active_houses: active_houses,
        selected_phase: nil,  # Broadcast não aplica filtros
        failed_inspections_summary: failed_inspections_summary,
        failed_inspections_detail: failed_inspections_detail,
        selected_phase_inspections: nil  # Broadcast não aplica filtros
      }
    )

    # Broadcast o HTML já renderizado
    Turbo::StreamsChannel.broadcast_replace_to(
      "construction_overview",
      target: "construction_overview_content",
      html: html
    )

    Rails.logger.info "✅ Broadcasted Construction Overview: #{total_records} records, #{active_houses.size} active houses, #{phase_summary.size} phases"
  rescue StandardError => e
    Rails.logger.error "❌ Broadcast Construction Overview failed: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    # Don't re-raise - broadcast failure shouldn't fail the job
  end
end
