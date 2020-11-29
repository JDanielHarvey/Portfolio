'''
	Testing the api.builtwith.com lists
	limited to 50 requests

	country code params use ISO_3166-1_alpha-2
	refer to https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2
'''

import json
import requests
import os 

# sec 0 - set the global variables
apikey = os.environ.get('builtwith_apikey')
software_lookup = 'Optimizely'
	# lists of countries necessitate separate requests
countries = 'US'
	# use urllib.parse package to handle the formatting 
	# can't be used with json - must use xml
time_range = '30%20Days%20Ago'

url_req = 'https://api.builtwith.com/lists6/api.json'

url_params = {
	'KEY': apikey, 'TECH': software_lookup, 'COUNTRY': countries, 'META': 'yes'
	}

req_resp = requests.get(url_req, params=url_params, timeout=30)


# sec 1 - handle the responses
json_resp = json.dumps(req_resp.json(), indent = 2, sort_keys=True)

print(json_resp)