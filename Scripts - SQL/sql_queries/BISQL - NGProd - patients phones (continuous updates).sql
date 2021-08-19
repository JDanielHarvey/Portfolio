/*
	AUTHOR: Joshua Harvey
	ORIG DATE: 2020, 04, 22
	PURPOSE: Creates an easy to access unpivoted phone number table with risk analysis
	NOTES: 
*/


	-- 2169364 @ 00:00
DROP TABLE IF EXISTS AVP_Marketing.dbo.ref_ng_patients_phones_nums_unpivot_test
SELECT person_id, PhoneNum, PhoneType, last_update, numStatus 
INTO AVP_Marketing.dbo.ref_ng_patients_phones_nums_unpivot_test
FROM AVP_Marketing.dbo.ref_ng_patients_phones_nums_unpivot



--_________________________________SEC 1: Base Phone Table_________________________________

--> creates repeating person rows with all 5 possible phone values
	--> ~2404417 @ ~00:07
DROP TABLE IF EXISTS #person_phones_1a
SELECT 
	sq2.person_id, sq2.PhoneNum, sq2.PhoneType,
	NULL AS 'status'
INTO #person_phones_1a
FROM (
	-- create filter for duplicate phone for any given person
	SELECT 
		sq.*,
		ROW_NUMBER() OVER(PARTITION BY sq.person_id, sq.PhoneNum ORDER BY sq.PhoneType) 'xrnk'
	FROM (
		-- unpivot phone nums from person table
		SELECT 
			pp.person_id, pp.PhoneNum, pp.PhoneType
		FROM
			(SELECT 
				person_id,
				home_phone '1',
				sec_home_phone '2',
				day_phone '3',
				alt_phone '4',
				cell_phone '5'
				--int_home_phone '6',
				--int_work_phone '7'
			FROM NGPROD02.NGProd.dbo.person pr
			WHERE 
				CAST(pr.create_timestamp AS DATE) >= CAST(getdate() AS DATE) OR
				CAST(pr.modify_timestamp AS DATE) >= CAST(getdate() AS DATE)
			) p
			UNPIVOT
				(PhoneNum FOR PhoneType IN (
				p.[1],
				p.[2],
				p.[3],
				p.[4],
				p.[5]
				--p.[6],
				--p.[7]
				)
			) AS pp
		WHERE  
			pp.PhoneNum > '1111111111' AND TRIM(pp.PhoneNum) != '' AND LEN(pp.PhoneNum) > 9
		) sq
	) sq2
WHERE sq2.xrnk = 1
GO


--> rename the PhoneTypes to original values
	-- ~2404425 @ ~00:00
DROP TABLE IF EXISTS #person_phones_1b
SELECT
	p1a.person_id, p1a.PhoneNum,
	CASE
		WHEN p1a.PhoneType = 1 THEN 'home_phone'
		WHEN p1a.PhoneType = 2 THEN 'sec_home_phone'
		WHEN p1a.PhoneType = 3 THEN 'day_phone'
		WHEN p1a.PhoneType = 4 THEN 'alt_phone'
		WHEN p1a.PhoneType = 5 THEN 'cell_phone'
	END AS 'PhoneType'
INTO #person_phones_1b
FROM #person_phones_1a p1a


--_________________________________SEC 2: Comparison_________________________________

--> new Table with only people from old table
	-- 2284323 @ 00:02
DROP TABLE IF EXISTS #newT_comparison_1a
SELECT *
INTO #newT_comparison_1a
FROM #person_phones_1b
WHERE person_id IN (SELECT DISTINCT person_id FROM AVP_Marketing.dbo.ref_ng_patients_phones_nums_unpivot)


--> full join from old and new comparing numbers and classifying 
	-- 144627 @ 00:02
