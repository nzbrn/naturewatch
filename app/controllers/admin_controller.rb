#
# A collection of tools useful for administrators.
#
class AdminController < ApplicationController
  
  before_filter :authenticate_user!
  before_filter :admin_required
  before_filter :return_here, :only => [:stats, :index, :user_content]
  
  def stats
    @observation_weeks = Observation.count(
      :conditions => ["EXTRACT(YEAR FROM created_at) = ?", Time.now.year],
      :group => "EXTRACT(WEEK FROM created_at)"
    )
    @observation_weeks_last_year = Observation.count(
      :conditions => ["EXTRACT(YEAR FROM created_at) = ?", Time.now.year - 1],
      :group => "EXTRACT(WEEK FROM created_at)"
    )
    @observations_max = (@observation_weeks.values + @observation_weeks_last_year.values).sort.last
    
    @user_weeks = User.count(
      :conditions => ["EXTRACT(YEAR FROM created_at) = ?", Time.now.year],
      :group => "EXTRACT(WEEK FROM created_at)"
    )
    @user_weeks_last_year = User.count(
      :conditions => ["EXTRACT(YEAR FROM created_at) = ?", Time.now.year - 1],
      :group => "EXTRACT(WEEK FROM created_at)"
    )
    @users_max = (@user_weeks.values + @user_weeks_last_year.values).sort.last
    
    @total_users = User.count
    @active_observers = Observation.count(:select => "distinct user_id", :conditions => ["created_at > ?", 3.months.ago])
    @total_observations = Observation.count
    
    @daily_date = Date.yesterday
    daily_country_stats_sql = <<-SQL
      SELECT 
        p.display_name, p.code, p.id, count(o.*)
      FROM 
        observations o, 
        places p, 
        place_geometries pg
      WHERE 
        ST_Intersects(o.geom, pg.geom) 
        AND p.id = pg.place_id 
        AND o.created_at::DATE = '#{@daily_date.to_s}' 
        AND p.place_type = 12 
      GROUP BY p.display_name, p.code, p.id
    SQL
    @daily_country_stats = Observation.connection.execute(daily_country_stats_sql.gsub(/\s+/, ' ').strip)
  end
  
  def index
  end

  def user_content
    return unless load_user_content_info
    @records = @display_user.send("#{@klass.name.underscore.pluralize}").page(params[:page]) rescue []
  end

  def destroy_user_content
    return unless load_user_content_info
    @records = @display_user.send("#{@klass.name.underscore.pluralize}").
      where("id IN (?)", params[:ids] || [])
    @records.each(&:destroy)
    flash[:notice] = "Deleted #{@records.size} #{@type}"
    redirect_back_or_default(admin_user_content_path(@display_user.id, @type))
  end
  
  def login_as
    unless user = User.find_by_id(params[:id] || [params[:user_id]])
      flash[:error] = "That user doesn't exist"
      redirect_back_or_default(:index)
    end
    sign_out :user
    sign_in user
    
    flash[:notice] = "Logged in as #{user.login}. Be careful, and remember to log out when you're done."
    redirect_to root_path
  end

  def delayed_jobs
    @jobs = Delayed::Job.all
  end
  

  private
  def load_user_content_info
    user_id = params[:id] || params[:user_id]
    @display_user = User.find_by_id(user_id)
    @display_user ||= User.find_by_login(user_id)
    @display_user ||= User.find_by_email(user_id)
    unless @display_user
      flash[:error] = "User #{user_id} doesn't exist"
      redirect_back_or_default(:action => "index")
      return false
    end

    @type = params[:type] || "observations"
    @klass = Object.const_get(@type.camelcase.singularize) rescue nil
    @klass = nil unless @klass.try(:base_class).try(:superclass) == ActiveRecord::Base
    unless @klass
      flash[:error] = "#{params[:type]} doesn't exist"
      redirect_back_or_default(:action => "index")
      return false
    end

    @class_names = []
    has_many_reflections = User.reflections.select{|k,v| v.macro == :has_many}
    has_many_reflections.each do |k, reflection|
      # Avoid those pesky :through relats
      next unless reflection.klass.column_names.include?(reflection.foreign_key)
      @class_names << reflection.klass.name
    end
    @class_names.uniq!
    true
  end
end
