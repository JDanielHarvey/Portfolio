USE NGProd
GO

--> build the ##roi_tran table
DROP TABLE IF EXISTS ##roi_tran;
SELECT
	CAST(t.tran_date AS DATE) 'tran_date',
	t.person_id,
	SUM(td.paid_amt) 'paid_amt'
INTO ##roi_tran
FROM transactions t
LEFT JOIN trans_detail td ON 
	t.trans_id = td.trans_id
WHERE CAST(t.tran_date AS DATE) >= '2018-10-15'
GROUP BY t.tran_date, t.person_id
ORDER BY t.person_id;
GO



--> build the ##roi_match table
--> join the marketing roi table with call_date to conduct the analysis
DROP TABLE IF EXISTS ##roi_match;
SELECT 
	rpd.first_call_date,
	rt.*
INTO ##roi_match
FROM ##roi_tran rt
	INNER JOIN AVP_Marketing.dbo.roi_paidmedia_digital rpd ON
	rt.person_id = rpd.person_id



--> build the ##roi_exclude table
--> exclude trans from before [first_call_date], maintains included vals
SELECT 
	person_id,
	SUM(paid_amt)*-1 'paid_amt'
INTO ##roi_exclude
FROM (
	SELECT 
		DATEDIFF(DAY, rm.first_call_date, rm.tran_date) 'diff',
		rm.first_call_date,
		rm.tran_date,
		rm.person_id,
		rm.paid_amt
	FROM ##roi_match rm
	WHERE DATEDIFF(DAY, rm.first_call_date, rm.tran_date) >= 0
) AS sq1
GROUP BY person_id
ORDER BY person_id ASC;
GO



--# builds refunds table to eliminate trans before call date and 
--# joins in the refunds to later be joined to the final ROI table
DROP TABLE IF EXISTS ##ref_tran
SELECT 
	tabe.person_id,
	tabe.source_id,
	tabe.tran_date,
	tabe.first_call_date,
	DATEDIFF(DAY,tabe.first_call_date,CAST(tabe.tran_date AS DATE)) AS 'diff',
	t2.tran_amt 'refunds'
INTO ##ref_tran
FROM (
	--# builds the prelim tran table for Marketing callers only
	--# before eliminating trans before first call date
	SELECT
		t.person_id,
		t.source_id,
		CAST(t.tran_date AS DATE) 'tran_date',
		MIN(rpd.first_call_date) 'first_call_date'
	FROM transactions t
	INNER JOIN AVP_Marketing.dbo.roi_paidmedia_digital rpd ON
		t.person_id = rpd.person_id
	WHERE t.person_id IS NOT NULL AND CAST(t.tran_date AS DATE) >= '2018-10-15'
	GROUP BY CAST(t.tran_date AS DATE), t.person_id, t.source_id
) AS tabe
	LEFT JOIN transactions t2 ON 
	tabe.source_id = t2.source_id
WHERE 
	t2.type = 'R' AND 
	DATEDIFF(DAY,tabe.first_call_date,CAST(tabe.tran_date AS DATE)) >=0
ORDER BY tabe.person_id, tabe.tran_date ASC



--> reconstruct the roi_paidmedia_digital table
DROP TABLE IF EXISTS ##roi_final
SELECT 
	sq.caller_id,
	sq.first_call_date,
	sq.fst_apt,
	sq.lst_apt,
	sq.person_id,
	sq.clt_amt,
	sq.paid_amt,
	sq.refunds,
	(sq.paid_amt - sq.refunds) 'net_rev',
	--ISNULL((sq.paid_amt - sq.refunds),sq.paid_amt) 'net_rev',
	--ISNULL((sq.paid_amt - sq.refunds),sq.paid_amt)/NULLIF(sq.clt_amt,0) 'net % of clt', 
	sq.modality,
	sq.accredited
INTO ##roi_final
FROM (
	SELECT 
		rpd.caller_id,
		rpd.first_call_date,
		rpd.fst_apt,
		rpd.lst_apt,
		rpd.person_id,
		rpd.clt_amt,
		ISNULL(tpex.paid_amt,0) 'paid_amt',
		SUM(ISNULL(tprf.refunds,0)) 'refunds',
		--(tpex.paid_amt - SUM(tprf.refunds)) 'net_rev',
		rpd.modality,
		rpd.accredited
	FROM AVP_Marketing.dbo.roi_paidmedia_digital rpd
		LEFT JOIN ##roi_exclude tpex ON 
		rpd.person_id = tpex.person_id
		LEFT JOIN ##ref_tran tprf ON
		rpd.person_id = tprf.person_id
	GROUP BY rpd.caller_id,
		rpd.first_call_date,
		rpd.fst_apt,
		rpd.lst_apt,
		rpd.person_id,
		rpd.clt_amt,
		tpex.paid_amt,
		rpd.modality,
		rpd.accredited
	) AS sq

/*
SELECT 
	rfi.modality,
	SUM(rfi.paid_amt) 'collected',
	SUM(rfi.refunds) 'refunds'
FROM ##roi_final rfi
WHERE 
	rfi.first_call_date > '2019-02-01' AND
	rfi.first_call_date < '2019-08-01'
GROUP BY rfi.modality
ORDER BY SUM(rfi.refunds) DESC;
GO


-- date.range = {2019,2,1 : 2019,8,1}
-- spend is $189,732 = (119,981+69,751)
-- rev on all is $552,353.56 - 2.91x ROI
-- rev on new_pts is $233,989.19 - 1.23x ROI
-- rev on est_pts is $318,364.37 - 1.67x ROI
-- refunds on all is $67,557.45
-- 552,732 - 67,557 = $485,175 ~ 2.55x ROI