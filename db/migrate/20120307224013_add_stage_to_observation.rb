class AddStageToObservation < ActiveRecord::Migration
  def self.up
    add_column :observations, :stage, :string
  end

  def self.down
    remove_column :observations, :stage
  end
end
