'''
	Robinhood trader bot on RSI oversold
'''

import yfinance as yf
import robin_stocks as r 
import pyotp
import os 

# sec 0 - robinhood login
r_mfa = os.environ.get('robinhood_mfa')
r_un = os.environ.get('robinhood_un')
r_pw = os.environ.get('robinhood_pw')


totp = pyotp.TOTP(r_mfa).now()

login = r.login(r_un,r_pw, expiresIn=86400, mfa_code=totp)


# sec 1 - get data
data = yf.download(tickers="SOLO", period="1d", interval="1m")

list1 = []
list2 = []
x = 0


for num, i in enumerate(data.Close - data.Open, start=1):
	
	x += 1

	if (x <= 14):
		list1.append(i)
		
		if(x == 14):
			rs = sum(list1)
			list2.append( 100 - ( 100 / (1+rs) ) )	
	
	else:
		x = 1
		list1.clear()

	
last_item_list2 = list2[-1]

print()
print(f'this is all the items in list2: {list2}')
print()
print(f'this is the last item in list2: {last_item_list2}')
print()


# testing the 2nd 14 min period in SOLO's trading day on 11/27
if list2[1] < -70: #and open positions is null and open orders is null 
	print('this would execute a trade on robinhood')

	lat_ask = r.get_latest_price('SOLO', priceType='ask_price', includeExtendedHours=True)


	# if r.get_all_open_stock_orders():	
		# r.order_buy_limit('SOLO', quantity, limitPrice, timeInForce='gtc', extendedHours=False)



solo_lat_ask = float(r.get_latest_price('PLUG', priceType='ask_price', includeExtendedHours=True)[0])

solo_inst_url = r.get_instruments_by_symbols('PLUG')[0]['url']


for position in r.get_all_positions():
	if position['instrument'] == solo_inst_url:
		solo_avg_buy = float(position['average_buy_price'])

		print('this is the current price diff')
		print(solo_lat_ask - solo_avg_buy)


# print(dir(r))