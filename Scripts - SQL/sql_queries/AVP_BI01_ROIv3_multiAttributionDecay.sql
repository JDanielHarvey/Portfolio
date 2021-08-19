/*
	AUTHOR: Joshua Harvey
	ORIG DATE: 2020, 07, 10
	PURPOSE: Build a multi-touch attribution model to distribute revenue to all sources
	NOTES: Time decay formula = 2^(-t/hl)
		-t = time between interaction and appointment
		hl = half life 
	RESOURCES: https://github.com/American-Vision-Partners/Marketing/blob/master/ROI/README.rst
*/

SELECT 
	sq6.person_id, sq6.lead_create_date, sq6.appt_create_date,
	sq6.source_type, sq6.orig_source, sq6.utm_campaign,
	sq6.row, sq6.cnt, sq6.date_dif, 
	sq6.net_rev,
	CASE 
		WHEN sq6.uniq_by_appt > 1 AND sq6.row = 1 AND sq6.max_row > 1 THEN (sq6.tot_prs_rev - sq6.min_prs_rev) 
		ELSE sq6.tot_prs_rev
	END AS 'rev_dif',
	sq6.linear_rev,
	CAST((sq6.exp_decay/sq6.sum_exp_decay) * sq6.tot_prs_rev AS DECIMAL(10,2)) 'decay_rev'
FROM (
	SELECT
		sq5.*,
		SUM(sq5.exp_decay) OVER(PARTITION BY sq5.person_id) 'sum_exp_decay'
	FROM (
		--> ex_decay = 2^-x
		SELECT 
			sq4.*,
			POWER(2.00,CAST(sq4.[-x] AS DECIMAL(10,7))) 'exp_decay'
		FROM (
			--> -x = -t/hl
			SELECT 
				sq3.*,
				sq3.tot_prs_rev*sq3.linear_model 'linear_rev',
				CAST(-sq3.date_dif/sq3.avg_diff AS DECIMAL (8,3)) '-x'
			FROM (
				SELECT 
					sq2.*,
					ROUND(CAST(1 AS FLOAT),3) / ROUND(CAST(sq2.cnt AS FLOAT),3) 'linear_model',
					CAST(AVG(sq2.date_dif) OVER(PARTITION BY sq2.person_id) AS DECIMAL(7,4)) 'avg_diff',
					MAX(sq2.uniq_prs_apt) OVER(PARTITION BY sq2.person_id) 'uniq_by_appt',
					MAX(sq2.row) OVER(PARTITION BY sq2.person_id) 'max_row'
				FROM (
					SELECT
						sq.*,
						ROW_NUMBER() OVER(PARTITION BY sq.person_id ORDER BY sq.lead_create_date) 'row',
						COUNT(*) OVER(PARTITION BY sq.person_id) 'cnt',
						DATEDIFF(DAY,sq.lead_create_date,sq.appt_create_date) 'date_dif',
						MAX(sq.net_rev) OVER(PARTITION BY sq.person_id) 'tot_prs_rev',
						MIN(sq.net_rev) OVER(PARTITION BY sq.person_id) 'min_prs_rev',
						DENSE_RANK() OVER(PARTITION BY sq.person_id ORDER BY sq.appt_create_date) 'uniq_prs_apt'
					FROM (
						SELECT 
							rpdd.person_id, rpdd.first_date 'lead_create_date', 
							rpdd.appt_create_date, rpdd.net_rev, 'calls' AS 'source_type',
							'healthgrades' AS 'orig_source', NULL AS 'utm_campaign'
						FROM AVP_Marketing.dbo.roi_paidmedia_digital_directories rpdd
							UNION
						SELECT 
							rpd.person_id,rpd.lead_create_date,rpd.appt_create_date,
							rpd.net_rev, rpd.source_type, rpd.orig_source, rpd.utm_campaign
						FROM AVP_Marketing.dbo.roi_paidmedia_digital rpd
						) sq
					) sq2
				WHERE sq2.cnt > 1 AND sq2.net_rev IS NOT NULL
			) sq3
		) sq4
	) sq5
) sq6
ORDER BY sq6.person_id, sq6.lead_create_date ASC