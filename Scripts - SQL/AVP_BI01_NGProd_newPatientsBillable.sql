/*
	AUTHOR: Joshua Harvey
	ORIG DATE: 2020, 6, 10 
	PURPOSE: Count new patients by person and billable new patient charges
	NOTES: 
*/


--> create a charges table for only new_pt cpt codes
	--> 727,650 @ 00:39
DECLARE @newpt_charges_t1 DATETIME;
DECLARE @newpt_charges_t2 DATETIME;
DECLARE @newpt_charges_tt DATETIME;
SET @newpt_charges_t1 = GETDATE();
DROP TABLE IF EXISTS ##newpt_charges
SELECT
	c.practice_id, c.person_id,
	c.charge_id, c.source_id,
	c.service_item_id, c.begin_date_of_service,
	c.location_id
INTO ##newpt_charges
FROM 
	[NGPROD02].NGProd.dbo.charges c
	INNER JOIN (SELECT nnc.Service_item_id FROM AVP_Marketing.dbo.ref_ng_newpt_cpt nnc) sq ON
		c.service_item_id = sq.Service_item_id
WHERE 
	c.begin_date_of_service >= '1/1/2018' AND
	c.person_id IS NOT NULL AND 
	c.link_id IS NULL 
SET @newpt_charges_t2 = GETDATE()
SET @newpt_charges_tt = DATEDIFF(SECOND,@newpt_charges_t1,@newpt_charges_t2)
GO


--> create payments received table
	--> 1,980,846 @ 01:24 (before group)
	--> 626,790 @ 01:20 (after group) 
