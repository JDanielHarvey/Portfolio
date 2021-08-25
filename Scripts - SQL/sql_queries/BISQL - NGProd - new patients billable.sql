/*
	AUTHOR: Joshua Daniel Harvey
	ORIG DATE: 2020, 6, 10
	PURPOSE: Count new patients by practice
	NOTES: revision of ...BI01 - NGProd - new patients billable.sql
			[AVP_Marketing].dbo.ng_newpt_billable_v3
	PRE-REQ: AVP_Marketing.ref.ng_internalProviders must be refreshed
*/

--> new patient cpt codes verified by Carrie Clark
	--> ~32 @ ~00:00
drop table if exists #new_pt_cpt
select 
	Service_item_id
into #new_pt_cpt
from (
	values
	('92002'),
	('00000L6'),
	('99223'),
	('99205'),
	('W9999'),
	('99203'),
	('PEXAM'),
	('00000L7'),
	('NC99203'),
	('00000L5'),
	('S0620T'),
	('99254'),
	('PREOPCL'),
	('99202'),
	('92004H'),
	('CONSULTRE'),
	('NC92004'),
	('S0620'),
	('REF79'),
	('S0620S'),
	('W9995'),
	('99204'),
	('NC99201'),
	('99253'),
	('NC92002'),
	('EXAMRX'),
	('00000L9'),
	('99201'),
	('99201C'),
	('99252'),
	('92004'),
	('RRE')
) as sq (Service_item_id)


--___________________________________SEC 1: Bulid base charges tables___________________________________

--> Table 1: create a charges table for only new_pt cpt codes
	--> 283,435 @ 03:00
DROP TABLE IF EXISTS #newpt_charges
SELECT
	c.practice_id, 
	c.person_id,
	c.charge_id, c.source_id,
	c.service_item_id, c.begin_date_of_service,
	c.location_id, c.rendering_id, sim.description,
	c.create_timestamp, referring_id
INTO #newpt_charges
FROM BISQL.NGProd.dbo.charges c with(nolock)
	INNER JOIN #new_pt_cpt nnc with(nolock) ON
		c.service_item_id = nnc.Service_item_id
	LEFT JOIN BISQL.NGProd.dbo.service_item_mstr sim with(nolock) ON
		c.service_item_id = sim.service_item_id AND
		c.service_item_lib_id = sim.service_item_lib_id
WHERE 
	CAST(c.begin_date_of_service AS DATE) >= '1/1/2019' AND
	c.person_id IS NOT NULL AND 
	c.link_id IS NULL AND
	c.begin_date_of_service BETWEEN sim.eff_date AND sim.exp_date AND
	c.practice_id IN (0011,0020,0023,0025)
GO



----> Table 2: create a charges table for only new_pt cpt codes RCA 
--	--> 16,873 @ 00:09
--DROP TABLE IF EXISTS #newpt_charges_rca
--SELECT
--	'0023' as practice_id, 
--	c.person_id,
--	c.charge_id, c.source_id,
--	c.service_item_id, c.begin_date_of_service,
--	c.location_id, c.rendering_id, sim.description,
--	c.create_timestamp, referring_id
--INTO #newpt_charges_rca
--FROM BI01.NGProd_RCA.dbo.charges c with(nolock)
--	INNER JOIN #new_pt_cpt nnc ON
--		c.cpt4_code_id = nnc.Service_item_id
--	LEFT JOIN BI01.NGProd_RCA.dbo.service_item_mstr sim with(nolock) ON
--		c.service_item_id = sim.service_item_id AND
--		c.service_item_lib_id = sim.service_item_lib_id
--WHERE 
--	CAST(c.begin_date_of_service AS DATE) >= '1/1/2019' AND
--	c.person_id IS NOT NULL AND 
--	c.link_id IS NULL AND
--	c.begin_date_of_service BETWEEN sim.eff_date AND sim.exp_date
--GO


--> Table 3: union table 1 and table 2
	--> 300,308 @ 00:01
drop table if exists #newpt_charges1b
select * 
into #newpt_charges1b
from (
	select * from #newpt_charges
	--	union all
	--select * from #newpt_charges_rca
) sq
go


--___________________________________SEC 2: Enrichment and Main Methodology___________________________________

--> Table 4: enrich with referring 
	--> 310,219 @ 00:01
DROP TABLE IF EXISTS #newpt_charges2
SELECT
	nc.*,
	CONCAT(pm.first_name, ' ',pm.last_name) 'full_name', pm.degree, sq.npi, ipm.provider_id,
	CASE 
		WHEN ipm.provider_id IS NOT NULL OR sq.npi IS NOT NULL THEN 'self_referral'
		WHEN ipm.provider_id IS NULL AND sq.npi IS NULL AND pm.provider_id IS NOT NULL THEN 'external_referral'
		ELSE 'self_referral'
	END AS 'refer_type'
