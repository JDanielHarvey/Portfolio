/*
	AUTHOR: Joshua Harvey
	ORIG DATE: 2020, 06, 16
	PURPOSE: measure the kept and unkept apointments booked by the call center
	NOTES: this should not be used to measure individual agents productivity 
	METHODOLOGY: 
		1) maintain mult kept appts on a single day
		2) eliminate unkept appts on a day with a kept
		3) eliminte multiple unkept appts on a single day to accurately count unkept when unkept was the only outcome
		on a single day
*/


--> set the call center user base table. this will be used to create a master ref_table
	--> 192 @ 00:01
DROP TABLE IF EXISTS #user_base
SELECT DISTINCT
	sq.user_id,
	TRIM(sq.first_name) 'first_name',
	TRIM(REPLACE(REPLACE(sq.last_name, 'CTH-',''), 'TEMP-', '')) 'last_name',
	CASE
		WHEN PATINDEX('%CTH-%', sq.last_name) > 0 THEN 'CTH'
		WHEN PATINDEX('%TEMP-%', sq.last_name) > 0 THEN 'TEMP'
		ELSE 'FTE'
	END AS 'employee_type',
	sq.last_logon, sq.group_name, sq.group_id, 
	CAST(sq.create_timestamp AS DATE) 'create_date'
INTO #user_base
FROM (
	SELECT 
		um.last_name, um.first_name, um.[start_date],
		TRY_CAST(um.last_logon_date AS DATE) 'last_logon', um.delete_ind,
		xr.[user_id],
		sg.group_id, sg.group_name, sg.[description], um.create_timestamp,
		ROW_NUMBER() OVER(PARTITION BY um.user_id ORDER BY last_logon_date DESC) 'rowXuser|login'
	FROM [NGProd02].NGProd.dbo.security_groups sg
		INNER JOIN [NGProd02].NGProd.dbo.user_group_xref xr
			ON sg.group_id = xr.group_id
		INNER JOIN [NGProd02].NGProd.dbo.user_mstr um 
			ON xr.[user_id] = um.[user_id]
	WHERE (um.user_id in (5037,5057) or LOWER(sg.group_name) LIKE '%call%center%') and um.user_id != 2523
	) sq
WHERE sq.[rowXuser|login] = 1
GO


--> create the base table for BDP/SEC appts only events the cc schedules for
	--> 255,842 @ 00:38 (without event constraint 272,949)
DECLARE @today AS DATE = CAST(GETDATE() AS DATE)
DROP TABLE IF EXISTS ##cc_prod1a
SELECT 
	sq.*
INTO ##cc_prod1a
FROM (
	SELECT
		uc.[user_id],
		CAST(a.appt_date AS DATE) 'appt_date',
		a.create_timestamp, a.person_id, a.enc_id,
		a.appt_kept_ind, a.location_id, 
		CASE 
			WHEN a.practice_id = 0011 THEN 'BDP'
			WHEN a.practice_id = 0020 THEN 'SEC'
			WHEN a.practice_id = 0023 THEN 'RCA'
		END AS 'practice_id',
		e.[event], 
		CASE
			WHEN a.appt_date >= @today THEN 'expected'
			WHEN a.appt_date <= @today AND a.appt_kept_ind = 'N' THEN 'unkept'
			WHEN a.appt_kept_ind = 'Y' THEN 'kept'
		END AS 'true_kept'
	FROM NGPROD02.[NGProd].dbo.appointments a
		INNER JOIN #user_base uc
			ON a.created_by = uc.[user_id]
		LEFT JOIN NGPROD02.NGProd.dbo.[events] e 
			ON a.event_id = e.event_id
	WHERE 
		a.practice_id IN(0011, 0020, 0023) AND
		CAST(a.create_timestamp AS DATE) >= '1/1/2019' AND 
		person_id IS NOT NULL AND 
		a.delete_ind = 'N'
	) AS sq
	--INNER JOIN AVP_Marketing.dbo.ref_ng_events_callcenter ec ON
			--sq.[event] = ec.[event]
GO


--> create the base table for RCA appts 
	--> 12,216 @ 00:01
DECLARE @today AS DATE = CAST(GETDATE() AS DATE)
DROP TABLE IF EXISTS ##cc_prod1b
SELECT 
	sq.*
