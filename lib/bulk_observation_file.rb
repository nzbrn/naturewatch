# Custom DelayedJob task for the bulk upload functionality.
class BulkObservationFile < Struct.new(:observation_file, :project_id, :coord_system, :user)
  class BulkObservationException < StandardError
    attr_reader :reason, :row_count, :errors

    def initialize(reason, row_count = nil, errors = [])
      @reason    = reason
      @row_count = row_count unless row_count.nil?

      if errors.empty?
        @errors = [reason]
      else
        @errors = errors
      end
    end
  end

  BASE_ROW_COUNT    = 24
  IMPORT_BATCH_SIZE = 1000
  MAX_ERROR_COUNT   = 10

  attr_accessor :observation_file, :project, :coord_system, :user, :csv_options, :custom_field_count

  def initialize(observation_file, project_id, coord_system, user)
    @observation_file = observation_file
    @coord_system     = coord_system
    @user             = user

    # Try to load the specified project.
    if project_id.blank?
      @project = nil
    else
      @project = Project.find(project_id)
      if @project.nil?
        e = BulkObservationException.new('Specified project not found')
        UserMailer.delay.bulk_observation_error(user, File.basename(observation_file), e)
      end
    end

    @custom_field_count = @project.nil? ? 0 : @project.observation_fields.size
  end

  def perform
    begin
      # Run a validation check over the file to make sure it's valid CSV.
      validate_file

      # Start adding observations.
      import_file

      # Email uploader to say that the upload has finished.
      UserMailer.delay.bulk_observation_success(@user, File.basename(@observation_file))
    rescue BulkObservationException => e
      # Collate the errors into a hash for emailing
      error_details = collate_errors(e)

      # Email the uploader with exception details
      UserMailer.delay.bulk_observation_error(@user, File.basename(@observation_file), error_details)
    end
  end

  def check_encoding(row)
    row = row.map do |item|
      if item.blank?
        nil
      else
        begin
          item.to_s.encode('UTF-8').strip
        rescue Encoding::UndefinedConversionError => e
          problem = e.message[/"(.+)" from/, 1]
          item.to_s.gsub(problem, '').encode('UTF-8').strip
        end
      end
    end
  end

  def validate_file
    row_count = 1
    errors = []

    # Parse the entire observation file looking for possible errors.
    rows = CSV.parse(open(@observation_file).read)

    # Skip the header row - this is very clumsy, but using the built in
    # header skipping doesn't allow the use of Array.in_groups_of below
    # and causes issues with the field UTF-8 encoding above.
    rows.shift

    # Iterate over each row
    rows.each do |row|
      unless skip_row?(row)
        # Capture a second attempt encoding error
        begin
          row = check_encoding(row)
        rescue Encoding::UndefinedConversionError => e
          errors << e
        end

        # Check that the number of CSV fields is correct.
        errors << BulkObservationException.new("Column count is not correct (#{@custom_field_count + BASE_ROW_COUNT} expected, #{row.count} found)", row_count + 1) if row.count != (@custom_field_count + BASE_ROW_COUNT)

        # Check the validity of the observation
        obs = new_observation(row)
        errors << BulkObservationException.new('Observation is not valid', row_count + 1, obs.errors) unless obs.valid?
      end

      # Increment the row count.
      row_count = row_count + 1

      # Stop if we have reached our max error count
      break if errors.count >= MAX_ERROR_COUNT
    end

    raise BulkObservationException.new('Too many errors encountered:', nil, errors) if errors.count > 0
    raise BulkObservationException.new('Observation file was empty.') if row_count == 0
  end

  # Import the observations in the file, and add to the specified project.
  def import_file
    observations = []
    row_count = 2

    # Load the entire file and skip the header row
    csv = CSV.parse(open(@observation_file).read)
    csv.shift

    # Split the rows into groups of the IMPORT_BATCH_FILE to
    # minimize wasted time in the case of errors.
    csv.in_groups_of(IMPORT_BATCH_SIZE).each do |rows|
      ActiveRecord::Base.transaction do
        rows.each do |row|
          next if skip_row?(row)
          row = check_encoding(row)

          # Add the observation file name as a tag for identification purposes.
          if row[6].blank?
            tags = []
          else
            tags = row[6].split(',')
          end
          tags << File.basename(@observation_file)
          row[6] = tags.join(',')

          obs = new_observation(row)
          begin
            # Try to save the observation
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

      # Add all of the observations to the project if a project was specified
      if @project
        observations.each do |obs|
          @project.project_observations.create(:observation => obs)
        end

        # Manually update counter caches.
        ProjectUser.update_observations_counter_cache_from_project_and_user(@project.id, @user.id)
        ProjectUser.update_taxa_counter_cache_from_project_and_user(@project.id, @user.id)
        Project.update_observed_taxa_count(@project.id)

        # Do a mass refresh of the project taxa.
        Project.refresh_project_list(@project.id, :taxa => observations.collect(&:taxon_id), :add_new_taxa => true)
      end
    end
  end

  def new_observation(row)
    obs = Observation.new(
      :user               => @user,
      :species_guess      => row[0],
      :observed_on_string => row[1],
      :description        => row[2],
      :place_guess        => row[3],
      :time_zone          => @user.time_zone,
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
    if @coord_system.nil? || @coord_system == 'wgs84'
      obs.latitude  = row[4]
      obs.longitude = row[5]
    else
      obs.geo_x = row[4]
      obs.geo_y = row[5]
      obs.coordinate_system = @coord_system
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
    unless @project.nil?
      # Add the per-project fields if applicable.
      field_count = BASE_ROW_COUNT
      ProjectObservationField.where(:project_id => @project).order(:position).each do |field|
        if row[field_count].blank?
          if field.required
            obs.custom_field_errors ||= []
            obs.custom_field_errors << "#{field.observation_field.name} is required"
          end
        else
          obs.observation_field_values.build(:observation_field_id => field.observation_field_id, :value => row[field_count])
        end
        field_count += 1
      end
    end

    # Skip some expensive post-save tasks
    obs.skip_identifications     = true
    obs.skip_refresh_check_lists = true
    obs.skip_refresh_lists       = true
    obs.bulk_import              = true

    obs
  end

  def skip_row?(row)
    row.blank? || !(row.first =~ /\A\s*#/).nil?
  end

  def collate_errors(exception)
    # enumerate the exceptions and collate error messages
    field_options = {}
    errors = {}
    exception.errors.each do |e|
      if e.errors.is_a?(ActiveModel::Errors)
        e.errors.each do |field, error|
          errors[field] ||= {}
          full_error = e.errors.full_message(field, error)
          errors[field][full_error] ||= []
          errors[field][full_error] << e.row_count
          field_options[field] = Observation.field_allowed_values(field)
        end
      else
        e.errors.each do |error|
          errors['base'] ||= {}
          errors['base'][error] ||= []
          errors['base'][error] << e.row_count
        end
      end
    end

    { :reason => exception.reason, :errors => errors, :field_options => field_options }
  end

end
