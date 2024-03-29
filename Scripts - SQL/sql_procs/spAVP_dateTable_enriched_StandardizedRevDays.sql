USE [AVP_Marketing]
GO
/****** Object:  StoredProcedure [dbo].[spAVP_curYearStandardizeRevDays]    Script Date: 7/13/2021 4:04:52 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

create proc [dbo].[spAVP_dateTableStandardizedRevDays]
as 
begin 

/*
	AUTHOR: Joshua Harvey
	ORIG DATE: 2021-07-13
	PURPOSE: enriched date table
	NOTES: without OPENQUERY() this couldn't be used inside table variables b/c of "Msg 8164"
		"An INSERT EXEC statement cannot be nested."
	SOURCE: spAVP_dateTable 
*/


Declare @dt Table 
	(full_Date DATE, [Year] INT, [Month] INT, WeekYear INT, DayMonth INT, DayYear INT, 
	MonthName VARCHAR(10), WeekDay VARCHAR(10), FirstofMonth DATE, rev_day INT, rev_day_todate INT, grp_date date)
Insert @dt Exec AVP_Marketing.dbo.[spAVP_dateTable] 

;with
cte1a as (
	select 
		dt.*, 
		sum(rev_day) over(partition by dt.Year, dt.Month) 'rev_day_yyyymm',
		sum(rev_day_todate) over(partition by dt.Year, dt.Month) 'rev_day_todate_yyyymm'
	from @dt dt
),	
cte2a as (
	select c1a.Year, c1a.Month, min(c1a.rev_day_yyyymm) 'rev_day_yyyymm', min(c1a.rev_day_todate_yyyymm) 'rev_day_todate_yyyymm'
	from cte1a c1a
	group by c1a.Year, c1a.Month
),
cte3a AS (
	select c2a.*, sq.rev_day_yyyymm as 'cur_year_rev_days', sq.rev_day_yyyymm -c2a.rev_day_yyyymm 'negate_days'
	from cte2a c2a
	left join (select * from cte2a c2a where c2a.Year = Year(getdate()) ) sq on 
		c2a.Month = sq.Month
	)
select oq.*, sq.rev_day_todate_yyyymm, sq.rev_day_yyyymm
from @dt oq
left join cte3a sq on
	oq.[Year] = sq.[Year] AND
	oq.[Month] = sq.[Month]
order by oq.full_Date asc

end
