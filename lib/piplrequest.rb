require 'pipl'
require 'pry'
require 'geocoder'

class PiplRequest
  def initialize(api_key, fields_to_use)
    @api_key = api_key
    @fields_to_use = fields_to_use
    configure_pipl
  end

  # Sets Pipl API settings globally
  def configure_pipl
    Pipl.configure do |c|
      c.api_key = @api_key
      c.show_sources = 'all'
      c.minimum_probability = 0.7
      c.minimum_match = 0.5
      c.strict_validation = true
    end
  end

  # Gets the data
  def get_data(data_item)
    return process_output(send_request(build_person(data_item)))
  end

  # Sends the request
  def send_request(person)
    response = Pipl::client.search person: person, pretty: true, hide_sponsored: true, show_sources: "all"
  end

  # Process the output
  def process_output(response)
    personout = Array.new

    # Handle both single persons and possible_persons response
    if response.person
      personout.push(response.person.to_hash)
    elsif response.possible_persons
      response.possible_persons.each{|r| personout.push(r.to_hash)}
    end
    
    return JSON.pretty_generate(personout)
  end

  # Geocode location to get area in correct format
  def geocode(location)
    begin
      # Catch Washington DC case and similar
      location = "Washington D.C." if location.include?("Washington D.C.")
      location = location.gsub("Area", "").gsub("Greater", "").strip.lstrip
    
      # Geocode and get first part of response
      response = Geocoder.search(location)
      address_info = response.first.data["address_components"]
    
      # Get data for each field
      country = address_info.select { |i| i["types"].include?("country")}[0]["short_name"]
      state = address_info.select { |i| i["types"].include?("administrative_area_level_1")}[0]["short_name"]
      city = address_info.select { |i| i["types"].include?("colloquial_area") || i["types"].include?("locality")}[0]["long_name"]
      
      return Pipl::Address.new(country: country, state: state, city: city)
    rescue # Return input location if fails (default to US)
      return Pipl::Address.new(country: 'US', city: location) if location && location != ","
    end
  end

  # Clean name fields to not include extra info
  def clean_name(name)
    return name.split("(").first.split("/").first.strip if name
  end

  # Generate the name
  def gen_name(data_item)
    return Pipl::Name.new(first: clean_name(get_field_content(data_item, :name, :first)),
                   last: clean_name(get_field_content(data_item, :name, :last)))
  end

  # Generate the URL
  def gen_url(data_item)
    Pipl::Url.new(url: get_field_content(data_item, :url, :url),
                  domain: @fields_to_use[:url][:domain])
  end

  # Builds person model
  def build_person(data_item)
    # Initial gen and required fields
    person = Pipl::Person.new
    person.add_field(gen_name(data_item))

    # Optional fields- only run if there
    location = geocode(get_field_content(data_item, :address, :city))
    person.add_field(location) if location
    
    url = gen_url(data_item)
    person.add_field(url) if url
    
    return person
  end

  # Get content that should be put in field based on fields_to_use mapping
  def get_field_content(data_item, field_category, field_name)
    data_field = @fields_to_use[field_category][field_name]
    
    # Merge multiple fields if provided
    if data_field.is_a?(Array)
      data_field.map{|d| data_item[d]}.join(", ")
    else return data_item[data_field]
    end
  end
end

# TODO: Test with Indeed too!
