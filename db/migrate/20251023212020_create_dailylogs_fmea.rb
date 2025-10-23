class CreateDailylogsFmea < ActiveRecord::Migration[8.0]
  def change
    create_table :dailylogs_fmea do |t|
      # IDs
      t.integer :job_id
      t.integer :site_number

      # Core fields
      t.text :process
      t.text :status
      t.text :phase
      t.text :failure_group      # IMPORTANTE para Query 10 (Rules 2 e 3)
      t.text :failure_item

      # Booleans (Query 10 usa estes!)
      t.boolean :is_multitag
      t.boolean :not_report       # REGRA 0 da Query 10
      t.boolean :checklist_done
      t.boolean :fees

      # Dates
      t.date :datecreated

      # Metadata
      t.text :addedby
      t.text :logtitle
      t.text :notes

      # Location
      t.text :county
      t.text :sector
      t.text :cell
      t.text :jobsite
      t.text :site
      t.text :permit
      t.text :parcel
      t.text :model_code

      t.timestamps
    end

    # Índices estratégicos para Query 10 (Rules 2 e 3 do firefighting)
    add_index :dailylogs_fmea, :job_id
    add_index :dailylogs_fmea, [:job_id, :process]
    add_index :dailylogs_fmea, [:process, :status]
    add_index :dailylogs_fmea, :datecreated
    add_index :dailylogs_fmea, :not_report
    add_index :dailylogs_fmea, :failure_group
  end
end
