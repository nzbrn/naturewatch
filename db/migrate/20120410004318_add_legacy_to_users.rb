class AddLegacyToUsers < ActiveRecord::Migration
  def self.up
    add_column :users, :legacy, :text
  end

  def self.down
    remove_column :users, :legacy
  end
end
