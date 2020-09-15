/*
	AUTHOR: Joshua Harvey
	ORIG DATE: 2020, 04, 22
	PURPOSE: Creates an easy to access unpivoted phone number table with risk analysis
	NOTES: 
*/


-->creates repeating person rows with all 4 possible phone values
	--> 1,896,614 @ 00:17
DROP TABLE IF EXISTS ##person_phones
SELECT 
	sq2.person_id, sq2.PhoneNum, sq2.PhoneType,
	COUNT(*) OVER(PARTITION BY sq2.person_id) 'cnt_inst_phone'
INTO ##person_phones
FROM (
	SELECT 
		sq.*,
		ROW_NUMBER() OVER(PARTITION BY sq.person_id, sq.PhoneNum ORDER BY sq.PhoneType) 'xrnk'
	FROM (
		SELECT 
			pp.person_id, pp.PhoneNum, pp.PhoneType
		FROM
			(SELECT
				person_id,
				home_phone '1',
				sec_home_phone '2',
				day_phone '3',
				alt_phone '4'
			FROM NGPROD02.NGProd.dbo.person) p
			UNPIVOT
				(PhoneNum FOR PhoneType IN (p.[1],
				p.[2],
				p.[3],
				p.[4])
			) AS pp
		WHERE  
			pp.PhoneNum > '1111111111' AND TRIM(pp.PhoneNum) != '' AND LEN(pp.PhoneNum) > 9
		) sq
	) sq2
WHERE sq2.xrnk = 1
GO



--> creates the final table by classifying riskiness of numbers
	--> 1,896,614 @ 00:45
DROP TABLE IF EXISTS ##person_phones_final
SELECT 
	sq.*,
	ROUND(CAST(sq.cnt_inst_phoneXsurname AS FLOAT) / CAST(sq.cnt_inst_phone AS FLOAT),3) '% of surname',
	ROUND(MAX(CAST(sq.cnt_inst_phoneXsurname AS FLOAT)) OVER(PARTITION BY sq.PhoneNum) / CAST(sq.cnt_inst_phone AS FLOAT), 3)  '% of max'
INTO ##person_phones_final
FROM (
	SELECT
		pp.*,
		LOWER(P.last_name) 'last_name',
		LOWER(P.first_name) 'first_name',
		COUNT(*) OVER(PARTITION BY pp.person_id) 'cnt_inst_person',
		COUNT(*) OVER(PARTITION BY pp.PhoneNum, LOWER(P.last_name)) 'cnt_inst_phoneXsurname'
	FROM ##person_phones pp
	LEFT JOIN NGPROD02.NGProd.dbo.person p ON
		pp.person_id = P.person_id
	--WHERE pp.cnt_inst_phone < 13 AND pp.cnt_inst_phone >2
	) AS sq
ORDER BY sq.cnt_inst_phone DESC, sq.PhoneNum, sq.cnt_inst_phoneXsurname DESC
GO


--> writes to the saved table
	--> 1,896,614 @ 00:02
DROP TABLE IF EXISTS AVP_Marketing.dbo.ref_ng_patients_phones_nums_unpivot
SELECT
	ppf.person_id, ppf.PhoneNum,
	CASE
		WHEN ppf.PhoneType = 1 THEN 'home_phone'
		WHEN ppf.PhoneType = 2 THEN 'sec_home_phone'
		WHEN ppf.PhoneType = 3 THEN 'day_phone'
		WHEN ppf.PhoneType = 4 THEN 'alt_phone'
	END AS 'PhoneType',
	ppf.cnt_inst_phone, ppf.last_name, ppf.first_name,
	ppf.cnt_inst_person, ppf.cnt_inst_phoneXsurname,
	ppf.[% of surname], ppf.[% of max],
	CASE 
		WHEN ppf.cnt_inst_phone > 25 THEN 'risk_high'
		WHEN ppf.cnt_inst_phone > 4 AND ppf.[% of surname] < .65 THEN 'risk_high'
		WHEN ppf.cnt_inst_phone > 4 AND ppf.[% of surname] >= .65 THEN 'risk_med'
		WHEN ppf.[% of surname] >= .90 THEN 'risk_low'
		WHEN ppf.[% of surname] >= .65 THEN 'risk_med'
		WHEN ppf.[% of surname] <= .65 THEN 'risk_med_high'
		ELSE 'risk_undeclared'
	END AS 'surname_risk_lvl'
INTO AVP_Marketing.dbo.ref_ng_patients_phones_nums_unpivot
FROM ##person_phones_final ppf
ORDER BY ppf.cnt_inst_phone DESC, ppf.PhoneNum, ppf.cnt_inst_phoneXsurname DESC
GO


--> pivots the phone numbers for each phone type category
	--> 1,633,113 @ 00:02
DROP TABLE IF EXISTS [AVP_Marketing].dbo.[ref_ng_patients_phones_nums_pivot]
SELECT 
	*
INTO [AVP_Marketing].dbo.[ref_ng_patients_phones_nums_pivot]
FROM (
	SELECT
		npp.person_id, npp.PhoneNum, npp.PhoneType --,npp.surname_risk_lvl
	FROM AVP_Marketing.dbo.ref_ng_patients_phones_nums_unpivot npp
	) sq
PIVOT (
	MIN(sq.PhoneNum)
	FOR PhoneType IN ([home_phone],	[sec_home_phone], [day_phone], [alt_phone])
	) AS pv
ORDER BY pv.person_id
GO


--> pivots the risk levels for each phone type category
	--> 1,633,113 @ 00:02
DROP TABLE IF EXISTS [AVP_Marketing].dbo.[ref_ng_patients_phones_risks_pivot]
SELECT 
	*
INTO [AVP_Marketing].dbo.[ref_ng_patients_phones_risks_pivot]
FROM (
	SELECT
		npp.person_id, npp.PhoneType, npp.surname_risk_lvl
	FROM AVP_Marketing.dbo.ref_ng_patients_phones_nums_unpivot npp
	) sq
PIVOT (
	MIN(sq.surname_risk_lvl)
	FOR PhoneType IN ([home_phone],	[sec_home_phone], [day_phone], [alt_phone])
	) AS pv
ORDER BY pv.person_id
GO


-- investigate the %s to determine the best formula 
/*
SELECT * FROM ##person_phones_final ppf 
WHERE ppf.cnt_inst_phone >= 4 AND ppf.[% of max] >= .33
ORDER BY ppf.[% of max] ASC, ppf.PhoneNum, ppf.cnt_inst_phoneXsurname
*/