INTO ##cc_prod1b
FROM (
	SELECT
		a.created_by 'user_id',
		CAST(a.appt_date AS DATE) 'appt_date',
		a.create_timestamp, a.person_id, a.enc_id,
		a.appt_kept_ind, a.location_id, 'RCA' AS practice_id,
		e.[event], 
		CASE
			WHEN a.appt_date >= @today THEN 'expected'
			WHEN a.appt_date <= @today AND a.appt_kept_ind = 'N' THEN 'unkept'
			WHEN a.appt_kept_ind = 'Y' THEN 'kept'
		END AS 'true_kept'
	FROM NGPROD02.NGProd_RCA.dbo.appointments a
		LEFT JOIN NGPROD02.NGProd_RCA.dbo.[events] e 
			ON a.event_id = e.event_id
	WHERE 
		a.created_by IN (776, 778, 777, 724, 569, 633) 
		AND CAST(a.appt_date AS DATE) >= '6/19/2020' 
		AND a.person_id IS NOT NULL AND a.delete_ind = 'N'
	) AS sq
GO


--> union the BDP/SEC and RCA 
	--> 291,273
DROP TABLE IF EXISTS ##cc_prod1c
SELECT
	sq.*
INTO ##cc_prod1c
FROM (
	SELECT * FROM ##cc_prod1a
		UNION
	SELECT * FROM ##cc_prod1b
) sq
GO

--____________________SECTION: FILTERING____________________
--> handles the kept daily occurances, maintaining mult inst of kept on a day
	-- discarding the unkept when there is also a kept (1076)
	--> 200,631 @ 00:02
DROP TABLE IF EXISTS ##cc_prod2a
SELECT 
	sq2.*
INTO ##cc_prod2a
FROM (
	SELECT
		sq.*,
		DENSE_RANK() OVER(PARTITION BY sq.person_id, sq.appt_date ORDER BY appt_kept_ind DESC) 'drnkXpers&apt\kept'
	FROM (
		SELECT 
			c1c.*,
			MAX(c1c.appt_kept_ind) OVER(PARTITION BY c1c.person_id, c1c.appt_date) 'maxXper&apt'
		FROM ##cc_prod1c c1c
		WHERE c1c.true_kept != 'expected'
		) AS sq
	WHERE sq.[maxXper&apt] = 'Y'
	) sq2
WHERE sq2.[drnkXpers&apt\kept] = 1
GO


--> handles the unkept daily occurances, eliminating mult inst of unkept on a day
	--> 104,128 @ 00:02
DROP TABLE IF EXISTS ##cc_prod2b
SELECT 
	sq2.*
INTO ##cc_prod2b
FROM (
	SELECT
		sq.*,
		ROW_NUMBER() OVER(PARTITION BY sq.person_id, sq.appt_date ORDER BY sq.create_timestamp ASC) 'rowXpers&apt\cre8'
	FROM (
		SELECT 
			c1c.*,
			MAX(c1c.appt_kept_ind) OVER(PARTITION BY c1c.person_id, c1c.appt_date) 'maxXper&apt'
		FROM ##cc_prod1c c1c
		WHERE c1c.true_kept != 'expected'
		) AS sq
	WHERE sq.[maxXper&apt] = 'N'
	) sq2
WHERE sq2.[rowXpers&apt\cre8] = 1
GO


--> union the tables together
	--> 289,975 @ 00:02
DROP TABLE IF EXISTS ##cc_prod3a
SELECT 
	sq.*
INTO ##cc_prod3a
FROM (
	SELECT
		c2a.user_id, c2a.appt_date, c2a.create_timestamp, c2a.person_id, c2a.enc_id, 
		c2a.appt_kept_ind, c2a.event, c2a.location_id, c2a.practice_id, c2a.true_kept
	FROM ##cc_prod2a c2a
		UNION
	SELECT
		c2b.user_id, c2b.appt_date, c2b.create_timestamp, c2b.person_id, c2b.enc_id, 
		c2b.appt_kept_ind, c2b.event, c2b.location_id, c2b.practice_id, c2b.true_kept
	FROM ##cc_prod2b c2b
		UNION
	SELECT
		c1a.user_id, c1a.appt_date, c1a.create_timestamp, c1a.person_id, c1a.enc_id, 
		c1a.appt_kept_ind, c1a.event, c1a.location_id, c1a.practice_id, c1a.true_kept
	FROM ##cc_prod1a c1a WHERE c1a.true_kept = 'expected'
	) sq
GO


--____________________SECTION: TRANSACTIONS____________________
--> handles the transactions for kept appointments 
	--> 896,200 @ 01:26
