'''
Beautiful Soup or hacker target
'''

import requests
import json
from bs4 import BeautifulSoup as bsoup
import re

host_domain = 'https://www.alaschools.org'

# request_url = 'https://api.hackertarget.com/pagelinks/'
# req_resp = requests.get(f'{request_url}?q={host_domain}')

page = requests.get(host_domain)

bSoup = bsoup(page.content, 'html.parser')

links_list = bSoup.findAll('a')

links_array = []

for link in links_list:
	if 'href' in link.attrs:
		link_href = link.attrs['href']
		#print(str(f'{host_domain}{link_href}') + '\n')

		links_array.append(link_href)

paths_array = []

path_patrn = re.compile(r'^/about/careers.*')

for path in links_array:
	matches = path_patrn.finditer(path)
	for match in matches:
		paths_array.append(f'{host_domain}{match[0]}')

		# print(match[0]) # viewable list of paths_array


paths_array = list( dict.fromkeys(paths_array) )

for item in paths_array:
	print(item)

print()

for page in paths_array:
	page_req = requests.get(page)

	page_html = bsoup(page_req.content, 'html.parser')

	form_patrn = re.compile(r'.*body.*')
	# field_patrn = re.compile(r'.*input.*')

	forms_list = page_html.findAll(form_patrn)
	# fields = forms_list.find(field_patrn)

	forms_array = []




	# formdata = dict( (field.get('name'), field.get('value')) for field in fields)

	print()
	print(page, forms_list)
	print()
	print()


