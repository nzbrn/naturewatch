# Custom DelayedJob task for the bulk upload functionality.
class BulkObservationFile < Struct.new(:observation_file, :project_id, :coord_system, :user)
  class BulkObservationException < StandardError
    attr_reader :reason, :row_count, :errors

    def initialize(reason, row_count = nil, errors = [])
      @reason    = reason
      @row_count = row_count unless row_count.nil?
      @errors    = errors    unless errors.empty?
    end
  end

  BASE_ROW_COUNT = 24
  IMPORT_BATCH_SIZE = 1000

  def perform
    begin
      # Try to load the specified project.
      if project_id.blank?
        project = nil
      else
        project = Project.find(project_id)
        raise BulkObservationException('Specified project not found') if project.nil?
      end

      # Run a validation check over the file to make sure it's valid CSV.
      validate_file(observation_file, project, coord_system, user)

      # Start adding observations.
      import_file(observation_file, project, coord_system, user)

      # Email uploader to say that the upload has finished.
      UserMailer.delay.bulk_observation_success(user, File.basename(observation_file))
    rescue BulkObservationException => e
      # Email the uploader with exception details
      UserMailer.delay.bulk_observation_error(user, File.basename(observation_file), e)
    end
  end

  def validate_file(observation_file, project, coord_system, user)
    row_count = 1
    custom_field_count = project.nil? ? 0 : project.observation_fields.size

    # Parse the entire observation file looking for possible errors.
    CSV.parse(open(observation_file).read) do |row|
      next if row.blank?
      row = row.map do |item|
        if item.blank?
          nil
        else
          begin
            item.to_s.encode('UTF-8').strip
          rescue Encoding::UndefinedConversionError => e
            problem = e.message[/"(.+)" from/, 1]
            begin
              item.to_s.gsub(problem, '').encode('UTF-8').strip
            rescue Encoding::UndefinedConversionError
              # If there's more than one encoding issue, just bail.
              raise BulkObservationException.new('Multiple encoding issues encountered')
            end
          end
        end
      end

      # Check that the number of CSV fields is correct.
      raise BulkObservationException.new("Column count is not correct on at least one row (#{custom_field_count + BASE_ROW_COUNT} expected, #{row.count} found)", row_count) if row.count != (custom_field_count + BASE_ROW_COUNT)

      # Check the validity of the observation
      obs = new_observation(row, project, user, coord_system)
      raise BulkObservationException.new('Observation is not valid', row_count, obs.errors) unless obs.valid?

      # Increment the row count.
      row_count = row_count + 1
    end
  end

  # Import the observations in the file, and add to the specified project.
  def import_file(observation_file, project = nil, coord_system = nil, user = nil)
    observations = []
    row_count = 1
    csv = CSV.parse(open(observation_file).read)
    csv.in_groups_of(IMPORT_BATCH_SIZE).each do |rows|
      ActiveRecord::Base.transaction do
        rows.each do |row|
          next if row.blank?

          # Add the observation file name as a tag for identification purposes.
          if row[6].blank?
            tags = []
          else
            tags = row[6].split(',')
          end
          tags << File.basename(observation_file)
          row[6] = tags.join(',')

          obs = new_observation(row, project, user, coord_system)
          begin
            # Skip some expensive post-save tasks
            obs.skip_identifications     = true
            obs.skip_refresh_check_lists = true
            obs.skip_refresh_lists       = true
            obs.bulk_import              = true

            # And save!
            obs.save!

            # Add this observation to a list for later importing to the project.
            observations << obs

            # Increment the row count so we can tell them where any errors are.
            row_count = row_count + 1
          rescue ActiveRecord::RecordInvalid
            raise BulkObservationException.new('Invalid record encountered', row_count)
          end
        end
      end

      # Add all of the observations to the project.
      observations.each do |obs|
        project.project_observations.create(:observation => obs)
      end

      # Manually update counter caches.
      ProjectUser.update_observations_counter_cache_from_project_and_user(project.id, user.id)
      ProjectUser.update_taxa_counter_cache_from_project_and_user(project.id, user.id)
      Project.update_observed_taxa_count(project.id)

      # Do a mass refresh of the project taxa.
      Project.refresh_project_list(project_id, :taxa => observations.collect(&:taxon_id), :add_new_taxa => true)
    end
  end

  def new_observation(row, project, user, coord_system)
    obs = Observation.new(
      :user               => user,
      :species_guess      => row[0],
      :observed_on_string => row[1],
      :description        => row[2],
      :place_guess        => row[3],
      :time_zone          => user.time_zone,
      :tag_list           => row[6],
      :sex                => row[7],
      :stage              => row[8],
      :cultivated         => row[9],
      :number_individuals => row[10],
      :sought_not_found   => row[11],
      :geoprivacy         => row[12],
    )

    # If a coordinate system other than WGS84 is in use
    # set the correct fields for transformation.
    if coord_system.nil? || coord_system == 'wgs84'
      obs.latitude  = row[4]
      obs.longitude = row[5]
    else
      obs.geo_x = row[4]
      obs.geo_y = row[5]
      obs.coordinate_system = coord_system
    end

    # Add in the professional field set details
    obs.pro_fieldset = ProFieldset.new(
      :second_hand              => row[13],
      :uncertain                => row[14],
      :escaped                  => row[15],
      :planted                  => row[16],
      :ecologically_significant => row[17],
      :observation_method       => row[18],
      :host_name                => row[19],
      :habitat                  => row[20],
      :substrate                => row[21],
      :substrate_qualifier      => row[22],
      :substrate_description    => row[23],
    )

    # Are we adding to a specific project?
    unless project.nil?
      # Add the per-project fields if applicable.
      field_count = BASE_ROW_COUNT
      project.observation_fields.order(:position).each do |field|
        obs.observation_field_values.build(:observation_field_id => field.id, :value => row[field_count]) unless row[field_count].blank?
        field_count += 1
      end
    end

    obs
  end
end
