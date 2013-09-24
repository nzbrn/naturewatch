class Project < ActiveRecord::Base
  belongs_to :user
  belongs_to :place
  has_many :project_users, :dependent => :delete_all
  has_many :project_observations, :dependent => :destroy
  has_many :project_invitations, :dependent => :destroy
  has_many :users, :through => :project_users
  has_many :observations, :through => :project_observations
  has_one :project_list, :dependent => :destroy
  has_many :listed_taxa, :through => :project_list
  has_many :taxa, :through => :listed_taxa
  has_many :project_assets, :dependent => :destroy
  has_one :custom_project, :dependent => :destroy
  has_many :project_observation_fields, :dependent => :destroy, :inverse_of => :project, :order => "position"
  has_many :observation_fields, :through => :project_observation_fields
  has_many :posts, :as => :parent, :dependent => :destroy
  has_many :assessments, :dependent => :destroy
    
  before_save :strip_title
  after_create :create_the_project_list
  after_save :add_owner_as_project_user
  
  has_rules_for :project_users, :rule_class => ProjectUserRule
  has_rules_for :project_observations, :rule_class => ProjectObservationRule

  has_subscribers :to => {
    :posts => {:notification => "created_project_post"},
    :project_users => {:notification => "curator_change"}
  }

  extend FriendlyId
  friendly_id :title, :use => :history, :reserved_words => ProjectsController.action_methods.to_a
  
  preference :count_from_list, :boolean, :default => false
  preference :place_boundary_visible, :boolean, :default => false
  
  # For some reason these don't work here
  # accepts_nested_attributes_for :project_user_rules, :allow_destroy => true
  # accepts_nested_attributes_for :project_observation_rules, :allow_destroy => true
  accepts_nested_attributes_for :project_observation_fields, :allow_destroy => true
  
  validates_length_of :title, :within => 1..85
  validates_presence_of :user
  
  scope :featured, where("featured_at IS NOT NULL")
  scope :near_point, lambda {|latitude, longitude|
    latitude = latitude.to_f
    longitude = longitude.to_f
    where("ST_Distance(ST_Point(projects.longitude, projects.latitude), ST_Point(#{longitude}, #{latitude})) < 5").
    order("ST_Distance(ST_Point(projects.longitude, projects.latitude), ST_Point(#{longitude}, #{latitude}))")
  }
  scope :from_source_url, lambda {|url| where(:source_url => url) }
  
  has_attached_file :icon, 
    :styles => { :thumb => "48x48#", :mini => "16x16#", :span1 => "30x30#", :span2 => "70x70#" },
    :path => ":rails_root/public/attachments/:class/:attachment/:id/:style/:basename.:extension",
    :url => "/attachments/:class/:attachment/:id/:style/:basename.:extension",
    :default_url => "/attachment_defaults/general/:style.png"
  
  CONTEST_TYPE = 'contest'
  OBS_CONTEST_TYPE = 'observation contest'
  ASSESSMENT_TYPE = 'assessment'
  PROJECT_TYPES = [CONTEST_TYPE, OBS_CONTEST_TYPE , ASSESSMENT_TYPE]
  RESERVED_TITLES = ProjectsController.action_methods
  MAP_TYPES = %w(roadmap terrain satellite hybrid)
  validates_exclusion_of :title, :in => RESERVED_TITLES + %w(user)
  validates_uniqueness_of :title
  validates_inclusion_of :map_type, :in => MAP_TYPES

  define_index do
    indexes :title
    indexes :description
    set_property :delta => :delayed
  end
  
  def to_s
    "<Project #{id} #{title}>"
  end
  
  def strip_title
    self.title = title.strip
    true
  end
  
  def add_owner_as_project_user
    return true unless user_id_changed?
    pu = project_users.where(:user_id => user_id).first
    pu ||= self.project_users.create(:user => user)
    pu.update_attributes(:role => ProjectUser::MANAGER)
    true
  end
  
  def create_the_project_list
    create_project_list
    true
  end
  
  def contest?
     PROJECT_TYPES.include? project_type
  end
  
  def editable_by?(user)
    return false if user.blank?
    return true if user.id == user_id || user.is_admin?
    pu = user.project_users.first(:conditions => {:project_id => id})
    pu && pu.is_manager?
  end
  
  def curated_by?(user)
    return false if user.blank?
    return true if user.is_admin?
    project_users.curators.exists?(:user_id => user.id) || project_users.managers.exists?(:user_id => user.id)
  end
  
  def rule_place
    project_observation_rules.first(:conditions => {:operator => "observed_in_place?"}).try(:operand)
  end
  
  def icon_url
    icon.file? ? "#{CONFIG.site_url}#{icon.url(:span2)}" : nil
  end
  
  def project_observation_rule_terms
    project_observation_rules.map{|por| por.terms}.join('|')
  end

  def matching_project_observation_rule_terms
    matching_project_observation_rules.map{|por| por.terms}.join('|')
  end

  def matching_project_observation_rules
    matching_operators = %w(in_taxon? observed_in_place? on_list? identified? georeferenced?)
    project_observation_rules.select{|rule| matching_operators.include?(rule.operator)}
  end
  
  def project_observations_count
    project_observations.count
  end
  
  def featured_at_utc
    featured_at.try(:utc)
  end
  
  def tracking_code_allowed?(code)
    return false if code.blank?
    return false if tracking_codes.blank?
    tracking_codes.split(',').map{|c| c.strip}.include?(code)
  end

  def observations_matching_rules
    scope = Observation.scoped
    project_observation_rules.each do |rule|
      case rule.operator
      when "in_taxon?"
        scope = scope.of(rule.operand)
      when "observed_in_place?"
        scope = scope.in_place(rule.operand)
      when "on_list?"
        scope = scope.scoped(
          :joins => "JOIN listed_taxa ON listed_taxa.list_id = #{project_list.id}", 
          :conditions => "observations.taxon_id = listed_taxa.taxon_id")
      when "identified?"
        scope = scope.scoped(:conditions => "observations.taxon_id IS NOT NULL")
      when "georeferenced"
        scope = scope.scoped(:conditions => "observations.geom IS NOT NULL")
      end
    end
    scope
  end

  def cached_slug
    slug
  end

  def curators
    users.where("project_users.role = ?", ProjectUser::CURATOR).scoped
  end

  def managers
    users.where("project_users.role = ?", ProjectUser::MANAGER).scoped
  end
  
  def self.default_json_options
    {
      :methods => [:icon_url, :project_observation_rule_terms, :featured_at_utc, :rule_place, :cached_slug, :slug],
      :except => [:tracking_codes]
    }
  end
  
  def self.update_curator_idents_on_make_curator(project_id, project_user_id)
    unless project = Project.find_by_id(project_id)
      return
    end
    unless project_user = project.project_users.find_by_id(project_user_id)
      return
    end
    project.project_observations.find_each(
        :include => {:observation => :identifications}, 
        :conditions => [
          "project_observations.curator_identification_id IS NULL AND identifications.user_id = ?", 
          project_user.user_id]) do |po|
      curator_ident = po.observation.identifications.detect{|ident| ident.user_id == project_user.user_id}
      po.update_attributes(:curator_identification => curator_ident)
      ProjectUser.delay.update_observations_counter_cache_from_project_and_user(project_id, po.observation.user_id)
      ProjectUser.delay.update_taxa_counter_cache_from_project_and_user(project_id, po.observation.user_id)
    end
  end
  
  def self.update_curator_idents_on_remove_curator(project_id, user_id)
    unless project = Project.find_by_id(project_id)
      return
    end
    
    find_options = if user = User.find_by_id(user_id)
      {
        :include => [:curator_identification, :observation], 
        :conditions => ["identifications.user_id = ?", user.id]
      }
    else
      {
        :include => {:observation => :identifications}, 
        :conditions => "project_observations.curator_identification_id IS NOT NULL"
      }
    end
    
    project_curators = project.project_users.all(:conditions => ["role IN (?)", [ProjectUser::MANAGER, ProjectUser::CURATOR]])
    project_curator_user_ids = project_curators.map{|pu| pu.user_id}
    
    project.project_observations.find_each(find_options) do |po|
      curator_ident = po.observation.identifications.detect{|ident| project_curator_user_ids.include?(ident.user_id)}
      po.update_attributes(:curator_identification => curator_ident)
      ProjectUser.delay.update_observations_counter_cache_from_project_and_user(project_id, po.observation.user_id)
      ProjectUser.delay.update_taxa_counter_cache_from_project_and_user(project_id, po.observation.user_id)
    end
  end
  
  def self.refresh_project_list(project, options = {})
    unless project.is_a?(Project)
      project = Project.find_by_id(project, :include => :project_list)
    end
    
    if project.blank?
      Rails.logger.error "[ERROR #{Time.now}] Failed to refresh list for " + 
        "project #{project} because it doesn't exist."
      return
    end
    
    project.project_list.refresh(options)
  end
  
  def self.update_observed_taxa_count(project_id)
    return unless project = Project.find_by_id(project_id)
    observed_taxa_count = project.project_list.listed_taxa.count(:conditions => "last_observation_id IS NOT NULL")
    project.update_attributes(:observed_taxa_count => observed_taxa_count)
  end
  
  
  def self.delete_project_observations_on_leave_project(project_id, user_id)
    unless proj = Project.find_by_id(project_id)
      return
    end
    unless usr = User.find_by_id(user_id)
      return
    end
    proj.project_observations.find_each(:include => :observation, :conditions => ["observations.user_id = ?", usr]) do |po|
      po.destroy
    end
  end

  def generate_bulk_upload_template
    data = {
      'Species'                  => ['#Lorem', '#Ipsum'],
      'Observation Date'         => ['2013-01-01', '2013-01-01 12:00:00'],
      'Description'              => ['Description of observation'],
      'Location'                 => ['Wellington City', 'Karori'],
      'Latitude or Northing'     => [-41.2837551, 1932810],
      'Longitude or Easting'     => [174.7408745, 5669626],
      'Tags'                     => ['Comma,Separated', 'List,Of,Tags'],
      'Sex'                      => ["One of #{Observation::OBSERVATION_SEX.join(', ')}"],
      'Stage'                    => ["One of #{Observation::STAGE_OPTIONS_VALUES.join(', ')}"],
      'Cultivated'               => ["One of #{Observation::CULTIVATED_OPTIONS.join(', ')}"],
      'Number of Individuals'    => [5, 1],
      'Sought But Not Found'     => ['Yes', 'No'],
      'Geoprivacy'               => ['', 'Private'],
      'Second Hand'              => ['Second Hand'],
      'Uncertain'                => ['Uncertain'],
      'Escaped'                  => ['Escaped'],
      'Planted'                  => ['Planted'],
      'Ecologically Significant' => ['Ecologically Significant'],
      'Observation Method'       => ['Observation Method'],
      'Host Name'                => ['Host Name'],
      'Habitat'                  => ['Habitat'],
      'Substrate'                => ['Substrate'],
      'Substrate Qualifier'      => ['Substrate Qualifier'],
      'Substrate Description'    => ['Substrate Description'],
    }

    ProjectObservationField.includes(:observation_field).where(:project_id => self.id).order(:position).each do |field|
      name = field.observation_field.name
      name = "#{name}*" if field.required?
      data[name] = [field.observation_field.datatype]
    end

    CSV.generate do |csv|
      csv << data.keys
      csv << data.collect { |f| f[1][0] }
      csv << data.collect { |f| f[1][1] }
    end
  end
end