DROP TABLE IF EXISTS #cc_prod4a
SELECT
	c3a.person_id, td.trans_id, c3a.enc_id, td.paid_amt, td.adj_amt, t.type
INTO #cc_prod4a
FROM NGPROD02.NGProd.dbo.trans_detail td
	INNER JOIN ##cc_prod3a c3a ON 
		td.source_id = c3a.enc_id
	LEFT JOIN NGPROD02.NGProd.dbo.transactions t ON
		td.trans_id = t.trans_id
	LEFT JOIN NGPROD02.NGProd.dbo.charges c ON
		td.charge_id = c.charge_id
WHERE c3a.practice_id IN ('BDP', 'SEC') AND c.link_id IS NULL AND t.post_ind = 'Y'
GO

--> 7,754 @ 00:01
DROP TABLE IF EXISTS #cc_prod4b
SELECT
	c4a.person_id, c4a.trans_id, SUM(ISNULL(c4a.adj_amt,0)*-1) 'refunds'
INTO #cc_prod4b
FROM #cc_prod4a c4a
WHERE c4a.type = 'R'
GROUP BY c4a.person_id, c4a.trans_id
GO

--> 547,035 @ 00:01
DROP TABLE IF EXISTS #cc_prod4c
SELECT
	c4a.person_id, c4a.enc_id, c4a.trans_id, SUM(ISNULL(c4a.paid_amt,0)*-1) 'received'
INTO #cc_prod4c
FROM #cc_prod4a c4a
GROUP BY c4a.person_id, c4a.enc_id, c4a.trans_id
GO

--> 126,295 @ 00:01
DROP TABLE IF EXISTS #cc_prod5a
SELECT 
	c4c.person_id, c4c.enc_id, SUM(c4c.received) 'received', 
	SUM(ISNULL(c4b.refunds, 0)) 'refunds'
INTO #cc_prod5a
FROM #cc_prod4c c4c
	LEFT JOIN #cc_prod4b c4b ON
		c4c.trans_id = c4b.trans_id
GROUP BY c4c.person_id, c4c.enc_id
GO


--____________________SECTION: RESULTS____________________
--> enrich the table with dimensions
	--> 346,831 @ 00:02
DROP TABLE IF EXISTS ##cc_prod6a
SELECT
	c3a.practice_id 'Brand',
	c3a.user_id, c3a.appt_date, c3a.create_timestamp, c3a.appt_kept_ind, c3a.true_kept, c3a.event,
	ROUND(ISNULL(c5a.received,0) / COUNT(*) OVER(PARTITION BY c3a.person_id, c3a.enc_id),2) 'received',
	ROUND(ISNULL(c5a.refunds,0) / COUNT(*) OVER(PARTITION BY c3a.person_id, c3a.enc_id),2) 'refunds',
	ISNULL(lm.alex_loc_name, lm.Location_Name) 'clinic', lm.same_store
INTO ##cc_prod6a
FROM ##cc_prod3a c3a
	LEFT JOIN #cc_prod5a c5a ON 
		c3a.person_id = c5a.person_id AND
		c3a.enc_id = c5a.enc_id
	LEFT JOIN AVP_Marketing.dbo.ref_ng_loc_mstr lm ON
		c3a.location_id = lm.location_id
GO


--____________________SECTION: Call Center Agents____________________

--> create a daily grain table for agent presence 
	--> 20757 @ 00:01
DROP TABLE IF EXISTS ##cc_prod7a
;WITH
CTE1a AS (
	SELECT
		CAST(c6a.create_timestamp AS DATE) 'dDate',
		c6a.[user_id],
		MIN(c6a.create_timestamp) 'first_daily_appt',
		MAX(c6a.create_timestamp) 'last_daily_appt',
		COUNT(*) 'cnt'
	FROM ##cc_prod6a c6a
	GROUP BY CAST(c6a.create_timestamp AS DATE), c6a.[user_id]
	),
CTE2a AS (
	SELECT
		c1a.*,
		CAST(DATEDIFF(HOUR, c1a.first_daily_appt, c1a.last_daily_appt) AS FLOAT) 'logged_time'
	FROM CTE1a c1a
	),
