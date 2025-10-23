class AddStrategicIndexesToDailylogs < ActiveRecord::Migration[8.0]
  def change
    # Índices estratégicos para queries do firefighting

    # Para filtros de process (Queries 7-8: LIKE '%inspection%')
    add_index :dailylogs, :process unless index_exists?(:dailylogs, :process)

    # Para queries de phase (todas as queries 1-12)
    add_index :dailylogs, :phase

    # Para JOINs complexos job_id + process (Queries 7-12)
    add_index :dailylogs, [:job_id, :process, :datecreated],
              name: 'index_dailylogs_on_job_process_date'

    # Para último status por job (Queries 8, 10, 12)
    add_index :dailylogs, [:job_id, :status, :datecreated],
              name: 'index_dailylogs_on_job_status_date'

    # Para filtros temporais (todas as queries usam datecreated)
    add_index :dailylogs, :datecreated unless index_exists?(:dailylogs, :datecreated)
  end
end
