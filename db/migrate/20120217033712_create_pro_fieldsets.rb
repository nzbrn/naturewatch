class CreateProFieldsets < ActiveRecord::Migration
  def self.up
    create_table :pro_fieldsets do |t|
      t.integer :observation_id
      t.boolean :second_hand, :default => false
      t.boolean :uncertain, :default => false
      t.boolean :escaped, :default => false
      t.boolean :planted, :default => false
      t.boolean :ecologically_significant, :default => false

      t.timestamps
    end
  end

  def self.down
    drop_table :pro_fieldsets
  end
end
