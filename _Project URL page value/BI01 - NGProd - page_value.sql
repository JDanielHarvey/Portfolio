/*
	AUTHOR: Joshua Harvey	
	ORIG DATE: 2020, 7, 14
	PURPOSE: Strict determination about person_id and phone number association
	NOTES:
*/


--> 193,171 @ 00:01
DROP TABLE IF EXISTS ##pageviews_base
SELECT
	RIGHT(cc.customer_phone_number, 10) 'caller_id', 
	cc.created_at 'call_date', cp.page_url, cp.created_at 'pageview_date'
INTO ##pageviews_base
FROM AVP_Marketing.dbo.src_callrail_pageviews cp
LEFT JOIN AVP_Marketing.dbo.src_callrail_calls cc ON
	cp.call_id = cc.id
GO


--> pull all appts for all callrail calls 
	--> 71,569 @ 00:11
DROP TABLE IF EXISTS ##phone_match_base
SELECT 
	cc.caller_id, npp.PhoneNum, npp.person_id, 
	npp.last_name, npp.first_name,
	cc.call_date,
	a.create_timestamp 'appt_create_date', 
	a.enc_id,
	DATEDIFF(DAY,cc.call_date, a.create_timestamp) 'dDiff'
INTO ##phone_match_base
FROM (SELECT DISTINCT caller_id, call_date FROM ##pageviews_base) cc
	LEFT JOIN AVP_Marketing.dbo.ref_ng_patients_phones_nums_unpivot npp ON
		cc.caller_id = npp.PhoneNum
	LEFT JOIN NGPROD02.NGProd.dbo.appointments a ON
		npp.person_id = a.person_id
WHERE CAST(a.create_timestamp AS DATE) >= CAST(cc.call_date AS DATE)
GO


--> intermediary table prior to obtaining expenses
DROP TABLE IF EXISTS ##caller_2a
SELECT 
	sq2.*,
	CASE 
		WHEN DATEDIFF(DAY, sq2.first_appt, sq2.call_date) = 0 THEN 'full_credit'
		WHEN DATEDIFF(DAY, sq2.first_appt, sq2.call_date) > 0 THEN 'rel_credit'
	END AS 'credit_attr'
INTO ##caller_2a
FROM (
	SELECT 
		pmb.*, sq.first_appt,
		ROW_NUMBER() OVER(PARTITION BY pmb.PhoneNum, pmb.person_id, pmb.enc_id ORDER BY pmb.appt_create_date) 'rowX3I1'
	FROM ##phone_match_base pmb
		LEFT JOIN 
			(SELECT pmb.person_id, MIN(pmb.appt_create_date) 'first_appt'
			FROM ##phone_match_base pmb
			GROUP BY pmb.person_id
			) sq ON
			pmb.person_id = sq.person_id
	WHERE pmb.dDiff = 0
	) sq2
WHERE sq2.rowX3I1 = 1
GO


--____________________SECTION: full_credit transactions____________________ 
--> obtain all expenses for these people 
	--> 102,685 @ 00:05
DROP TABLE IF EXISTS ##fc_trans_1a
SELECT 
	sq.person_id, t.type, td.paid_amt, td.adj_amt
INTO ##fc_trans_1a
FROM (
	SELECT 
		c2a.person_id, c2a.first_appt
	FROM ##caller_2a c2a
	WHERE credit_attr = 'full_credit' AND c2a.enc_id IS NOT NULL
	) sq
LEFT JOIN NGPROD02.NGProd.dbo.transactions t ON
	sq.person_id = t.person_id
LEFT JOIN NGPROD02.NGprod.dbo.trans_detail td ON
	t.trans_id = td.trans_id
LEFT JOIN NGPROD02.NGProd.dbo.charges c ON
	td.charge_id = c.charge_id
WHERE c.link_id IS NULL AND CAST(t.tran_date AS DATE) >= sq.first_appt AND t.post_ind = 'Y'
GO


--> create the aggregation table 
	--> 4,638 @ 00:00
DROP TABLE IF EXISTS ##fc_trans_2a
SELECT
	t1a.person_id, 
	'full_credit' AS 'credit_attr',
	SUM(ISNULL(t1a.paid_amt, 0)*-1) 'received',
	MIN(ISNULL(sq.refunds,0)) 'refunds',
	SUM(ISNULL(t1a.paid_amt, 0)*-1) + MIN(ISNULL(sq.refunds,0)) 'net'
INTO ##fc_trans_2a
FROM ##fc_trans_1a t1a
LEFT JOIN (
	SELECT 
		t1a.person_id, SUM(ISNULL(t1a.adj_amt, 0)*-1) 'refunds'
	FROM ##fc_trans_1a t1a
	WHERE t1a.type = 'R' 
	GROUP BY t1a.person_id
	) sq ON
	t1a.person_id = sq.person_id
WHERE t1a.type != 'R'
GROUP BY t1a.person_id
GO


--____________________SECTION: rel_credit transactions____________________ 
--> trans base prior to received and refunds
	--> 70 @ 00:01
DROP TABLE IF EXISTS ##rc_trans_1a
SELECT
	sq.person_id, sq.enc_id, t.type, td.paid_amt, td.adj_amt
INTO ##rc_trans_1a
FROM (
	SELECT
		c2a.person_id, c2a.enc_id
	FROM ##caller_2a c2a
	WHERE credit_attr = 'rel_credit' AND enc_id IS NOT NULL
	) sq
	LEFT JOIN NGPROD02.NGProd.dbo.transactions t ON
		sq.person_id = t.person_id AND
		sq.enc_id = t.source_id
	LEFT JOIN NGPROD02.NGprod.dbo.trans_detail td ON
		t.trans_id = td.trans_id
	LEFT JOIN NGPROD02.NGProd.dbo.charges c ON
		td.charge_id = c.charge_id
WHERE c.link_id IS NULL
GO


--> create the aggregation table 
	--> 14 @ 00:01
DROP TABLE IF EXISTS ##rc_trans_2a
SELECT
	t1a.person_id, t1a.enc_id,
	'rel_credit' AS 'credit_attr',
	SUM(ISNULL(t1a.paid_amt, 0)*-1) 'received',
	MIN(ISNULL(sq.refunds,0)) 'refunds',
	SUM(ISNULL(t1a.paid_amt, 0)*-1) + MIN(ISNULL(sq.refunds,0)) 'net'
INTO ##rc_trans_2a
FROM ##rc_trans_1a t1a
LEFT JOIN (
	SELECT 
		t1a.person_id, t1a.enc_id, SUM(ISNULL(t1a.adj_amt, 0)*-1) 'refunds'
	FROM ##rc_trans_1a t1a
	WHERE t1a.type = 'R' 
	GROUP BY t1a.person_id, t1a.enc_id
	) sq ON
	t1a.person_id = sq.person_id AND
	t1a.enc_id = sq.enc_id
WHERE t1a.type != 'R'
GROUP BY t1a.person_id, t1a.enc_id
GO


--____________________SECTION: page attribution modeling____________________ 

--> join back to caller_2a and build a union table 
	--> 26,056 @ 00:01
DROP TABLE IF EXISTS ##pv_attr_1a
;WITH
CTE1a AS (
	SELECT
		CAST(c2a.caller_id AS VARCHAR) 'caller_id', c2a.call_date, 
		MAX(ISNULL(ft2a.net,0))-MAX(ISNULL(sq.rel_net_total,0)) 'net_amt',
		'full_credit' AS 'credit_attr'
	FROM ##caller_2a c2a
	LEFT JOIN ##fc_trans_2a ft2a ON
		c2a.person_id = ft2a.person_id AND
		c2a.credit_attr = ft2a.credit_attr
	LEFT JOIN (
			SELECT
				t2a.person_id, SUM(ISNULL(t2a.net,0)) 'rel_net_total'
			FROM ##rc_trans_2a t2a
			GROUP BY t2a.person_id
		) sq ON
		c2a.person_id = sq.person_id
	GROUP BY c2a.caller_id, c2a.credit_attr, c2a.call_date
	),
CTE2a AS (
	SELECT
		CAST(c2a.caller_id AS VARCHAR) 'caller_id', c2a.call_date, c2a.credit_attr,
 		SUM(ISNULL(rt2a.net,0)) 'net_amt'
	FROM ##caller_2a c2a
	LEFT JOIN ##rc_trans_2a rt2a ON
		c2a.person_id = rt2a.person_id AND
		c2a.credit_attr = rt2a.credit_attr AND
		c2a.enc_id = rt2a.enc_id
	WHERE c2a.credit_attr = 'rel_credit'
	GROUP BY c2a.caller_id, c2a.call_date, c2a.credit_attr
	),
CTE3a AS (
	SELECT c1a.caller_id, c1a.call_date, net_amt, c1a.credit_attr FROM CTE1a c1a WHERE c1a.net_amt != 0
		UNION 
	SELECT c2a.caller_id, c2a.call_date, net_amt, c2a.credit_attr FROM CTE2a c2a WHERE c2a.net_amt != 0
	)
SELECT
	pb.*, c3a.net_amt, c3a.credit_attr,
	ROW_NUMBER() OVER(PARTITION BY c3a.caller_id, CAST(c3a.call_date AS DATE) ORDER BY pb.pageview_date ASC) 'rowX2I1'
INTO ##pv_attr_1a
FROM ##pageviews_base pb
LEFT JOIN CTE3a c3a ON
	pb.caller_id = c3a.caller_id AND
	pb.call_date = c3a.call_date
WHERE c3a.net_amt IS NOT NULL



--> create the linear model
	--> 123 @ 00:00
DROP TABLE IF EXISTS AVP_Marketing.dbo.fx_roi_page_urls
SELECT 
	sq2.caller_id, sq2.call_date, 
	CASE
		WHEN PATINDEX('%?%', sq2.page_url) = 0 THEN sq2.page_url
		WHEN PATINDEX('%?%', sq2.page_url) >0 THEN STUFF(sq2.page_url, PATINDEX('%?%', sq2.page_url), LEN(sq2.page_url), '') 
	END AS 'page_url',
	sq2.pageview_date, sq2.net_amt, sq2.credit_attr,
	CAST(sq2.net_amt*perc_attr AS FLOAT) 'url_val'
INTO AVP_Marketing.dbo.fx_roi_page_urls
FROM (
	SELECT 
		sq.*,
		CASE
			WHEN sq.rowX2I1 = 1 THEN .4
			WHEN sq.rowX2I1 = last_page THEN .4
			ELSE ROUND(1./(sq.last_page-2), 3)
		END AS 'perc_attr'
	FROM (
		SELECT
			p1a.*,
			MAX(p1a.rowX2I1) OVER(PARTITION BY p1a.caller_id, p1a.call_date) 'last_page'
		FROM ##pv_attr_1a p1a
		) sq
	) sq2



/*
SELECT 
	c2a.caller_id, c2a.call_date, COUNT(DISTINCT person_id) 'num_pts'
FROM ##caller_2a c2a
WHERE c2a.credit_attr = 'full_credit'
GROUP BY c2a.caller_id, c2a.call_date

SELECT * FROM ##caller_2a WHERE caller_id = '4067881710'

--> group by day, keeping the first daily instance of calls and appointments
	--> 15,094 for same day (strict determination)
DROP TABLE IF EXISTS ##phone_match_grpfilt
SELECT 
	sq2.*, DATEDIFF(MINUTE, sq2.call_date, sq2.appt_create_date) 'tdif'
INTO ##phone_match_grpfilt
FROM (
	SELECT 
		sq1a.*, sq1b.appt_create_date, DATEDIFF(DAY,sq1a.call_date,sq1b.appt_create_date) 'ddif'
	FROM (
		SELECT
			pmb.cr_phone, pmb.person_id, pmb.first_name, pmb.last_name, MIN(pmb.call_date) 'call_date'
		FROM ##phone_match_base pmb
		--WHERE pmb.dDiff >= 0
		GROUP BY pmb.cr_phone, pmb.person_id, pmb.first_name, pmb.last_name, CAST(pmb.call_date AS DATE)
	) sq1a
		LEFT JOIN
		(SELECT 
			pmb.person_id, MIN(pmb.appt_create_date) 'appt_create_date'
		FROM ##phone_match_base pmb
		--WHERE pmb.diff >= 0
		GROUP BY pmb.person_id, CAST(pmb.appt_create_date AS DATE)
		) sq1b ON
			sq1a.person_id = sq1b.person_id
	) sq2
WHERE sq2.ddif = 0
GO
END
