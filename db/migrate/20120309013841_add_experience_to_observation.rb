class AddExperienceToObservation < ActiveRecord::Migration
  def self.up
    add_column :observations, :user_expertise, :string
  end

  def self.down
    remove_column :observations, :user_expertise
  end
end
