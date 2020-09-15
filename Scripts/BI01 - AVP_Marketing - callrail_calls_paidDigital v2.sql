/*
	AUTHOR: Joshua  Harvey
	ORIG DATE: 2020, 06, 22
	PURPOSE: Find patients from digital calls 
	NOTES: 
*/


--> build the callrail paid calls table, removing duplicates
	--> callrail_calls_paidDigital = 3,742 (2020, 06, 22)
	--> this section can be reserved for including the scripts to...
	--> ...format the callrail paid callers table (BI01 - AVP_Marketing - callrail_callers_paidDigital.sql)
DROP TABLE IF EXISTS ##paid_callers_base
SELECT 
	sq2.*
INTO ##paid_callers_base
FROM (
		SELECT 
			sq.caller_id, sq.campaign, sq.source, sq.utm_campaign,
			ROW_NUMBER() OVER(PARTITION BY sq.caller_id ORDER BY sq.call_date ASC) 'instance',
			SUM(CAST(sq.duration AS INT)) OVER(PARTITION BY sq.caller_id) 'total_duration',
			MIN(sq.call_date) OVER(PARTITION BY sq.caller_id) 'first_call_date',
			MAX(sq.call_date) OVER(PARTITION BY sq.caller_id) 'last_call_date',
			COUNT(*) OVER(PARTITION BY sq.caller_id) 'number_calls'
		FROM (
			SELECT
				RIGHT(cc.customer_phone_number, 10) 'caller_id',
				cc.duration,
				CAST(cc.created_at AS Date) 'call_date',
				ca.company_abv +'___'+cc.campaign 'campaign',
				cc.source,
				cc.utm_campaign,
				cc.gclid,
				cc.fbclid
			FROM 
				AVP_Marketing.dbo.src_callrail_calls AS cc
					LEFT JOIN AVP_Marketing.dbo.src_callrail_companies ca ON 
						cc.company_id = ca.company_id 
			WHERE 
				LOWER(medium) = 'cpc' OR LOWER(utm_medium) IN ('cpc', 'paid') 
		) sq
	) sq2
WHERE sq2.instance = 1
GO


--> build the merge table to match on phone_number
	--> as of June 22 there were 1,882,180 patients with one or more phones
	--> results in 4320 expanded from 3732, b/c of multiple people sharing a phone ()
DROP TABLE IF EXISTS ##calls_match_base
SELECT 
	pcb.caller_id, pcb.first_call_date,
	sq.person_id, sq.ng_f_name,
	sq.ng_l_name, sq.surname_risk_lvl
INTO ##calls_match_base
FROM ##paid_callers_base pcb
LEFT JOIN (
	SELECT 
		npp.person_id,
		npp.PhoneNum 'ng_phone',
		LOWER(npp.first_name) 'ng_f_name',
		LOWER(npp.last_name) 'ng_l_name',
		npp.surname_risk_lvl
	FROM AVP_Marketing.dbo.ref_ng_patients_phones_nums_unpivot npp
	) AS sq ON
	pcb.caller_id = sq.ng_phone
GO


--> create the calls matched only table 
	--> 2312 matches (non distinct) and 2003 no matches (5 dupes of person)
DROP TABLE IF EXISTS ##calls_match_found
SELECT 
	sq.*
INTO ##calls_match_found
FROM (
	SELECT
		cmb.*,
		COUNT(*) OVER(PARTITION BY cmb.caller_id ORDER BY cmb.first_call_date) 'cnt_phone_ocur',
		ROW_NUMBER() OVER(PARTITION BY cmb.person_id ORDER BY cmb.first_call_date) 'inst_prsn'
	FROM ##calls_match_base cmb
		WHERE cmb.person_id IS NOT NULL 
	--ORDER BY cnt_phone_ocur DESC, cmb.caller_id
	) sq
WHERE sq.inst_prsn = 1
GO



--> bring in the ng_newpt_billable_v2 for the base dos. This is a critical step in the process...
--> and includes the main methodology behind the LTV calcualtion
	--> 2890 charges up from 2826 b/c of multiple appointments
	--> 990 where dos is greater than first call date (still multiple people)
	--> 827 single persons with dos after call date
DROP TABLE IF EXISTS ##calls_match_withdos
SELECT 
	sq2.person_id, MIN(sq2.first_call_date) 'first_call_date', 
	SUM(sq2.tot_new_paid) 'tot_new_paid', MIN(sq2.dos) 'dos', 
	MIN(sq2.appt_create_date) 'appt_create_date', 
	MAX(sq2.cnt_prs_dos) 'cnt_prs_dos'
