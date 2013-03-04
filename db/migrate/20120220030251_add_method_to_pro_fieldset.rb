class AddMethodToProFieldset < ActiveRecord::Migration
  def self.up
    add_column :pro_fieldsets, :observation_method, :string
  end

  def self.down
    remove_column :pro_fieldsets, :observation_method
  end
end
