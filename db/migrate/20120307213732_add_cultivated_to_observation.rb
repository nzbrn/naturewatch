class AddCultivatedToObservation < ActiveRecord::Migration
  def self.up
    add_column :observations, :cultivated, :string
  end

  def self.down
    remove_column :observations, :cultivated
  end
end
