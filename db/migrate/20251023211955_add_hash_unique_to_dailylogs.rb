class AddHashUniqueToDailylogs < ActiveRecord::Migration[8.0]
  def change
    add_column :dailylogs, :hash_unique, :text
    add_index :dailylogs, :hash_unique
  end
end