CTE3a AS (
	SELECT
		c2a.dDate, c2a.user_id, uc.first_name, uc.last_name,
		FORMAT(CAST(c2a.first_daily_appt AS DATETIME), 'hh:mm tt') 'first_time', 
		FORMAT(CAST(c2a.last_daily_appt AS DATETIME), 'hh:mm tt') 'last_time',
		c2a.cnt, c2a.logged_time,
		CASE 
			WHEN c2a.logged_time >= 7 THEN 1 
			WHEN c2a.logged_time < 7 THEN ROUND(c2a.logged_time/6.62, 3)
		END AS 'percent_agent',
		1 as 'full_person'
	FROM CTE2a c2a
		LEFT JOIN #user_base uc ON
			c2a.user_id = uc.user_id
	)
SELECT * 
INTO ##cc_prod7a
FROM CTE3a c3a
GO


--> create a ref table for active agents per month
	--> 1304 @ 00:01
DROP TABLE IF EXISTS AVP_CallCenter.dbo.fx_active_monthly_agents
;WITH 
CTE1a AS (
	SELECT
		YEAR(c7a.dDate) 'dYear',
		MONTH(c7a.dDate) 'dMonth',
		c7a.[user_id],
		SUM(c7a.cnt) 'cnt',
		SUM(c7a.logged_time) 'logged_time',
		SUM(c7a.percent_agent) 'full_days'
	FROM ##cc_prod7a c7a
	GROUP BY YEAR(c7a.dDate), MONTH(c7a.dDate), c7a.[user_id]
	),
CTE2a AS (
	SELECT 
		c1a.*, 
		ROUND(CAST(c1a.cnt AS FLOAT)/CAST(SUM(c1a.cnt) OVER(PARTITION BY dYear, dMonth) AS FLOAT), 3)*100 'relt_total',
		SUM(c1a.cnt) OVER(PARTITION BY dYear, dMonth) 'total_month'
	FROM CTE1a c1a
	),
CTE2b AS (
	SELECT 
		c2a.*,
		ROUND(AVG(relt_total) OVER(PARTITION BY c2a.dYear, c2a.dMonth), 3) 'avg_YnM',
		ROUND(STDEV(relt_total) OVER(PARTITION BY c2a.dYear, c2a.dMonth), 3) 'stdev_YnM'
	FROM CTE2a c2a
	),
CTE2c AS (
	SELECT 
		c2b.*,
		ROUND(c2b.relt_total - c2b.avg_YnM, 3) 'dist_from_mean',
		ROUND((c2b.relt_total - c2b.avg_YnM)/c2b.stdev_YnM, 3) 'num_stdevs'
	FROM CTE2b c2b
),
CTE3a AS (
	SELECT 
		c6a.user_id, 
		MIN(CAST(c6a.create_timestamp AS DATE)) 'first_booking', 
		MAX(CAST(c6a.create_timestamp AS DATE)) 'latest_booking'
	FROM ##cc_prod6a c6a
	GROUP BY c6a.user_id
),
CTE4a AS (
	SELECT
		CAST(CONCAT(c2c.dYear, '-', c2c.dMonth, '-',1) AS DATE) 'dDate',
		c2c.cnt, c2c.user_id, c2c.logged_time, c2c.full_days,
		c3a.first_booking, c3a.latest_booking,
		DATEDIFF(YEAR, c3a.first_booking, CAST(CONCAT(c2c.dYear, '-', c2c.dMonth, '-',1) AS DATE)) 'years_as_agent',
		DATEDIFF(DAY, c3a.first_booking, CAST(CONCAT(c2c.dYear, '-', c2c.dMonth, '-',1) AS DATE)) 'days_as_agent',
		CASE 
			WHEN c2c.num_stdevs < -1 THEN '1_low_activity'
			WHEN c2c.num_stdevs > 1  THEN '3_high_activity'
			ELSE '2_normal_activity'
		END AS 'activity_categ'
	FROM CTE2c c2c
		LEFT JOIN CTE3a c3a ON
			c2c.user_id = c3a.user_id
		)
SELECT
	c4a.*,
	CASE 
		WHEN c4a.days_as_agent > 365 THEN '3_seasoned'
		WHEN c4a.days_as_agent >= 180 THEN '2_regular'
		WHEN c4a.days_as_agent < 180 THEN '1_newbie'
	END AS 'agent_exper',
	CONCAT(uc.first_name, ' ', uc.last_name) 'agent_name'
INTO AVP_CallCenter.dbo.fx_active_monthly_agents
FROM CTE4a c4a
	LEFT JOIN #user_base uc ON
		c4a.user_id = uc.user_id
GO