INTO ##calls_match_withdos
FROM (
	SELECT 
		sq.*,
		ROW_NUMBER() OVER(PARTITION BY sq.person_id ORDER BY sq.dos) 'inst_prsn',
		COUNT(*) OVER(PARTITION BY sq.person_id) 'cnt_prs_dos'
	FROM (
			SELECT 
				cmf.person_id, 
				cmf.first_call_date,
				SUM(ISNULL(nnbv.paid,0)) 'tot_new_paid', nnbv.dos,
				CAST(ISNULL(a.create_timestamp, cmf.first_call_date) AS DATE) 'appt_create_date',
				DATEDIFF(DAY, cmf.first_call_date, nnbv.dos) 'diff_calldate_dos'
			FROM ##calls_match_found cmf
			LEFT JOIN AVP_Marketing.dbo.fx_ng_newpt_billable_v2 nnbv ON
				cmf.person_id = nnbv.person_id --AND
				--fm.practice_id = nnbv.practice_id
			LEFT JOIN NGPROD02.NGProd.dbo.appointments a ON
				nnbv.source_id = a.enc_id
			--WHERE cmf.person_id IN ('57D12E30-F70B-464C-943A-0107D8CD98D4','BD98B0E0-FD4A-48B6-92DD-017B9FC2EA64')
			GROUP BY cmf.person_id, cmf.first_call_date, a.create_timestamp, nnbv.dos
		) sq 
	WHERE sq.diff_calldate_dos >= 0
	--ORDER BY sq.person_id, sq.dos
	) sq2
GROUP BY sq2.person_id
GO


--> get transactions greater than the dos of new billable
	--> 19,013 @ 00:04
DROP TABLE IF EXISTS ##match_trans
SELECT 
	cmw.*, td.paid_amt, td.adj_amt, td.post_ind, t.[type], c.link_id, td.trans_id,
	CAST(td.create_timestamp AS DATE) 'tran_date'
INTO ##match_trans
FROM ##calls_match_withdos cmw
	LEFT JOIN NGPROD02.NGProd.dbo.transactions t ON
		t.person_id = cmw.person_id
	LEFT JOIN NGPROD02.NGProd.dbo.trans_detail td ON
		t.trans_id = td.trans_id
	LEFT JOIN NGPROD02.NGProd.dbo.charges c ON
		td.charge_id = c.charge_id
WHERE CAST(td.create_timestamp AS DATE) >= cmw.dos
GO


--> aggegate the paid amounts of 827 persons 
	--> refunds shouldn't exceed $9,074
	--> received shouldn't exceed $838,529
DROP TABLE IF EXISTS ##match_totals
SELECT cmw.*,ISNULL(sq2.tot_received,0) 'tot_rec', ISNULL(sq2.tot_refunds,0) 'tot_ref'
INTO ##match_totals
FROM ##calls_match_withdos cmw
	LEFT JOIN (
		SELECT
			mt.person_id, mt.first_call_date, mt.tot_new_paid,
			mt.dos, mt.cnt_prs_dos,
			SUM(ISNULL(mt.paid_amt,0)*-1) 'tot_received', MIN(ISNULL(sq.tot_refunds,0)) 'tot_refunds'
		FROM ##match_trans mt
			LEFT JOIN 
				(
				SELECT
					mt.person_id,
					SUM(ISNULL(mt.adj_amt,0)*-1) 'tot_refunds'
				FROM ##match_trans mt
				WHERE mt.type = 'R' AND mt.post_ind = 'Y' AND mt.link_id IS NULL
				GROUP BY 
					mt.person_id
				) AS sq ON 
				mt.person_id = sq.person_id
		WHERE mt.post_ind = 'Y' AND mt.link_id IS NULL
		GROUP BY 
			mt.person_id, mt.first_call_date, mt.tot_new_paid,
			mt.dos, mt.cnt_prs_dos
		) AS sq2 ON
	cmw.person_id = sq2.person_id
ORDER BY cmw.person_id, cmw.dos ASC
GO


--> rebuild the original union table so we can use PII attributes to evaluate shared contact info persons
	--> Of 2312 total 827 dos is not null and 784 cr_first_call_date >= 0
	--> 44 cr_first_call_date after appt_create. 75,293.01 lost 
	--> 75 instances requiring double_yolk eval
DROP TABLE IF EXISTS ##match_dbl1
SELECT
	sq.*
INTO ##match_dbl1
FROM (
	SELECT
		cmf.person_id, cmf.caller_id, 
		cmf.ng_f_name, cmf.ng_l_name, 
		p.address_line_1, p.address_line_2,
		cmf.first_call_date, mf.appt_create_date, cmf.surname_risk_lvl,
		DATEDIFF(DAY,cmf.first_call_date, mf.appt_create_date) 'dif_crCreate_ngApptCreate',
		ROW_NUMBER() OVER(PARTITION BY cmf.caller_id ORDER BY mf.appt_create_date DESC) 'inst_cr',
		COUNT(*) OVER(PARTITION BY cmf.caller_id) 'cnt_cr'
	FROM ##calls_match_found cmf
	LEFT JOIN ##match_totals mf ON
		cmf.person_id = mf.person_id
	LEFT JOIN NGPROD02.NGProd.dbo.person p ON
		cmf.person_id = p.person_id
	WHERE mf.dos IS NOT NULL
	) sq
WHERE sq.dif_crCreate_ngApptCreate >= 0 AND sq.cnt_cr > 1
ORDER BY sq.first_call_date ASC, sq.caller_id, sq.appt_create_date
GO


