

create or alter view [vwAVP_invalid_home_address_prefix] as

/*
	AUTHOR: Joshua Harvey
	ORIG DATE: 2021-05-06
	PURPOSE:  manual construction of incorrect formats to the start of home address
	SOURCE: 
		
*/


select * 
from 
	( values
		('apt' ),
		('lot' ),
		('unit'), 
		('spc' ), 
		('box'), 
		('number'), 
		('site'), 
		('p.o.'), 
		('po'), 
		('trlr')
	) as NonAds(prefix)