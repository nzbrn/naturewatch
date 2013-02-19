class AddDeceasedToUser < ActiveRecord::Migration
  def self.up
    add_column :users, :deceased, :boolean, :default => false
  end

  def self.down
    remove_column :users, :deceased
  end
end
