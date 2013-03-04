class AddSexToObservation < ActiveRecord::Migration
  def self.up
    add_column :observations, :sex, :string
  end

  def self.down
    remove_column :observations, :sex
  end
end
