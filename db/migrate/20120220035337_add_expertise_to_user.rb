class AddExpertiseToUser < ActiveRecord::Migration
  def self.up
    add_column :users, :expertise, :text
  end

  def self.down
    remove_column :users, :expertise
  end
end