DROP TABLE IF EXISTS #newT_comparison_2a
;WITH 
cte1a AS (
	SELECT  
		nu.person_id, nu.PhoneNum, nu.PhoneType, nu.create_date, 
		
		nu2.person_id 'n_person_id', nu2.PhoneNum 'n_PhoneNum', nu2.PhoneType 'n_PhoneType', getdate() 'n_create_date',

			CASE
				WHEN nu.PhoneNum = nu2.PhoneNum AND nu.PhoneType = nu.PhoneType AND (nu.PhoneNum IS NOT NULL AND nu2.PhoneNum IS NOT NULL) THEN 'same'
				WHEN nu.PhoneNum = nu2.PhoneNum AND nu.PhoneType != nu.PhoneType AND (nu.PhoneNum IS NOT NULL AND nu2.PhoneNum IS NOT NULL) THEN 'reclass'
				WHEN (nu.PhoneNum != nu2.PhoneNum) AND (nu2.PhoneNum IS NOT NULL) THEN 'updated_phone'
				WHEN nu.PhoneNum IS NULL THEN 'new_phone'
				WHEN nu.person_id IS NOT NULL AND nu2.person_id IS NULL THEN 'scrubbed'
				ELSE 'undeclared'
			END AS 'numStatus'
	FROM AVP_Marketing.dbo.ref_ng_patients_phones_nums_unpivot_test nu
	FULL JOIN #newT_comparison_1a nu2 ON 
		(nu.person_id = nu2.person_id AND
		nu.PhoneType = nu2.PhoneType) OR 
		(nu.person_id = nu2.person_id AND
		nu.PhoneNum = nu2.PhoneNum)
	)
SELECT  *
INTO #newT_comparison_2a
FROM cte1a 
WHERE numStatus != 'same'



--_________________________________SEC 3: Write the updates_________________________________

--> Update the 'updated_phone' records for existing persons
UPDATE AVP_Marketing.dbo.ref_ng_patients_phones_nums_unpivot_test
SET numStatus = 'outdated', modify_date = c2a.n_create_date
FROM AVP_Marketing.dbo.ref_ng_patients_phones_nums_unpivot_test un
INNER JOIN #newT_comparison_2a c2a ON 
	un.person_id = c2a.person_id AND 
	un.PhoneNum = c2a.PhoneNum AND
	un.PhoneType = c2a.PhoneType AND
	un.create_date = c2a.create_date
WHERE c2a.numStatus = 'updated_phone'


--> Inserts the 'updated_phone' records for existing persons
INSERT INTO AVP_Marketing.dbo.ref_ng_patients_phones_nums_unpivot_test (person_id, PhoneNum, PhoneType, create_date, numStatus)
SELECT n_person_id, n_PhoneNum, n_PhoneType, create_date, numStatus
FROM #newT_comparison_2a 
WHERE numStatus = 'updated_phone'


--> Update the 'scrubbed' records for existing persons
UPDATE AVP_Marketing.dbo.ref_ng_patients_phones_nums_unpivot_test
SET numStatus = 'scrubbed', modify_date = c2a.create_date
FROM AVP_Marketing.dbo.ref_ng_patients_phones_nums_unpivot_test un
INNER JOIN #newT_comparison_2a c2a ON 
	un.person_id = c2a.person_id AND 
	un.PhoneNum = c2a.PhoneNum AND
	un.PhoneType = c2a.PhoneType AND
	un.create_date = c2a.create_date
WHERE c2a.numStatus = 'scrubbed'


--> Inserts the 'new_phone' records for existing persons
INSERT INTO AVP_Marketing.dbo.ref_ng_patients_phones_nums_unpivot_test (person_id, PhoneNum, PhoneType, create_date, numStatus)
SELECT n_person_id, n_PhoneNum, n_PhoneType, create_date, numStatus
FROM #newT_comparison_2a 
WHERE numStatus = 'new_phone'



--_________________________________SEC 3: Write New Numbers_________________________________

DECLARE @today DATETIME SET @today = (
SELECT MIN(n_create_date) FROM #newT_comparison_2a
WHERE CAST(n_create_date AS DATE) = CAST(getdate() AS DATE))

-- new people to insert to the final table
	-- 120103 @ 00:01
INSERT INTO AVP_Marketing.dbo.ref_ng_patients_phones_nums_unpivot_test (person_id, PhoneNum, PhoneType, create_date, numStatus)
SELECT
	person_id, PhoneNum, PhoneType, @today, NULL AS numStatus
FROM #person_phones_1b p1b
WHERE person_id NOT IN (SELECT DISTINCT person_id FROM AVP_Marketing.dbo.ref_ng_patients_phones_nums_unpivot_test)


	-- 2,428,475
SELECT COUNT(*)
FROM AVP_Marketing.dbo.ref_ng_patients_phones_nums_unpivot_test



