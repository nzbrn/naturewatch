module ObservationsHelper
  def setup_observation(observation)
    observation.pro_fieldset ||= ProFieldset.new
    observation
  end

  def observation_image_url(observation, params = {})
    return nil if observation.observation_photos.blank?
    size = params[:size] ? "#{params[:size]}_url" : 'square_url'
    photo = observation.observation_photos.sort_by do |op|
      op.position || observation.observation_photos.size + op.id.to_i
    end.first.photo
    photo.send(size)
  end
  
  def short_observation_description(observation)
    truncate(sanitize(observation.description), :length => 150)
  end
  
  def observations_order_by_options(order_by = nil)
    order_by ||= @order_by
    pairs = ObservationsController::ORDER_BY_FIELDS.map do |f|
      value = %w(created_at observations.id id).include?(f) ? 'observations.id' : f
      [ObservationsController::DISPLAY_ORDER_BY_FIELDS[f], value]
    end
    order_by = 'observations.id' if order_by.blank?
    options_for_select(pairs, order_by)
  end
  
  def show_observation_coordinates?(observation)
    ![observation.latitude, observation.longitude, 
        observation.private_latitude, observation.private_longitude].compact.blank? &&
        (!observation.geoprivacy_private? || observation.coordinates_viewable_by?(current_user))
  end
  
  def observation_place_guess(observation, options = {})
    display_lat = observation.latitude
    display_lon = observation.longitude
    if !observation.private_latitude.blank? && observation.coordinates_viewable_by?(current_user)
      display_lat = observation.private_latitude
      display_lon = observation.private_longitude
    end
    
    google_search_link = link_to("Google", "http://maps.google.com/?q=#{observation.place_guess}", :target => "_blank")
    google_coords_link = link_to("Google", "http://maps.google.com/?q=#{display_lat},#{display_lon}&z=#{observation.map_scale}", :target => "_blank")
    osm_search_link = link_to("OSM", "http://nominatim.openstreetmap.org/search?q=#{observation.place_guess}", :target => "_blank")
    osm_coords_url = "http://www.openstreetmap.org/?mlat=#{display_lat}&mlon=#{display_lon}"
    osm_coords_url += "&zoom=#{observation.map_scale}" unless observation.map_scale.blank?
    osm_coords_link = link_to("OSM", osm_coords_url, :target => "_blank")
    
    if coordinate_truncation = options[:truncate_coordinates]
      coordinate_truncation = 6 unless coordinate_truncation.is_a?(Fixnum)
      display_lat = display_lat.to_s[0..coordinate_truncation] + "..." unless display_lat.blank?
      display_lon = display_lon.to_s[0..coordinate_truncation] + "..." unless display_lon.blank?
    end
    
    if !observation.place_guess.blank?
      if observation.latitude.blank?
        "#{observation.place_guess} (#{google_search_link}, #{osm_search_link})".html_safe
      else
        place_guess = if observation.lat_lon_in_place_guess? && coordinate_truncation
          "<nobr>#{display_lat},</nobr> <nobr>#{display_lon}</nobr>"
        else
          observation.place_guess
        end
        link_to(place_guess.html_safe, observations_path(:lat => observation.latitude, :lng => observation.longitude)) +
         " (#{google_coords_link}, #{osm_coords_link})".html_safe
      end
    elsif !observation.latitude.blank? && !observation.coordinates_obscured?
      link_to("<nobr>#{display_lat},</nobr> <nobr>#{display_lon}</nobr>".html_safe, 
        observations_path(:lat => observation.latitude, :lng => observation.longitude)) +
        " (#{google_coords_link}, #{osm_coords_link})".html_safe
        
    elsif !observation.private_latitude.blank? && observation.coordinates_viewable_by?(current_user)
      link_to("<nobr>#{display_lat}</nobr>, <nobr>#{display_lon}</nobr>".html_safe, 
        observations_path(:lat => observation.private_latitude, :lng => observation.private_longitude)) +
        " (#{google_coords_link}, #{osm_coords_link})".html_safe
    else
      content_tag(:span, "(Somewhere...)")
    end
  end

  def stage_name(stage)
    reverse_stage = {
      'plant_seedling' => 'Seedling',
      'plant_juvenile' => 'Juvenile',
      'plant_adult' => 'Adult',
      'fungi_disease' => 'Disease symptoms',
      'fungi_immature' => 'Immature fruiting body',
      'fungi_mature' => 'Mature fruiting body',
      'fungi_immature' => 'Immature fruiting body',
      'insects_egg' => 'Egg',
      'insects_larva' => 'Larva/Nymph',
      'insects_pupa' => 'Pupa',
      'insects_adult' => 'Adult',
      'birds_egg' => 'Egg',
      'birds_chick' => 'Chick',
      'birds_juvenile' => 'Juvenile',
      'birds_adult' => 'Adult',
      'mammals_juvenile' => 'Juvenile',
      'mammals_adult' => 'Adult',
      'all_egg' => 'Egg',
      'all_juvenile' => 'Juvenile',
      'all_adult' => 'Adult',
    }
    reverse_stage[stage]
  end

  #function to filter the stages.  Shouldn't be used until the javascript event is hooked up
  def filtered_stages(observation)
    #if !observation.iconic_taxon_name.nil?
    #  options = Observation::STAGE_OPTIONS.reject { |k,v| ![Observation::NZBRN_ICONIC[observation.iconic_taxon_name]].include? k}
    #  return options if options.count > 0
    #end
    Observation::STAGE_OPTIONS
  end
  
  def coordinate_system_select_options
    options = {}
    
    CONFIG.coordinate_systems.each do |system_name, system|
      options[system[:label]] = system_name
    end
    
    options
  end

  def field_value_example(datatype, allowed_values = nil, field_id = nil)
    str = if allowed_values.blank?
      case datatype
      when 'text'
        'alphanumeric string'
      when 'datetime', 'date'
        'YYYY-MM-DD HH:MM'
      when 'coordinate'
        'dd.dddd (long/lat) or ddddddd (east/north)'
      when 'boolean'
        'yes or no'
      when 'list'
        'limited set of options, usually alphanumeric'
      when 'number'
        'positive whole number'
      else
        nil
      end
    else
      "One of #{allowed_values.split('|').to_sentence(:two_words_connector => ' or ', :last_word_connector => ' or ')}"
    end

    unless field_id.nil?
      proj_obs_field = ProjectObservationField.find_by_observation_field_id(field_id)
      str = "#{str}, #{content_tag('strong', 'required')}".html_safe if proj_obs_field.required
    end

    str
  end

end
