class SyncDailylogsJob < ApplicationJob
  queue_as :default

  def perform
    start_time = Time.current
    records_synced = 0
    records_added = 0

    begin
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

      # Calcular quantos registros novos foram adicionados
      records_added = [records_synced - previous_count, 0].max

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
end
