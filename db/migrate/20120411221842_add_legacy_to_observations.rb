class AddLegacyToObservations < ActiveRecord::Migration
  def self.up
    add_column :observations, :legacy, :text
  end

  def self.down
    remove_column :observations, :legacy
  end
end