INTO #newpt_charges2
FROM #newpt_charges1b nc
LEFT JOIN BISQL.NGProd.dbo.provider_mstr pm with(nolock) ON
	nc.referring_id = pm.provider_id
LEFT JOIN AVP_Marketing.ref.ng_internalProviders ipm ON
	ipm.[in-house_determ] like '%internal' and 
	pm.provider_id = ipm.provider_id
LEFT JOIN (select distinct npi FROM AVP_Marketing.ref.ng_internalProviders where npi is not null and [in-house_determ] like '%internal') sq ON
	pm.national_provider_id = sq.npi
--LEFT JOIN NGPROD02.AVP_Finance.dbo.SharedDimension_InternalProvider_Mstr ipm ON
--	pm.provider_id = ipm.ProviderID
GO



--> Table 5: main methodology - only maintain dupes when 1st inst on diff prac
	--> 263,946 @ 00:02
DROP TABLE IF EXISTS #newpt_keepers
SELECT
	sq2.practice_id,sq2.person_id, sq2.charge_id, sq2.source_id, sq2.service_item_id, sq2.description, sq2.rendering_id,
	CAST(sq2.begin_date_of_service AS DATE) 'dos', sq2.location_id, sq2.create_timestamp 'charge_createDate',
	sq2.full_name, sq2.degree, sq2.refer_type,
	COUNT(*) OVER(PARTITION BY sq2.person_id) 'cnt'
INTO #newpt_keepers
FROM (
	-- SQ2 start
	SELECT 
		sq.*,
		ROW_NUMBER() OVER(PARTITION BY sq.person_id, sq.drank_prac ORDER BY cast(begin_date_of_service as date) asc) 'keepers'
	FROM (
		-- SQ1 start
		SELECT
			nc.*,
			DENSE_RANK() OVER(PARTITION BY nc.person_id ORDER BY nc.practice_id) 'drank_prac',
			DENSE_RANK() OVER(PARTITION BY nc.person_id ORDER BY nc.begin_date_of_service) 'drank_date'
		FROM #newpt_charges2 nc
		) sq
	) sq2
WHERE sq2.keepers = 1
GO


--> Table 6: appointment create
	--> 263946 @ 02:00 (264 get eliminated b/c of missing appt date)
DROP TABLE IF EXISTS ##newpt_keepers2
SELECT
	nk.practice_id, nk.person_id, nk.source_id, nk.service_item_id,
	nk.description, nk.rendering_id, nk.dos, nk.location_id,
	nk.refer_type, nk.full_name 'refer_doc', nk.degree 'refer_degree', nk.cnt, 
	nk.charge_createDate, min(a.create_timestamp) 'appt_create',
	DATEDIFF(DAY, MIN(a.create_timestamp), nk.dos) 'dDiff'
INTO #newpt_keepers2
FROM #newpt_keepers nk
LEFT JOIN NGPROD02.NGProd.dbo.appointments a with(nolock) ON
	nk.practice_id = a.practice_id AND
	nk.person_id = a.person_id AND
	nk.source_id = a.enc_id
GROUP BY 
	nk.practice_id, nk.person_id, nk.source_id, nk.service_item_id,
	nk.description, nk.rendering_id, nk.dos, nk.location_id,
	nk.refer_type, nk.full_name, nk.degree, nk.cnt, nk.charge_createDate
GO


-- Table 7: enrich with locations and brands 
	--> 193,715 @ 00:01
DROP TABLE IF EXISTS #newpt_keepers3 --AVP_Marketing.dbo.fx_ng_newpt_distinct_bypractice
SELECT 
		CASE 
			WHEN nk.practice_id = '0011' THEN 'BDP'
			WHEN lower(nlm.alex_loc_name) like '%m&m%' or lower(nlm.Location_Name) like '%m&m%' THEN 'M&M'
			WHEN nk.practice_id = '0020' THEN 'SEC'
			WHEN nk.practice_id = '0023' THEN 'RCA'
			WHEN nk.practice_id = '0025' THEN 'AEI'
		END AS 'Brand', 
		nk.person_id, nk.service_item_id, nk.description,
		nk.refer_doc, nk.refer_degree, nk.refer_type,
		nk.dDiff, nk.dos, CAST(nk.charge_createDate AS DATE) 'charge_create', 
		nk.cnt, nlm.for_chris 'same_store',
		ISNULL(nlm.alex_loc_name, nlm.Location_Name) 'Location_Name',
		NULL AS 'ContactType',
		nk.location_id
