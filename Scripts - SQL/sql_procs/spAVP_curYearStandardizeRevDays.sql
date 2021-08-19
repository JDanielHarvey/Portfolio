
create or alter proc spAVP_curYearStandardizeRevDays
as 
begin 

/*
	AUTHOR: Joshua Harvey
	ORIG DATE: 2021-02-03
	PURPOSE: date table for universal use
	SOURCE: spAVP_dateTable 
*/

;with
cte1a as (
	SELECT 
		dt.*, 
		sum(rev_day) over(partition by dt.Year, dt.Month) 'rev_day_yyyymm',
		sum(rev_day_todate) over(partition by dt.Year, dt.Month) 'rev_day_todate_yyyymm'
	FROM OPENQUERY(BI01, 'EXEC [spAVP_dateTable]') dt
),	
cte2a as (
	select c1a.Year, c1a.Month, min(c1a.rev_day_yyyymm) 'rev_day_yyyymm', min(c1a.rev_day_todate_yyyymm) 'rev_day_todate_yyyymm'
from cte1a c1a
group by c1a.Year, c1a.Month
)
select c2a.*, sq.rev_day_yyyymm as 'cur_year_rev_days', sq.rev_day_yyyymm -c2a.rev_day_yyyymm 'negate_days'
from cte2a c2a
left join (select * from cte2a c2a where c2a.Year = Year(getdate()) ) sq on 
	c2a.Month = sq.Month

end
