/*
	AUTHOR: Joshua Harvey
	ORIG_DATE: 2020, 7, 11
	PURPOSE: Build a master persons table
	NOTES: 
*/


--> build the persons table from the vital_signs_
	--> chooses the most recent vitals on record
	--> 22404 @ 00:07
DROP TABLE IF EXISTS ##diag_persons
SELECT 
	sq2.person_id, sq2.sex, 
	sq2.height_cm, sq2.weight_kg, sq2.age_at_dos/365 'age',
	sq2.ethnicity, sq2. marital_status, 
	sq2.zip,
	sq2.bp_determ, sq2.bmi_determ
INTO ##diag_persons
FROM (
	SELECT 
		sq.person_id, sq.pulse_rate, sq.BMI_calc, sq.bp_systolic, sq.bp_diastolic,
		CASE 
			WHEN sq.bp_systolic < 120 AND sq.bp_diastolic < 80 THEN 'normal'
			WHEN sq.bp_systolic <= 129 AND sq.bp_diastolic < 80 THEN 'elevated'
			WHEN sq.bp_systolic <= 139 OR (sq.bp_diastolic >= 80 AND sq.bp_diastolic <=89) THEN 'high bp stage 1'
			WHEN sq.bp_systolic <= 180 OR sq.bp_diastolic > 90 THEN 'high bp stage 2'
			WHEN sq.bp_systolic > 180 AND sq.bp_diastolic > 120 THEN 'high bp stage 3'
			ELSE 'undeclared'
		END AS 'bp_determ',
		CASE
			WHEN sq.BMI_calc < 18.5 THEN 'underweight'
			WHEN sq.BMI_calc >= 18.5 AND sq.BMI_calc <=24.9 THEN 'normal'
			WHEN sq.BMI_calc >= 25 AND sq.BMI_calc <= 29.9 THEN 'overweight'
			WHEN sq.BMI_calc >= 30 AND sq.BMI_calc <= 40 THEN 'obese type 1'
			WHEN sq.BMI_calc >= 40.1 AND sq.BMI_calc <= 50 THEN 'obese type 2 morbid'
			WHEN sq.BMI_calc >= 51 THEN 'obese type 2 super'
		END AS 'bmi_determ',
		sq.height_cm, sq.weight_kg, CAST(sq.create_timestamp AS DATE) 'date',
		P.sex, P.marital_status, P.ethnicity, P.date_of_birth, P.zip,
		datediff(DAY,P.date_of_birth, CAST(sq.create_timestamp AS DATE)) 'age_at_dos'
	FROM (
		SELECT
			vs.person_id, vs.enc_id, vs.create_timestamp, vs.pulse_rate,
			vs.BMI_calc, vs.bp_diastolic, vs.bp_systolic, vs.height_cm, vs.weight_kg,
			ROW_NUMBER() OVER(PARTITION BY vs.person_id ORDER BY vs.create_timestamp DESC) 'xrow_date'
		FROM NGPROD02.NGProd.dbo.vital_signs_ vs
		WHERE vs.person_id IS NOT NULL AND vs.height_cm IS NOT NULL AND vs.weight_kg IS NOT NULL AND vs.create_timestamp >= '1/1/2020'
		) sq
	LEFT JOIN NGPROD02.NGProd.dbo.person p ON
		sq.person_id = p.person_id
	WHERE sq.xrow_date = 1
	) sq2
GO


--> build the surgery attributes table
	--> 508,226 @ 00:20 (ljoin appointments)
DROP TABLE IF EXISTS ##persons_attr_surgeries
SELECT 
	sq2.person_id,
	MIN(sq2.appt_date) 'first_surg_dos',
	MAX(sq2.appt_date) 'last_surg_dos',
	sq2.cnt_tot,
	MAX(sq2.xrnk) 'tot_uniq_surgEvents'