--> create the call center user referrence table
	--> 1325 @ 00:00
DROP TABLE IF EXISTS AVP_CallCenter.dbo.ref_ng_user_callcenter
SELECT 
	ub.*, 
	TRIM(LOWER(CONCAT(ub.first_name, ' ', ub.last_name))) 'full_name',
	sq.years_as_agent, sq.days_as_agent,
	sq.first_booking, sq.latest_booking, ISNULL(sq.total_appts, 0) 'total_appts'
INTO AVP_CallCenter.dbo.ref_ng_user_callcenter
FROM #user_base ub
	LEFT JOIN (
		SELECT 
			ama.user_id,
			ama.years_as_agent, ama.days_as_agent,
			ama.first_booking, ama.latest_booking,
			SUM(ama.cnt) 'total_appts'
		FROM AVP_CallCenter.dbo.fx_active_monthly_agents ama
		GROUP BY 
			ama.user_id, ama.years_as_agent, ama.days_as_agent,
			ama.first_booking, ama.latest_booking
			) sq ON 
	ub.[user_id] = sq.[user_id]
GO


--__________________SECTION: Google Sheets__________________

--> volume by agent with agent count (light weight grain for Google Sheets)
SELECT ama.*, rrd.num_of_days, ROUND(ama.logged_time/(rrd.num_of_days*6.62),3) 'presence_in_month'
FROM AVP_CallCenter.dbo.fx_active_monthly_agents ama
	LEFT JOIN AVP_CallCenter.dbo.ref_revenue_days rrd ON
		ama.dDate = rrd.first_of_month
WHERE ama.dDate > '2020-09-30'
--WHERE ama.user_id NOT IN (724,569,633)


--> quick hack to get brands for each agent
SELECT DISTINCT 
	CAST(CONCAT(YEAR(create_timestamp), '-', MONTH(create_timestamp), '-',1) AS DATE) 'dDate',
	 user_id, Brand 
FROM ##cc_prod6a
--WHERE user_id NOT IN (724, 569, 633)
ORDER BY dDate ASC, user_id, Brand



--> volume and revenue by brand, location (light weight grain for Google Sheets)
SELECT
	YEAR(create_timestamp) 'dYear',
	MONTH(create_timestamp) 'dMonth',
	CAST(CONCAT(YEAR(create_timestamp), '-', MONTH(create_timestamp), '-',1) AS DATE) 'dDate',
	c6a.Brand,
	c6a.clinic,
	c6a.same_store,
	c6a.true_kept,
	CAST(SUM(c6a.received + c6a.refunds) AS FLOAT) 'net',
	COUNT(*) 'cnt_appts'
FROM ##cc_prod6a c6a
--WHERE user_id NOT IN (724, 569, 633)
GROUP BY 
	YEAR(create_timestamp), MONTH(create_timestamp), c6a.Brand, 
	c6a.clinic, c6a.same_store, c6a.true_kept


	select top 100 * 
	from ##cc_prod6a

--> appointments for kept encounters with insurances
;with
cte1a as (
	select 
		p3a.*, pm.payer_name, case when cob1_payer_id is null then '_no_insurance' else pm.payer_name end as 'insur', lm.location_name
	from ##cc_prod3a p3a
	left join ngprod02.ngprod.dbo.patient_encounter pe on
		p3a.enc_id = pe.enc_id 
	left join ngprod02.ngprod.dbo.payer_mstr pm on
		pe.cob1_payer_id = pm.payer_id
	left join ngprod02.ngprod.dbo.location_mstr lm on
		p3a.location_id = lm.location_id
	where p3a.practice_id in ('BDP', 'SEC') and p3a.enc_id is not null
	)
select
	appt_date, practice_id, payer_name, count(*)
from cte1a
group by appt_date, payer_name, practice_id
order by appt_date asc


--	select 
--		datefromparts(datepart(year,appt_date), datepart(month,appt_date), 1) 'dDate',
--		datepart(year,appt_date) 'year',
--		datepart(month,appt_date) 'month',
--		Brand, same_store, clinic, event, count(*) 'appts'
--	from ##cc_prod6a
--	where 
--		true_kept != 'unkept' and 
--		datepart(year,appt_date) > 2018
--	group by 
--		datefromparts(datepart(year,appt_date), datepart(month,appt_date), 1), 
--		datepart(year,appt_date), datepart(month,appt_date), 
--		Brand, same_store, clinic, event
--	order by dDate asc