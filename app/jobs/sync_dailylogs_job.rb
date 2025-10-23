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

      # Broadcast Turbo Stream update to Construction Overview page
      broadcast_construction_overview_update

      # Processar webhooks para novos registros
      if new_record_ids.any?
        Rails.logger.info "Processing webhooks for #{new_record_ids.count} new records..."
        new_records = Dailylog.where(id: new_record_ids)
        NewRecordsDetectorService.new(new_records).process_webhooks
      end

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

  def broadcast_construction_overview_update
    # Calculate basic stats for Construction Overview
    total_records = Dailylog.count

    # Broadcast the updated partial to all connected clients
    Turbo::StreamsChannel.broadcast_replace_to(
      "construction_overview",
      target: "construction_overview_content",
      partial: "construction_overview/content",
      locals: {
        total_records: total_records
      }
    )

    Rails.logger.info "Broadcasted Construction Overview update via Turbo Stream (#{total_records} records)"
  rescue StandardError => e
    Rails.logger.error "Failed to broadcast Construction Overview update: #{e.message}"
    # Don't re-raise - broadcast failure shouldn't fail the job
  end
end
