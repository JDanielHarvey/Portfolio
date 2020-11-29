'''
	Testing the api.builtwith.com free
	unlimited requests

	https://api.builtwith.com/v18/api - 

'''

import json
import requests
import os

# sec 0 - set the global variables
apikey = os.environ.get('builtwith_apikey')
domain_lookup = 'trainual.com'
url_req = f'''
			https://api.builtwith.com/v18/api.json?
				KEY={apikey}&
				LOOKUP={domain_lookup}
			'''
url_req = url_req.replace('\n','').replace('\t','')

req_resp = requests.get(url_req)


# sec 1 - handle the responses
json_resp = json.dumps(req_resp.json(), indent = 2, sort_keys=True)

print(json_resp)



