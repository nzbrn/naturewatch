class AddYearofbirthToUser < ActiveRecord::Migration
  def self.up
    add_column :users, :year_of_birth, :integer
  end

  def self.down
    remove_column :users, :year_of_birth
  end
end
