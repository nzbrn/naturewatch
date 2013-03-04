class AddSubstrateToProFieldset < ActiveRecord::Migration
  def self.up
    add_column :pro_fieldsets, :host_name, :string
    add_column :pro_fieldsets, :habitat, :string
    add_column :pro_fieldsets, :substrate, :string
    add_column :pro_fieldsets, :substrate_qualifier, :string
    add_column :pro_fieldsets, :substrate_description, :string
  end

  def self.down
    remove_column :pro_fieldsets, :substrate_description
    remove_column :pro_fieldsets, :substrate_qualifier
    remove_column :pro_fieldsets, :substrate
    remove_column :pro_fieldsets, :habitat
    remove_column :pro_fieldsets, :host_name
  end
end