--> build the exclusion person_ids using the algorithm
--> strip out patients that share contact info using the probabilistic "avp_dbl_yolk" algorithm
	--> 365 days is 1 year
	--> 7 days * 4.33 weeks * 2 months = 61 days
	--> 75 total, 8 were lost to unlikely dbl_yolk benefit
DROP TABLE IF EXISTS ##match_dbl_exc
SELECT 
	sq2.person_id
INTO ##match_dbl_exc
FROM (
	SELECT 
		sq.*,
		sq.addr_match + sq.dbl_create_diff + sq.ng_l_name_match AS 'score'
	FROM (
		SELECT 
			m1.person_id, m1.caller_id, 
			m2.appt_create_date 'm2_appt_create_date',
			--DATEDIFF(DAY,m1.appt_create_date,ISNULL(m2.appt_create_date, m1.appt_create_date))*-1 'datediff', 
			CASE 
				WHEN m1.address_line_1 = ISNULL(m2.address_line_1, m1.address_line_1) THEN 2 ELSE -2
			END AS 'addr_match',
			CASE 
				WHEN m1.ng_f_name = ISNULL(m2.ng_f_name, m1.ng_f_name) AND
					m1.ng_l_name = ISNULL(m2.ng_l_name, m1.ng_l_name) 
				THEN 10 ELSE 0
			END AS 'ng_full_name_match',
			CASE 
				WHEN m1.ng_l_name = ISNULL(m2.ng_l_name, m1.ng_l_name) THEN 2 ELSE -2
			END AS 'ng_l_name_match',
			CASE 
				WHEN DATEDIFF(DAY,m1.appt_create_date,ISNULL(m2.appt_create_date, m1.appt_create_date)) = 0 THEN 5
				WHEN DATEDIFF(DAY,m1.appt_create_date,ISNULL(m2.appt_create_date, m1.appt_create_date)) >= 3 THEN 3
				WHEN DATEDIFF(DAY,m1.appt_create_date,ISNULL(m2.appt_create_date, m1.appt_create_date))*-1 > 365 THEN -6
				WHEN DATEDIFF(DAY,m1.appt_create_date,ISNULL(m2.appt_create_date, m1.appt_create_date))*-1 >= 61 THEN -2
				ELSE 2 
			END AS 'dbl_create_diff'
		FROM ##match_dbl1 m1
			LEFT JOIN ##match_dbl1 m2 ON
				m1.caller_id = m2.caller_id AND 
				m1.inst_cr = m2.inst_cr-1
		) sq
	) sq2
WHERE sq2.score < 0
GO


--> build the final table in the AVP_Marketing db
	--> 831,936 gross before stripping out ApptCreate before hs_create
	--> 756,643 gross after hs_create before ApptCreate (-75,293)
	--> WHERE filter was omitted b/c the analysis will be done in the reporting tool
DROP TABLE IF EXISTS AVP_Marketing.dbo.roi_paidmedia_digital_calls
SELECT 
	sq.*
INTO AVP_Marketing.dbo.roi_paidmedia_digital_calls
FROM (
	SELECT
		cmf.caller_id,
		cmf.person_id, cmf.ng_f_name, cmf.ng_l_name,
		cmf.first_call_date,
		mt.appt_create_date,
		DATEDIFF(DAY,cmf.first_call_date, mt.appt_create_date) 'crCreate_ngApptCreate_dif',
		mt.tot_new_paid, mt.tot_rec, mt.tot_ref, mt.tot_rec-mt.tot_ref 'net_rev',
		pd.source, pd.utm_campaign, pd.campaign
	FROM ##calls_match_found cmf
	LEFT JOIN ##match_totals mt ON
		cmf.person_id = mt.person_id
	LEFT JOIN AVP_Marketing.dbo.ref_callrail_callers_paidDigital pd ON
		cmf.caller_id = pd.caller_id
	WHERE cmf.person_id NOT IN (SELECT mde.person_id FROM ##match_dbl_exc mde)
	--ORDER BY mt.tot_rec DESC
	) sq
--WHERE NOT sq.crCreate_ngApptCreate_dif < 0
GO


SELECT * FROM AVP_Marketing.dbo.fx_roi_paidmedia_digital_calls rpdc
WHERE rpdc.campaign IS NULL AND rpdc.utm_campaign IS NOT NULL

/*
--> used to compare pulling directly from charges rather than billable
-- 838 - 153 nulls = 685 with charges
SELECT 
	fm.person_id, fm.ng_email,fm.practice_id, 
	TRY_CAST(fm.[Create Date] AS DATE) 'lead_create',
	MIN(c.begin_date_of_service) 'first_dos', MAX(c.begin_date_of_service) 'last_dos'
FROM ##forms_match fm
LEFT JOIN NGPROD02.NGProd.dbo.charges c ON 
	fm.person_id = c.person_id AND
	fm.practice_id = c.practice_id
GROUP BY fm.person_id, fm.ng_email, fm.practice_id, fm.[Create Date], fm.create_timestamp
ORDER BY MIN(c.begin_date_of_service) ASC
*/