DROP TABLE IF EXISTS ##newpt_paid
SELECT td.practice_id, td.charge_id, SUM(ISNULL(td.paid_amt,0)*-1) 'paid_amt'
INTO ##newpt_paid
FROM [NGPROD02].NGProd.dbo.trans_detail td
	INNER JOIN (SELECT practice_id, charge_id FROM ##newpt_charges) sq ON
		td.practice_id = sq.practice_id AND
		td.charge_id = sq.charge_id
WHERE td.post_ind = 'Y' AND sq.charge_id IS NOT NULL
GROUP BY td.practice_id, td.charge_id
GO


--> create refunds table
	--> 14,015 @ 00:02
DROP TABLE IF EXISTS ##newpt_refunds
SELECT td.practice_id, td.charge_id, SUM(td.adj_amt) 'refund_amt'
INTO ##newpt_refunds
FROM [NGPROD02].NGProd.dbo.trans_detail td
	INNER JOIN (SELECT practice_id, charge_id FROM ##newpt_charges) sq ON
		td.practice_id = sq.practice_id AND
		td.charge_id = sq.charge_id
	LEFT JOIN [NGPROD02].NGProd.dbo.transactions t ON
		td.trans_id = t.trans_id AND
		td.practice_id = t.practice_id
WHERE t.type = 'R' AND td.post_ind = 'Y'
GROUP BY td.practice_id, td.charge_id
GO


--> join paid and refunds with charges table
	--> 727,650 @ 00:04
DROP TABLE IF EXISTS ##newpt_trans
SELECT nc.*, SUM(ISNULL(np.paid_amt,0)*-1) 'paid', SUM(ISNULL(nr.refund_amt,0)) 'refund'
INTO ##newpt_trans
FROM ##newpt_charges nc
	LEFT JOIN ##newpt_paid np ON 
		nc.practice_id = np.practice_id AND
		nc.charge_id = np.charge_id
	LEFT JOIN ##newpt_refunds nr ON 
		nc.practice_id = nr.practice_id AND
		nc.charge_id = nr.charge_id
GROUP BY nc.practice_id, nc.person_id,
		nc.charge_id, nc.source_id,
		nc.service_item_id, nc.begin_date_of_service,
		nc.location_id
GO


--> make the table dimension friendly (optional step if using pbi or ssas)
	--> 727,650 @ 00:08
DROP TABLE IF EXISTS [AVP_Marketing].dbo.ng_newpt_billable_v2
SELECT 
	sq.practice_id, sq.person_id, sq.charge_id, sq.source_id,
	sq.service_item_id, CAST(sq.begin_date_of_service AS DATE) 'dos',
	sq.location_id, sq.paid, sq.refund, sq.prsn_cnt, sq.prs_inst,
	MAX(sq.cpt_inst) OVER(PARTITION BY sq.person_id) 'uniq_cpt', 
	MAX(sq.chrg_inst) OVER(PARTITION BY sq.person_id) 'uniq_chg', 
	MAX(sq.src_inst) OVER(PARTITION BY sq.person_id) 'uniq_src',
	nlm.[4Wall]
INTO [AVP_Marketing].dbo.ref_ng_newpt_billable_v2
FROM (
	SELECT
		nt.*,
		COUNT(*) OVER(PARTITION BY nt.person_id) 'prsn_cnt',
		DENSE_RANK() OVER(PARTITION BY nt.person_id ORDER BY nt.begin_date_of_service) 'prs_inst',
		DENSE_RANK() OVER(PARTITION BY nt.person_id ORDER BY nt.service_item_id) 'cpt_inst',
		DENSE_RANK() OVER(PARTITION BY nt.person_id ORDER BY nt.charge_id) 'chrg_inst',
		DENSE_RANK() OVER(PARTITION BY nt.person_id ORDER BY nt.source_id) 'src_inst'
	FROM ##newpt_trans nt
	) AS sq
LEFT JOIN [AVP_Marketing].dbo.ref_ng_loc_mstr nlm ON
	sq.location_id = nlm.location_id
GO


--DECLARE @total_query_time DATETIME;
--SET @total_query_time = @newpt_charges_tt + @newpt_paid
--PRINT 'TOTAL TIME =' + @total_query_time


--> create a summary table for the MBR KPI
	--> 19 @ 00:01
DROP TABLE IF EXISTS [AVP_Marketing].dbo.fx_SLT_MBR_newptBillable_KPI
SELECT 
	YEAR(bv2.dos) 'Year',
	MONTH(bv2.dos) 'Month',
	COUNT(bv2.charge_id) 'New Billable'
INTO [AVP_Marketing].dbo.fx_SLT_MBR_newptBillable_KPI
FROM AVP_Marketing.dbo.fx_ng_newpt_billable_v2 bv2
WHERE YEAR(bv2.dos) >= YEAR(GETDATE())-1 AND
bv2.[4Wall] = 'Same Store'
GROUP BY YEAR(bv2.dos), MONTH(bv2.dos)
ORDER BY YEAR(bv2.dos), MONTH(bv2.dos)


--> preview the results
--SELECT * FROM [AVP_Marketing].dbo.SLT_MBR_newpt_KPI slt
--ORDER BY slt.year ASC, slt.month ASC


--> this is the new summary table that uses native marketing loc tables
/*
SELECT 
	YEAR(sq.dos),
	MONTH(sq.dos),
	sq.practice_id,
	sq.location_name,
	sq.same_store,
	COUNT(sq.charge_id) 'all_inst',
	SUM(sq.paid - sq.refund) 'net_rev'
FROM (
	SELECT nnbv.*, nlm.same_store, nlm.location_name
	FROM AVP_Marketing.dbo.ng_newpt_billable_v2 nnbv
	LEFT JOIN AVP_Marketing.dbo.ng_loc_mstr nlm 
		ON nnbv.location_id = nlm.location_id
	) AS sq
GROUP BY YEAR(sq.dos), MONTH(sq.dos), sq.practice_id, sq.location_name, sq.same_store
ORDER BY YEAR(sq.dos) ASC, MONTH(sq.dos) ASC
*/


--> use this query for import into excel or powerbi
/*
SELECT 
	bv2.*,
	DENSE_RANK() OVER(ORDER BY bv2.person_id) 'SK_personid'
FROM [AVP_Marketing].dbo.ng_newpt_billable_v2 bv2
*/

-- LEGACY QUERY
/*
--> create appointments and merge in locations as well as charges
DROP TABLE IF EXISTS ##newpt_apt_merge
SELECT 
	nc.practice_id,
	nc.person_id,
	nc.charge_id,
	nc.source_id,
	a.appt_id,
	nc.service_item_id,
	nc.begin_date_of_service,
	--DENSE_RANK() OVER(PARTITION BY sq1.person_id, a.appt_id ORDER BY sq1.begin_date_of_service) AS rank_apt,
	--ROW_NUMBER() OVER(PARTITION BY sq1.person_id, sq1.charge_id ORDER BY sq1.charge_id) rank_chrg_inst,
	a.location_id,
	a.cancel_ind,
	a.delete_ind
INTO ##newpt_apt_merge
FROM appointments a
	INNER JOIN ##newpt_charges nc
		ON a.enc_id = nc.source_id


SELECT * FROM ##newpt_apt_merge nmp
ORDER BY nmp.begin_date_of_service DESC, nmp.person_id

--> strip out the duplicate charges. same as grouping by all columns
-- iterate the pateints to count instances
-- bring in the trans_detail
DROP TABLE IF EXISTS ##newpt_mold
SELECT 
	sq.practice_id,sq.person_id,sq.service_item_id,sq.charge_id,sq.source_id,
	sq.begin_date_of_service,sq.cancel_ind,
	sq.location_id,
	ROW_NUMBER() OVER(PARTITION BY sq.person_id ORDER BY sq.begin_date_of_service ASC) 'pt_inst',
	CASE
    	WHEN sq.practice_id = 0001 THEN 'SEC'
    	WHEN sq.practice_id = 0020 THEN 'SEC'
		WHEN sq.practice_id = 0011 THEN 'BDP'
    	ELSE Null
    END AS 'brand'
INTO ##newpt_mold
FROM 
(
	SELECT 
		nb.*,
		ROW_NUMBER() OVER(PARTITION BY nb.person_id,nb.charge_id ORDER BY nb.begin_date_of_service ASC) chg_inst
	FROM ##newpt_apt_merge nb
) AS sq
WHERE sq.chg_inst = 1


--> build the new-patient billable by first date of service
DROP TABLE IF EXISTS [AVP_Marketing].dbo.ng_newpt_billable
SELECT 
	sq.practice_id, sq.person_id, sq.service_item_id, sq.charge_id, sq.source_id,
	sq.location_id, sq.cancel_ind,sq.pt_inst,
	MAX(sq.uniq_prac) OVER(PARTITION BY sq.person_id) 'prac_max',
	sq.brand,sq.dos,sq.prior_dos,
	DATEDIFF(DAY, sq.prior_dos, sq.dos) AS 'date_dif'
INTO [AVP_Marketing].dbo.ng_newpt_billable
FROM (
	SELECT nm.*,
		CAST(nm.begin_date_of_service AS DATE) 'dos',
		ISNULL(CAST(nm2.begin_date_of_service AS DATE), '1900-01-01') 'prior_dos',
		DENSE_RANK() OVER(PARTITION BY nm.person_id ORDER BY nm.brand ASC) 'uniq_prac'
	FROM ##newpt_mold nm
	LEFT JOIN ##newpt_mold nm2 
		ON nm.person_id = nm2.person_id AND
		nm.pt_inst = nm2.pt_inst+1
	) AS sq
ORDER BY sq.person_id, sq.begin_date_of_service ASC


--> preview the results
SELECT 
	npb.service_item_id,
	npb.cancel_ind,
	npb.pt_inst,
	npb.prac_max,
	npb.brand,
	npb.dos,
	npb.prior_dos,
	npb.date_dif,
	nlm.alex_loc_name,
	nlm.[4Wall],
	nlm.Clinic_Region,
	nlm.loc_type
FROM [AVP_Marketing].dbo.ng_newpt_billable npb
LEFT JOIN [AVP_Marketing].dbo.ng_loc_mstr nlm
		ON npb.location_id = nlm.location_id


--> This section is building a secondary table for revenue purposes


--> grab refunds
DROP TABLE IF EXISTS ##newpt_refunds
SELECT t.source_id, SUM(t.tran_amt) 'refunds'
INTO ##newpt_refunds
FROM transactions t
	INNER JOIN ##newpt_final nf
		ON t.source_id = nf.source_id
WHERE type = 'R'
GROUP BY t.source_id


--> build the new patient revenue by first date of service
DROP TABLE IF EXISTS [AVP_Marketing].dbo.ng_newpt_rev_firstdate
SELECT 
	nf.practice_id, nf.person_id, nf.service_item_id, 
	nf.location_id, nf.cancel_ind,
	MIN(nf.begin_date_of_service) 'date_service', 
	SUM(ISNULL(td.paid_amt,0)*-1)-MIN(ISNULL(nr.refunds,0)) 'net_total'
INTO [AVP_Marketing].dbo.ng_newpt_rev_firstdate
FROM trans_detail td
	INNER JOIN ##newpt_final nf
		ON td.source_id = nf.source_id
	LEFT JOIN ##newpt_refunds nr
		ON td.source_id = nr.source_id
GROUP BY nf.practice_id, nf.person_id, 
	nf.service_item_id, nf.cancel_ind, nf.location_id


-- END OF QUERY

--> this method was replaced b/c it was harder to read and 
-- more difficult to troubleshoot. it did provide the same outcome as above
DROP TABLE IF EXISTS ##newpt_base
SELECT 
	sq1.practice_id,
	sq1.person_id,
	sq1.charge_id,
	sq1.source_id,
	a.appt_id,
	sq1.service_item_id,
	sq1.begin_date_of_service,
	--DENSE_RANK() OVER(PARTITION BY sq1.person_id, a.appt_id ORDER BY sq1.begin_date_of_service) AS rank_apt,
	ROW_NUMBER() OVER(PARTITION BY sq1.person_id, sq1.charge_id ORDER BY sq1.charge_id) rank_chrg_inst,
	a.location_id,
	a.cancel_ind,
	a.delete_ind,
	nlm.alex_loc_name,
	nlm.[4Wall],
	nlm.loc_type
INTO ##newpt_base
FROM (
	SELECT TOP 1000
		c.practice_id,
		c.person_id,
		c.charge_id,
		c.source_id,
		c.service_item_id,
		c.begin_date_of_service
	--INTO ##NewPtCharges
	FROM 
		ngprod.dbo.charges c
	WHERE 
		c.service_item_id IN (SELECT * FROM [AVP_Marketing].dbo.[nextgen_newpt_cpt]) AND
		c.person_id IS NOT NULL AND 
		c.link_id IS NULL
) sq1
	LEFT JOIN appointments a
		ON sq1.source_id = a.enc_id
	LEFT JOIN [AVP_Marketing].dbo.ng_loc_mstr nlm
		ON a.location_id = nlm.location_id
ORDER BY sq1.person_id, sq1.begin_date_of_service
*/