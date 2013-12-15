module UserMailerHelper
  def show_field_prefix(field)
    case field
    when 'species_not_found'
      'The species listed below were not found in the Naturewatch database. Please check the spelling for each entry. If the spelling is correct, please ask Naturewatch to add the species from an external source e.g. NZOR.'
    end
  end
end
