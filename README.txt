This uses the Pipl API to query based on data in the fields specified in a
JSON.

To install-
gem install piplrequest

To run-
p = PiplRequest.new("apikey", {name: {first: "first_name_field", last:
"last_name_field"}, address: {city: ["location", "area"]}, url: {url:
"profile_url", domain: "linkedin.com"}}) # Except for the URL domain, just put
in the field names with the data
p.get_data(specific_data_item) # Pass in each data item you want parsed with
this api key and data schema



