
CREATE OR ALTER VIEW ref.one23formbuilder_submissions AS

/*
	AUTHOR: Joshua Harvey
	ORIG DATE: 2021-07-21
	PURPOSE: quick way to view submissions in a cross tabulated format
	SOURCE: 
*/


SELECT 
	formName, pt.submissions_xml_id, pt.submissions_date, pt.submissions_refid, 
	[First name] 'fname', [Last name] 'lname', [Email] 'email',
	[Are you an existing patient?] 'new_exist', [Clinic Location] 'clinic_loc',
	[What service are you interested in?] 'new_service', [How can we help you?] 'exist_help',
	[um_medium] 'source_medium', [Please choose one of the following?] 'nonpatient'
FROM (
	SELECT 
		fo.formName, 
		fs.submissions_xml_id, fs.submissions_date, fs.submissions_refid, fs.submissions_browser, 
		fs.submissions_formhost, ff.fieldTitle, fs.fieldvalue
	FROM AVP_Marketing.[src].[one23_formbuilder_submissions] fs
	LEFT JOIN AVP_Marketing.src.one23_formbuilder_forms fo ON
		fs.formId = fo.formId
	LEFT JOIN AVP_Marketing.[src].[one23_form_fields] ff ON 
		fs.formId = ff.formId AND 
		fs.fieldid = ff.fieldId
	WHERE fo.formName LIKE '%Contact Us' AND fieldvalue != ''
	) sq
	PIVOT(
		MIN(fieldvalue)
		FOR fieldTitle IN (
			[First name],
			[Last name],
			[Email],
			[Are you an existing patient?],
			[Clinic Location],
			[What service are you interested in?],
			[Please choose one of the following?],
			[How can we help you?],
			[um_medium]) 
		) AS pt
WHERE 
	LOWER([pt].[Email]) NOT LIKE '%test%' AND LOWER([pt].[Email]) NOT LIKE '%americanvisionpartners%' AND 
	LOWER([First name]) NOT LIKE '%test%' AND LOWER([Last name]) NOT LIKE '%lname%'
	AND [What service are you interested in?] NOT LIKE 'Cosmet%'



