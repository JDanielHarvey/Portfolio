/*
	AUTHOR: Joshua Harvey
	ORIG DATE: 2021-08-10
	PURPOSE: creates a record log table for emails
	NOTES: 
		all emails that have been updated or added as new persons should 
		be verified in the SSIS package with ZeroBounce
*/


--> first instance to build base table
	--> 579,273 @ 00:23
--drop table if exists AVP_Marketing.ref.ng_patient_emails
--select  
--	p.person_id, 
--	lower(p.email_address) 'email', 
--	AVP_Marketing.dbo.ChkValidEmail(p.email_address) 'email_validity',
--	dateadd(day, -1, getdate()) 'insert_date',
--	p.modify_timestamp as 'record_date',
--	null as 'emailStatus',
--	null as 'modify_date'
--into AVP_Marketing.ref.ng_patient_emails
--from ngprod.dbo.person p 
--where AVP_Marketing.dbo.ChkValidEmail(p.email_address) = 1
--	and cast(p.create_timestamp as date) < cast(dateadd(day, -1, getdate()) as date)



--_________________________________SEC 1: Base Email Table_________________________________

--> obtain all records that were created or modified yesterday
	--> 4042 @ 00:01
drop table if exists #emails_1a
select  
	p.person_id, 
	lower(p.email_address) 'new_email', 
	AVP_Marketing.dbo.ChkValidEmail(p.email_address) 'email_validity',
	case 
		when cast(p.create_timestamp as date) >= cast(dateadd(day, -1, getdate()) as date) then 'created'
		when cast(p.modify_timestamp as date) >= cast(dateadd(day, -1, getdate()) as date) then 'modified'
		else null
	end as 'change_type',
	p.create_timestamp,
	p.modify_timestamp
into #emails_1a
from ngprod.dbo.person p 
where trim(p.email_address) != '' and p.email_address is not null
	and 
	(
		cast(p.create_timestamp as date) = cast(dateadd(day, -1, getdate()) as date)
		or 
		cast(p.modify_timestamp as date) = cast(dateadd(day, -1, getdate()) as date)
	)


--_________________________________SEC 2: Comparison_________________________________

drop table if exists #emails_2a
;with 
cte1a as (
	select 
		e1a.*,
		sq.email 'old_email',
		case
			when e1a.new_email = sq.email then 'same'
			when e1a.email_validity = 1 and e1a.new_email != sq.email then 'update'
			else null
		end as 'update_type'
	--into #newT_comparison_1a
	from #emails_1a e1a
	left join (select * from AVP_Marketing.ref.ng_patient_emails) sq on 
		e1a.person_id = sq.person_id
	where change_type = 'modified' and sq.email is not null
	)
select *
into #emails_2a
from cte1a 
where update_type != 'same'


--_________________________________SEC 3: Write the updates_________________________________

--> Update the 'emailStatus' for existing persons email records
update AVP_Marketing.ref.ng_patient_emails
set emailStatus = 'outdated', modify_date = e2a.modify_timestamp
from AVP_Marketing.ref.ng_patient_emails pe
inner join #emails_2a e2a on
	pe.person_id = e2a.person_id and 
	pe.email = e2a.old_email
where update_type = 'update'


--> Inserts the new persons email records for existing persons
insert into AVP_Marketing.ref.ng_patient_emails (person_id, email, email_validity, insert_date, record_date, emailStatus, modify_date)
select person_id, new_email, email_validity, getdate() as insert_date, modify_timestamp, null as 'emailStatus', null 'modify_date'
from #emails_2a e2a
where update_type = 'update'



--_________________________________SEC 4: Write New Persons_________________________________

insert into AVP_Marketing.ref.ng_patient_emails (person_id, email, email_validity, insert_date, record_date, emailStatus, modify_date)
select
	person_id, new_email 'email', email_validity, getdate(), create_timestamp, null as emailStatus, null as modify_date
from #emails_1a
where 
	change_type = 'created' and 
	email_validity = 1 



--_________________________________SEC 4: Used only in SSIS packages_________________________________

----> get a count to compare against current number of available credits in ZeroBounce account
--select count(*) 'cnt'
--from AVP_Marketing.ref.ng_patient_emails
--where 
--	cast(insert_date as date) = cast(dateadd(day, 0, getdate()) as date) or 
--	cast(modify_date as date) = cast(dateadd(day, 0, getdate()) as date) 


----> used as a payload for the zeroBounce validation API endpoint 
--select
--	person_id,
--	email,
--	null as 'ip_address'
--from AVP_Marketing.ref.ng_patient_emails
--where 
--	cast(insert_date as date) = cast(dateadd(day, 0, getdate()) as date) or 
--	cast(modify_date as date) = cast(dateadd(day, 0, getdate()) as date) 
	


