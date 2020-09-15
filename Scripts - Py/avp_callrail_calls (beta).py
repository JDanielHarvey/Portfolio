'''
	AUTHOR: Joshua Harvey
	ORIG DATE: 2020, 6, 29
	PURPOSE: Ad-hoc large historical data pulls
	NOTES: n/a
'''

# __ module imports
from time import sleep
import requests
import json
import datetime
import datetime
import pyodbc 
import csv
import os

# -- prelims for AVP_GCSQL 
serverip = os.environ["GOOGLE_SERVER"]
serveruid = os.environ["GOOGLE_SQLUID"]
serverpwd = os.environ["GOOGLE_SQLPWD"]

conn_string = '''
    DRIVER={SQL Server Native Client 11.0};
    SERVER=serverip;Database=avp_marketing;
    UID=serveruid;PWD=serverpwd;
    '''
insert_query = '''
	INSERT INTO callrail_calls_py 
		(answered, business_phone_number, customer_city, customer_country,
		customer_phone_number, customer_state, direction,
		duration, id,
		start_time, tracking_phone_number, company_id,
		company_name, device_type, first_call, prior_calls,
		campaign, medium, source, source_name, referring_url,
		keywords, landing_page_url, last_requested_url, utm_medium,
		utm_term, utm_content, utm_campaign, ga, gclid, fbclid) 
	VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
	'''
insert_query = insert_query.replace('\n','').replace('\t','')




# __ global variable declaration (prelims for callrail) 
account_id = '524183757'
api_tok = 'Token 6fab3261e8737c493908aff8529e7611'
field_select = '''
	company_id,company_name,created_at,device_type,
	first_call,prior_calls,campaign,medium,
	source,source_name,referring_url,keywords,
	landing_page_url,last_requested_url,utm_medium,utm_term,
	utm_content,utm_campaign,ga,gclid,fbclid
	'''
field_select = field_select.replace('\n','').replace('\t','')
ep_companies = 'https://api.callrail.com/v3/a/524183757/companies.json'
ep_calls = 'https://api.callrail.com/v3/a/524183757/calls.json'


prev_params = {'date_range': 'today', 'fields': field_select}
prev_req_get_calls = requests.get(f'{ep_calls}', headers={'Authorization': f'{api_tok}'}, params=prev_params, timeout=30)
key = list(prev_req_get_calls.json()['calls'][0].keys())

total_pages = prev_req_get_calls.json()['total_pages']
total_records = prev_req_get_calls.json()['total_records']

calls_array = []

with pyodbc.connect(conn_string) as sql_conn:
	cur = sql_conn.cursor()


# -- creates a flat file to create the SQL schema using SSIS
path = 'C:\\Users\\Joshua\\Downloads\\'
with open(f'{path}callrail_schema_build.csv', 'w') as new_file:
	csv_writer = csv.writer(new_file, delimiter=',')

# # -- write the headers to the sql prep file
# 	mydic = req_get_calls.json()['calls'][0]
# 	del mydic['recording']
# 	del mydic['recording_duration']
# 	del mydic['recording_player']
# 	del mydic['voicemail']
# 	del mydic['created_at']
# 	del mydic['customer_name']


	print(key)
	print()
	print(total_pages)
	print(total_records)
	print()

	for page in range(total_pages):
		page += 1
		full_params = {'date_range': 'today', 'fields': field_select, 'sort': 'start_time', 'order': 'asc', 'page': page, 'per_page': 250}
		req_get_calls = requests.get(f'{ep_calls}', headers={'Authorization': f'{api_tok}'}, params=full_params, timeout=30)
		calls_json = req_get_calls.json()['calls']


		for obj in calls_json:
			key_val0 = obj[f'{key[0]}']
			key_val1 = obj[f'{key[1]}']
			key_val2 = obj[f'{key[2]}']
			key_val3 = obj[f'{key[3]}']
			# key_val4 = obj[f'{key[4]}']
			key_val5 = obj[f'{key[5]}']
			key_val6 = obj[f'{key[6]}']
			key_val7 = obj[f'{key[7]}']
			key_val8 = obj[f'{key[8]}']
			key_val9 = obj[f'{key[9]}']
			# key_val10 = obj[f'{key[10]}']
			# key_val11 = obj[f'{key[11]}']
			# key_val12 = obj[f'{key[12]}']
			try:
				key_val13 = datetime.datetime.strptime(obj[f'{key[13]}'],'%Y-%m-%dT%H:%M:%S.%f%z')
			except:
				key_val13 = obj[f'{key[13]}']
			key_val14 = obj[f'{key[14]}']
			# key_val15 = obj[f'{key[15]}']
			key_val16 = obj[f'{key[16]}']
			key_val17 = obj[f'{key[17]}']
			# key_val18 = obj[f'{key[18]}']
			key_val19 = obj[f'{key[19]}']
			key_val20 = obj[f'{key[20]}']
			key_val21 = obj[f'{key[21]}']
			key_val22 = obj[f'{key[22]}']
			key_val23 = obj[f'{key[23]}']
			key_val24 = obj[f'{key[24]}']
			key_val25 = obj[f'{key[25]}']
			try:
				key_val26 = obj[f'{key[26]}'].split('?')[0]
			except:
				key_val26 = obj[f'{key[26]}']
			key_val27 = obj[f'{key[27]}']
			#key_val28 = (obj[f'{key[28]}'][:100]) if len(obj[f'{key[28]}']) > 100 else obj[f'{key[28]}']
			try:
				key_val28 = obj[f'{key[28]}'].split('?')[0]
			except:
				key_val28 = obj[f'{key[28]}']
			try:
				key_val29 = obj[f'{key[29]}'].split('?')[0]
			except:
				key_val29 = obj[f'{key[29]}']
			key_val30 = obj[f'{key[30]}']
			key_val31 = obj[f'{key[31]}']
			key_val32 = obj[f'{key[32]}']
			key_val33 = obj[f'{key[33]}']
			key_val34 = obj[f'{key[34]}']
			key_val35 = obj[f'{key[35]}']
			key_val36 = obj[f'{key[36]}']


			calls_array.append((key_val0,
				key_val1, key_val2, key_val3,
				key_val5, key_val6, key_val7,
				key_val8,key_val9,key_val13,
				key_val14, key_val16, key_val17,
				key_val19, key_val20, key_val21,
				key_val22, key_val23, key_val24,
				key_val25, key_val26, key_val27,
				key_val28, key_val29, key_val30,
				key_val31, key_val32, key_val33,
				key_val34, key_val35, key_val36))


	headers = tuple((key[0],
		key[1], key[2], key[3],
		key[5], key[6], key[7],
		key[8],key[9],key[13],
		key[14], key[16], key[17],
		key[19], key[20], key[21],
		key[22], key[23], key[24],
		key[25], key[26], key[27],
		key[28], key[29], key[30],
		key[31], key[32], key[33],
		key[34], key[35], key[36]))

	csv_writer.writerow(headers)

	print(headers)

	for row in calls_array:
		print(row)
		csv_writer.writerow(row)

	# cur.executemany(insert_query, calls_array)