INTO ##persons_attr_surgeries
FROM (
	SELECT 
		sq.person_id,
		sq.appt_date, sq.appt_kept_ind, sq.event,
		DENSE_RANK() OVER(PARTITION BY sq.person_id ORDER BY sq.event) 'xrnk',
		COUNT(*) OVER(PARTITION BY sq.person_id) 'cnt_tot'
	FROM (
		SELECT
			dp.person_id,
			a.enc_id,
			a.event_id,
			a.appt_kept_ind,
			a.appt_date,
			e.event
		FROM ##diag_persons dp
			LEFT JOIN NGPROD02.NGProd.dbo.appointments a ON
				dp.person_id = a.person_id
			LEFT JOIN NGPROD02.NGProd.dbo.events e ON
				a.event_id = e.event_id
		WHERE e.event LIKE '%*%'
		) sq
	WHERE sq.appt_kept_ind = 'Y'
	) sq2
GROUP BY sq2.person_id, sq2.cnt_tot
GO


--> build the general appointments attributes table
	--> locations was omitted to be conducted in a separate query
DROP TABLE IF EXISTS ##persons_attr
SELECT 
	sq3.person_id, 
	MIN(sq3.create_date) 'first_create',
	MIN(sq3.appt_date) 'first_appt',
	MAX(sq3.appt_date) 'last_appt',
	sq3.tot_pracs,
	sq3.tot_kept_appts,
	MAX(sq3.canc_ind) 'max_canc',
	MAX(sq3.nosho_ind) 'max_nosho',
	MAX(sq3.conf_ind) 'max_conf'
INTO ##persons_attr
FROM (
	SELECT 
		sq2.person_id, sq2.create_date, sq2.appt_date,
		sq2.canc_ind, sq2.nosho_ind, sq2.conf_ind,
		MAX(sq2.rnx_pracs) OVER(PARTITION BY sq2.person_id) 'tot_pracs',
		MAX(sq2.cnt_kept) OVER(PARTITION BY sq2.person_id) 'tot_kept_appts'
	FROM (
		SELECT 
			sq.person_id, sq.create_date,
			sq.appt_date, sq.cancel_ind, sq.intrf_no_show_ind, sq.confirm_ind,
			DENSE_RANK() OVER(PARTITION BY sq.person_id ORDER BY sq.practice_id) 'rnx_pracs',
			CASE WHEN sq.cancel_ind = 'N' THEN 1 ELSE 2 END AS 'canc_ind',
			CASE WHEN sq.intrf_no_show_ind = 'N' THEN 1 ELSE 2 END AS 'nosho_ind',
			CASE WHEN sq.confirm_ind = 'N' THEN 1 ELSE 2  END AS 'conf_ind',
			CASE 
				WHEN sq.appt_kept_ind = 'Y' THEN COUNT(*) OVER(PARTITION BY sq.person_id)
			END AS 'cnt_kept'
		FROM (
			SELECT
				dp.person_id,
				CAST(a.create_timestamp AS DATE) 'create_date',
				a.practice_id,
				a.appt_kept_ind,
				a.cancel_ind,
				a.intrf_no_show_ind,
				a.confirm_ind,
				a.appt_date,
				e.event
			FROM ##diag_persons dp
				LEFT JOIN NGPROD02.NGProd.dbo.appointments a ON
					dp.person_id = a.person_id
				LEFT JOIN NGPROD02.NGProd.dbo.events e ON
					a.event_id = e.event_id
			) sq
		) sq2
	) sq3
GROUP BY sq3.person_id, sq3.tot_pracs, sq3.tot_kept_appts
GO


--> get the phone stats
	--> execute the PROC for "BI01 - NGProd - patients phones v2.sql"
		--> 1,886,192 @ 00:58
DROP TABLE IF EXISTS ##person_attr_phones
SELECT
	sq.person_id, sq.num_phones, 
	nppnp.home_phone, nppnp.sec_home_phone, 
	nppnp.day_phone, nppnp.alt_phone
INTO ##person_attr_phones
FROM (
	SELECT
		pa.person_id, sq.num_phones
	FROM ##persons_attr pa
		LEFT JOIN 
				(SELECT npp.person_id, MAX(npp.cnt_inst_person) 'num_phones'
				FROM [AVP_Marketing].dbo.[nextgen_patients_phones] npp
				GROUP BY npp.person_id
				) sq ON
			pa.person_id = sq.person_id
	) sq
	LEFT JOIN AVP_Marketing.dbo.nextgen_patients_phones_nums_pivot nppnp ON
		sq.person_id = nppnp.person_id
