require 'pipl'
require 'pry'
require 'geocoder'

class PiplRequest
  def initialize(api_key, fields_to_use, geocoder_api_key)
    @api_key = api_key
    @fields_to_use = fields_to_use
    Geocoder.configure(:api_key => geocoder_api_key)
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
    begin
      return process_output(send_request(build_person(data_item)))
    rescue
    end
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
    without_parens = name.gsub(/\((?:[^()]+)\)/, "").strip.lstrip
    without_slash = without_parens.split("/").first.strip
    without_numerals = without_slash.gsub(/\s(?:I|V)+(?:\s|$)/, "").strip.lstrip
  end

  # Get the name content and clean it if it exists
  def get_clean_name_content(data_item, type)
    name = get_field_content(data_item, :name, type)
    return clean_name(name) if name
  end

  # Generate the name
  def gen_name(data_item)
    return Pipl::Name.new(first: get_clean_name_content(data_item, :first),
                          last: get_clean_name_content(data_item, :last),
                          middle: get_clean_name_content(data_item, :middle),
                          raw: get_clean_name_content(data_item, :raw)
                         )
  end

  # Get the location
  def gen_location(data_item)
    city = get_field_content(data_item, :address, :city)
    state = get_field_content(data_item, :address, :state)
    country = get_field_content(data_item, :address, :country)

    # Gen string for location
    location_string = ""
    location_string += city + ", "if city
    location_string += state + ", " if state
    location_string += country if country

    location = geocode(location_string)
  end

  # Generate the URL
  def gen_url(data_item)
    url = get_field_content(data_item, :url, :url)
    Pipl::Url.new(url: url, domain: @fields_to_use[:url][:domain]) if url
  end

  # Builds person model
  def build_person(data_item)
    # Initial gen and required fields
    person = Pipl::Person.new
    person.add_field(gen_name(data_item))
    
    # Optional fields- only run if there
    location = gen_location(data_item)
    person.add_field(location) if location
   
    url = gen_url(data_item)
    person.add_field(url) if url
  
    return person
  end

  # Get content that should be put in field based on fields_to_use mapping
  def get_field_content(data_item, field_category, field_name)
    data_field = @fields_to_use[field_category][field_name] if @fields_to_use[field_category]
    
    # Merge multiple fields if provided
    if data_field.is_a?(Array)
      data_field.map{|d| data_item[d]}.join(", ")
    else return data_item[data_field]
    end
  end
end
