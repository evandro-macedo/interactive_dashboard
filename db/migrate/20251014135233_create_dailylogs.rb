class CreateDailylogs < ActiveRecord::Migration[8.0]
  def change
    create_table :dailylogs do |t|
      t.integer :job_id
      t.integer :site_number
      t.string :logtitle
      t.text :notes
      t.string :process
      t.string :status
      t.string :phase
      t.string :jobsite
      t.string :county
      t.string :sector
      t.string :site
      t.string :permit
      t.string :parcel
      t.string :model_code

      t.timestamps
    end

    # Índices para otimizar buscas
    add_index :dailylogs, :job_id
    add_index :dailylogs, :site_number
    add_index :dailylogs, :logtitle
    add_index :dailylogs, :status
    add_index :dailylogs, :jobsite
  end
end