GO


--> get the location stats
DROP TABLE IF EXISTS ##person_attr_locs
SELECT
	sq3.person_id, sq3.loc_name, sq3.tot_at_loc,
	CAST(CAST(sq3.tot_at_loc AS FLOAT)/CAST(sq3.tot_appts AS FLOAT) AS DECIMAL(4,2)) 'loc_ratio',
	sq3.tot_locs
INTO ##person_attr_locs
FROM ( 
	SELECT 
		sq2.*,
		ROW_NUMBER() OVER(PARTITION BY sq2.person_id ORDER BY sq2.tot_at_loc DESC) 'xrow',
		SUM(sq2.tot_at_loc) OVER(PARTITION BY sq2.person_id) 'tot_appts',
		COUNT(*) OVER(PARTITION BY sq2.person_id) 'tot_locs'
	FROM (
		-- some persons were lost here - this needs troubleshooting
		SELECT 
			sq.person_id, sq.loc_name,
			COUNT(*) 'tot_at_loc'
		FROM (
			SELECT
				pa.person_id, a.appt_kept_ind,
				ISNULL(nlm.alex_loc_name, nlm.Location_Name) 'loc_name'
			FROM ##persons_attr pa
				LEFT JOIN NGPROD02.NGProd.dbo.appointments a ON
					pa.person_id = a.person_id
				LEFT JOIN AVP_Marketing.dbo.ng_loc_mstr nlm ON
					a.location_id = nlm.location_id
			) sq
		WHERE sq.appt_kept_ind = 'Y' -- AND sq.person_id = '3701FC2C-2697-4283-A533-2318C626A51E'
		GROUP BY sq.person_id, sq.loc_name
		) sq2
	) sq3
WHERE sq3.xrow = 1
GO


--> merge the 3 tables => 22404
DROP TABLE IF EXISTS AVP_Marketing.dbo.ng_master_patient
SELECT 
	pa.person_id, 
	dp.sex, 
	--dp.height_cm, ROUND(dp.height_cm/30.48,2) 'height_ft',
	--dp.weight_kg, ROUND(dp.weight_kg*2.20462,2) 'weight_lb',
	dp.age, dp.ethnicity,
	dp.marital_status, LEFT(dp.zip,5) 'zip', dp.bp_determ, dp.bmi_determ,
	pa.first_create, 
	CAST(pa.first_appt AS DATE) 'first_appt', 
	CAST(pa.last_appt AS DATE) 'last_apt', 
	pa.tot_kept_appts, pa.tot_pracs,
	CASE
		WHEN pa.max_canc = 1 THEN 'N'
		WHEN pa.max_canc = 2 THEN 'Y'
	END AS 'ever_cancel',
	CASE
		WHEN pa.max_nosho = 1 THEN 'N'
		WHEN pa.max_nosho = 2 THEN 'Y'
	END AS 'ever_noshow',
	CASE
		WHEN pa.max_conf = 1 THEN 'N'
		WHEN pa.max_conf = 2 THEN 'Y'
	END AS 'ever_confirm',
	CASE WHEN pas.cnt_tot IS NULL THEN 'N' ELSE 'Y' END AS 'had_surgery',
	pas.first_surg_dos, pas.last_surg_dos,
	pas.cnt_tot, pas.tot_uniq_surgEvents,
	pal.loc_name 'prefer_clinic', pal.tot_at_loc,
	pal.loc_ratio, pal.tot_locs,
	pap.num_phones, pap.home_phone, pap.sec_home_phone, 
	pap.day_phone, pap.alt_phone
INTO AVP_Marketing.dbo.ng_master_patient
FROM ##persons_attr pa
	LEFT JOIN ##diag_persons dp ON
		pa.person_id = dp.person_id
	LEFT JOIN ##persons_attr_surgeries pas ON
		pa.person_id = pas.person_id
	LEFT JOIN ##person_attr_phones pap ON
		pa.person_id = pap.person_id
	LEFT JOIN ##person_attr_locs pal ON
		pa.person_id = pal.person_id
GO


SELECT TOP 100 * FROM AVP_Marketing.dbo.ng_master_patient