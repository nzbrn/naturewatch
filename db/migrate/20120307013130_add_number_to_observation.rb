class AddNumberToObservation < ActiveRecord::Migration
  def self.up
    add_column :observations, :number_individuals, :integer
  end

  def self.down
    remove_column :observations, :number_individuals
  end
end
