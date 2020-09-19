'''
	To be used in whitelisted DNS or CIDR notation
'''

import requests
import json

get_req = requests.get('https://ip-ranges.amazonaws.com/ip-ranges.json')

req_json = get_req.json()['prefixes']

readable = json.dumps(get_req.json()['prefixes'], indent=2)
# print(readable)

# print(req_json[0]['region'])

my_lst = []

for ip in req_json:
 	# print(ip)
 	if ip['region'] == 'us-east-1':
 		my_lst.append(ip['ip_prefix'])
 	else:
 		pass

my_lst_srted = sorted(my_lst, reverse=True)

print(my_lst_srted)