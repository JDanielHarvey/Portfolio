

create or alter view ref.typeform_responses as

/*
	AUTHOR: Joshua Harvey
	ORIG DATE: 2021-08-03
	PURPOSE: quick way to view responses for typeform submissions
	SOURCE: 
*/


select 
	items_response_id, items_submitted_at, items_metadata_platform, items_calculated_score, 
	[field.id], [field.type], type, [choice.id], [choice.label], boolean, text,
	email, phone
from (
	select 
		items_response_id, items_submitted_at, items_metadata_platform, items_calculated_score, 
		[field.id], [field.type], type, [choice.id], [choice.label], boolean, text,
		max(email) over(partition by items_response_id) 'email',
		max(phone_number) over(partition by items_response_id) 'phone',
		row_number() over(partition by items_response_id order by items_submitted_at) 'rowx'
	from AVP_Marketing.[src].[typeform_responses]
	) sq
where rowx = 1


