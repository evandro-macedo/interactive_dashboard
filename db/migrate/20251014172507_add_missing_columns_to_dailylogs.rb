class AddMissingColumnsToDailylogs < ActiveRecord::Migration[8.0]
  def change
    add_column :dailylogs, :addedby, :text
    add_column :dailylogs, :cell, :text
    add_column :dailylogs, :datecreated, :datetime
    add_column :dailylogs, :dateonly, :datetime
    add_column :dailylogs, :enddate, :datetime
    add_column :dailylogs, :servicedate, :text
    add_column :dailylogs, :startdate, :datetime
    add_column :dailylogs, :sub, :text
  end
end
