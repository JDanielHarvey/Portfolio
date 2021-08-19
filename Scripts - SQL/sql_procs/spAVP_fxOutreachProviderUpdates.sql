create or alter proc spAVP_fxOutreachProviderUpdates
as 

begin 

/*
	AUTHOR: Joshua Harvey
	ORIG DATE: 2021-03-03
	PURPOSE:  report for modifications being made to the master provider table 
	SOURCE: ngprod02 
*/

--> generate the list of outreach users
drop table if exists #outreach_users
;with 
cte1a as (
	select 
		um.last_name, um.first_name, um.[start_date],
		try_cast(um.last_logon_date as date) 'last_logon', um.delete_ind,
		xr.[user_id],
		sg.group_id, sg.group_name, sg.[description], um.create_timestamp,
		row_number() over(partition by um.user_id order by last_logon_date desc) 'rowXuser|login'
	from [NGProd02].NGProd.dbo.security_groups sg
		inner join [NGProd02].NGProd.dbo.user_group_xref xr
			on sg.group_id = xr.group_id
		inner join [NGProd02].NGProd.dbo.user_mstr um 
			on xr.[user_id] = um.[user_id]
	where lower(sg.group_name) LIKE '%outreach%' and delete_ind = 'N'
	)
select last_name, first_name, user_id
into #outreach_users
from cte1a
group by last_name, first_name, user_id


--> get all providers that have been updated or modified 
drop table if exists #outreach_updates
select 
	-- identity info
	provider_id, lower(pm.last_name) 'last_name', lower(pm.first_name) 'first_name', 
	-- practice address
	lower(refer_practice_name) 'practice_name',  lower(address_line_1) 'address_line_1', lower(address_line_2) 'address_line_2', lower(city) 'city', state, left(zip,5) 'zip',
	-- contact information
	phone, home_phone, home_fax, mobile_phone, fax, lower(email_address) 'email_address',
	-- identity info
	national_provider_id, degree,
	-- dates
	create_timestamp, datediff(day, create_timestamp, getdate()) 'days_since_create', 
	modify_timestamp, delete_ind, ou.first_name 'agent_create_fname', ou2.first_name 'agent_mod_fname'
	--case 
		--when create_timestamp = modify_timestamp and ou.user_id is not null then 'created'
		--when create_timestamp != modify_timestamp and ou2.user_id is not null then 'modified'
		--when ou.user_id is not null then 'created'
		--when ou2.user_id is not null then 'modified'	
	--end as 'updates'
into #outreach_updates
from NGPROD02.NGProd.dbo.provider_mstr pm
left join  #outreach_users ou on 
	pm.created_by = ou.user_id
left join #outreach_users ou2 on 
	pm.modified_by = ou2.user_id 
where ou.user_id is not null or ou2.user_id is not null


;with cte1a as (
	select 
		create_timestamp 'update_timestamp', agent_create_fname 'agent_name', delete_ind, degree, 'create' as 'update_type'
	from #outreach_updates
	where agent_create_fname is not null
		 union
	select 
		modify_timestamp 'update_timestamp', agent_mod_fname 'agent_name', delete_ind, degree, 'modify' as 'update_type'
	from #outreach_updates
	where agent_mod_fname is not null
	)
select c1a.update_timestamp, c1a.agent_name, c1a.delete_ind, c1a.degree, c1a.update_type
from cte1a c1a
order by update_timestamp desc


end