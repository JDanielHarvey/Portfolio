
create or alter proc spAVP_dateTable
as 
begin 

/*
	AUTHOR: Joshua Harvey
	ORIG DATE: 2021-02-03
	PURPOSE: date table for universal use
	SOURCE: self generating 
*/
	declare @start_date date set @start_date = '2017-01-01'
	declare @end_date date set @end_date = '2021-12-31'

	--> recursive date table
	;with 
	cte1a as (
		-- anchor query
		select @start_date as full_Date

		union all

		-- recursive query
		select dateadd(day, 1, full_Date) as dateTable
		from cte1a where dateadd(day, 1, full_Date) < @end_date
		)
	select
		full_Date, year(full_Date) 'Year', month(full_Date) 'Month', datename(week,full_Date) 'WeekYear',
		day(full_date) 'DayMonth', datename(dayofyear, full_Date) 'DayYear',
		datename(month, full_Date) 'MonthName',	datename(weekday, full_Date) 'WeekDay',
		datefromparts(year(full_Date),month(full_Date),1) 'FirstofMonth',
		case when hd.holidate is null and datename(weekday, full_Date) not in ('Saturday','Sunday') then 1 else 0 end as 'rev_day',
		case when hd.holidate is null and datename(weekday, full_Date) not in ('Saturday','Sunday') and full_Date < getdate() then 1 else 0 end as 'rev_day_todate',
		min(full_Date) over(partition by year(full_Date), datename(week,full_Date)) 'grp_date'
	from cte1a
	left join 
		(
		SELECT hdays.holidate
		FROM (
			VALUES
			-- 2017 holidays
			('2017-01-02'),('2017-05-29'),('2017-07-03'),('2017-07-04'),('2017-11-23'),('2017-11-24'),('2017-11-25'),('2017-12-26'),
			-- 2018 holidays
			('2018-01-01'),('2018-05-25'),('2018-05-28'),('2018-07-04'),('2018-09-03'),('2018-11-22'),('2018-11-23'),('2018-12-24'),('2018-12-25'),
			-- 2019 holidays
			('2019-01-01'),('2019-05-27'),('2019-07-04'),('2019-07-05'),('2019-09-02'),('2019-11-28'),('2019-11-29'),('2019-12-24'),('2019-12-25'),
			-- 2020 holidays
			('2020-01-01'),('2020-05-25'),('2020-07-02'),('2020-07-03'),('2020-09-07'),('2020-11-26'),('2020-11-27'),('2020-12-24'),('2020-12-25'),
			-- 2021 holidays 
			('2021-01-01'),('2021-05-31'),('2021-07-05'),('2021-09-06'),('2021-11-25'),('2021-11-26'),('2021-12-24'),('2021-12-31')
			) 
			AS hdays (holidate)) hd on 
			cte1a.full_Date = hd.holidate
	option (MAXRECURSION 32767);

end