/*
	AUTHOR: Joshua  Harvey
	ORIG DATE: 2020, 06, 24
	PURPOSE: Merge the roi_calls and roi_forms and remove any duplications
	NOTES: 130+134+318+280+250+70 = 1182 lines
*/

--> union the two roi digital tables
	--> for leads with the same create date, we only want one and it doesn't matter which one...
	--> though ideally we would have used the date/time to determine that 

	--> for leads with different create dates, we want the first one
	--> exclude the second occurence

	--> since we want the first one in both situations this can be done in one step
	--> or it can be done in two steps for future proofing

	--> 1,676,132 after removing inst_prs_uniq_max
	--> 1,620,738 after removing inst_prs
DROP TABLE IF EXISTS AVP_Marketing.dbo.roi_paidmedia_digital
--SELECT * 
--FROM (
SELECT 
	sq2.person_id, sq2.lead_create_date, sq2.appt_create_date, sq2.net_rev,
	sq2.source_type, sq2.orig_source, sq2.campaign,
	COUNT(*) OVER(PARTITION BY sq2.person_id) 'cnt_integrity', sq2.inst_prs_uniq, sq2.inst_prs_uniq_rev
INTO AVP_Marketing.dbo.roi_paidmedia_digital
FROM (
	SELECT 
		sq.*,
		ROW_NUMBER() OVER(PARTITION BY sq.person_id ORDER BY sq.lead_create_date) 'inst_prs',
		DENSE_RANK() OVER(PARTITION BY sq.person_id ORDER BY sq.lead_create_date) 'inst_prs_uniq',
		DENSE_RANK() OVER(PARTITION BY sq.person_id ORDER BY sq.net_rev DESC) 'inst_prs_uniq_rev',
		COUNT(*) OVER(PARTITION BY sq.person_id) 'cnt'
	FROM (
		SELECT 
			df.person_id, 
			df.hs_create_date 'lead_create_date',
			df.appt_create_date,
			df.net_rev,
			'form' AS 'source_type',
			df.[Original Source] 'orig_source',
			df.utm_campaign 'campaign'
		FROM AVP_Marketing.dbo.fx_roi_paidmedia_digital_forms df
			UNION
		SELECT 
			dc.person_id, 
			dc.first_call_date 'lead_create_date',
			dc.appt_create_date,
			dc.net_rev,
			'phone' AS 'source_type',
			dc.source 'orig_source',
			ISNULL(dc.campaign, dc.utm_campaign) 'campaign'
		FROM AVP_Marketing.dbo.fx_roi_paidmedia_digital_calls dc

			--UNION
		--SELECT 
		--	dd.person_id,
		--	dd.first_date 'lead_create_date',
		--	dd.appt_create_date,
		--	dd.net_rev,
		--	'phone' AS 'source_type',
		--	'healthgrades' AS 'orig_source',
		--	NULL AS 'campaign'
		--FROM AVP_Marketing.dbo.fx_roi_paidmedia_digital_directories dd
		) AS sq
	) sq2
WHERE sq2.inst_prs_uniq = 1
--) sq3
--WHERE sq3.cnt_integrity = 2
GO


--> preview the results
--SELECT * FROM AVP_Marketing.dbo.roi_paidmedia_digital rpd
--GO


--> troubleshoot 
--SELECT * FROM (
--	SELECT 
--		sq.*,
--		ROW_NUMBER() OVER(PARTITION BY sq.person_id ORDER BY sq.lead_create_date) 'inst_prs',
--		DENSE_RANK() OVER(PARTITION BY sq.person_id ORDER BY sq.lead_create_date) 'inst_prs_uniq',
--		DENSE_RANK() OVER(PARTITION BY sq.person_id ORDER BY sq.net_rev DESC) 'inst_prs_uniq_rev',
--		COUNT(*) OVER(PARTITION BY sq.person_id) 'cnt_prs'
--	FROM (
--		SELECT 
--			df.person_id, 
--			df.hs_create_date 'lead_create_date',
--			df.appt_create_date,
--			df.net_rev,
--			'form' AS 'source_type',
--			df.[Original Source] 'orig_source',
--			df.utm_campaign
--		FROM AVP_Marketing.dbo.roi_paidmedia_digital_forms df
--			UNION
--		SELECT 
--			dc.person_id, 
--			dc.first_call_date 'lead_create_date',
--			dc.appt_create_date,
--			dc.net_rev,
--			'phone' AS 'source_type',
--			dc.source 'orig_source',
--			dc.utm_campaign
--		FROM AVP_Marketing.dbo.roi_paidmedia_digital_calls dc
--		) AS sq
--	) sq2
--	WHERE sq2.person_id IN (
--	'84B5F533-5F2E-4DC4-AC9C-035DF88E514C',
--'BE2891FC-27F4-49ED-B3B8-06AC8D415A7F',
--'CFF67CFE-EA95-4A33-B91E-09DEFB760646',
--'E0BD4733-51C9-4784-8F3B-3C7F2A5A4D6A',
--'C3CD8A71-EAFA-4571-AEAF-505B188F1DD1',
--'62161AE4-D5CC-4EE1-9F9D-606143EBF48E',
--'DD6952F8-BEBD-498B-856F-6391862D317E',
--'0E55E3E5-7633-40D3-A8EA-745CA421CCAF',
--'AA833E6A-B314-42AB-9122-74CEF5FEEEFE',
--'4B3DCF24-D816-44C8-9435-8EB6ACB7E2C8',
--'55A1C900-F6BE-4367-8A95-96E1562D0FE5',
--'7AA1A053-2B16-49D9-AFA9-97E2735F58E5',
--'E7FAB336-05B4-4476-8618-E39104DB91C2'
--	)