INTO #newpt_keepers3 --INTO [AVP_Marketing].dbo.fx_ng_newpt_distinct_bypractice
FROM #newpt_keepers2 nk
	LEFT JOIN (select * from AVP_Marketing.[ref].[ng_locations]) nlm ON 
		nk.location_id = nlm.location_id
WHERE CAST(nk.charge_createDate AS DATE) >= '2021-07-01'
ORDER BY practice_id, nlm.Location_Name
GO


-- occurs at the end of every month on the 3rd day only
INSERT INTO AVP_Marketing.dbo.fx_ng_newpt_distinct_bypractice (Brand, person_id, service_item_id, description, refer_doc, refer_degree, refer_type, dDiff, dos, charge_create, cnt, same_store, Location_Name, ContactType, location_id, insert_time)
SELECT *, GETDATE() AS 'insert_time'
FROM #newpt_keepers3
WHERE 
	DATEDIFF( DAY, 
		DATEADD(DAY, -DATEPART(DAY, GETDATE()) + 1, CAST(GETDATE() AS DATE) ), 
		GETDATE() 
		) 
		= 3


-- occurs every day
DROP TABLE IF EXISTS [AVP_Marketing].dbo.fx_ng_newpt_distinct_bypractice_curMonth
SELECT *, GETDATE() AS 'insert_time'
INTO [AVP_Marketing].dbo.fx_ng_newpt_distinct_bypractice_curMonth
FROM #newpt_keepers3



--SELECT 
--	--DATEFROMPARTS(YEAR(dos), MONTH(dos), 1), COUNT(*) 'cnt'
--	SUM(
--FROM AVP_Marketing.dbo.fx_ng_newpt_distinct_bypractice
--GROUP BY DATEFROMPARTS(YEAR(dos), MONTH(dos), 1)
--ORDER BY DATEFROMPARTS(YEAR(dos), MONTH(dos), 1) asc




----> Table 8: standardize for prior years and use summary results for reporting 
--	-->
--SELECT sq.*, /*sq2.rev_day_yyyymm, sq2.cur_year_rev_days,*/ (sq.Visits*1.0/sq2.rev_day_yyyymm)*sq2.cur_year_rev_days 'Visits Standardized'
--FROM (
--	SELECT
--		DATEFROMPARTS(YEAR(nd.dos), MONTH(nd.dos), 1) 'DateXMonth',
--		YEAR(nd.dos) 'Year', 
--		MONTH(nd.dos) 'Month', 
--		nd.brand,
		
--		nd.Location_Name 'Location',
--		COUNT(*) 'Visits',
--		nd.refer_type,
--		nd.for_chris 'same_store'
--	FROM #newpt_keepers3 nd --AVP_Marketing.dbo.fx_ng_newpt_distinct_bypractice nd
--	GROUP BY YEAR(nd.dos), MONTH(nd.dos), nd.brand, nd.Location_Name, nd.refer_type, nd.for_chris
--	) sq
--LEFT JOIN ( select * from openquery(BI01, 'exec spAVP_curYearStandardizeRevDays') ) sq2 on
--	sq.Year = sq2.Year and sq.Month = sq2.Month
--ORDER BY sq.Year asc, sq.Month asc
 

/*
LEFT JOIN ( 
	select c1a.Year, c1a.Month, min(c1a.rev_day_yyyymm) 'rev_day_prev_year' from cte1a c1a group by c1a.Year, c1a.Month
	) sq on 
	c1a.Year = sq.Year+1 and
	c1a.Month = sq.Month
*/



--> used to find people same day multiple practices
/*
SELECT 
	DISTINCT sq3.*
FROM (
	SELECT 
		sq2.*,
		sq2.drank_date_max-sq2.drank_prac_max 'diff'
	FROM (
		SELECT 
			sq.*,
			MAX(sq.drank_prac) OVER(PARTITION BY sq.person_id) 'drank_prac_max',
			MAX(sq.drank_date) OVER(PARTITION BY sq.person_id) 'drank_date_max'
		FROM (
			SELECT TOP 5000
				nc.*,
				DENSE_RANK() OVER(PARTITION BY nc.person_id ORDER BY nc.practice_id) 'drank_prac',
				DENSE_RANK() OVER(PARTITION BY nc.person_id ORDER BY nc.begin_date_of_service) 'drank_date'
			FROM ##newpt_charges nc
			) sq
		) sq2
	WHERE sq2.drank_prac_max > 1
	) sq3
WHERE sq3.diff < 0
ORDER BY sq3.begin_date_of_service ASC, sq3.person_id
*/