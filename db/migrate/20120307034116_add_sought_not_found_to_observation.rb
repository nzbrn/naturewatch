class AddSoughtNotFoundToObservation < ActiveRecord::Migration
  def self.up
    add_column :observations, :sought_not_found, :boolean, :default => false
  end

  def self.down
    remove_column :observations, :sought_not_found
  end
end
