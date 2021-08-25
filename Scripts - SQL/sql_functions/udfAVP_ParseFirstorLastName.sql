
create OR alter function dbo.ParseLastName (@NameType varchar(5), @FullName varchar(255)) RETURNS varchar(100) as

/*
	AUTHOR: Joshua Harvey
	ORIG DATE: 2021-08-24
	PURPOSE: parse out first or last name
	NOTES: 
*/

begin

-- --> used for development and debugging
--declare @NameType nvarchar(5)
--set @NameType = 'last'
--declare @FullName nvarchar(255)
--set @FullName = 'Joshua H'

declare @NamePartial nvarchar(100)

-- handles the first name
if lower(@NameType) = 'first' and charindex(' ', @FullName) > 0
	set @NamePartial = lower( substring(@FullName, 1, charindex(' ', @FullName) - 1) )
-- handles the last name
else if lower(@NameType) = 'last' and charindex(' ', @FullName) > 0
	set @NamePartial = lower( reverse(substring(reverse(@FullName), 1, charindex(' ', reverse(@FullName))-1)) )
-- returns error if not a full name
else if charindex(' ', @FullName) = 0
	set @NamePartial = 'Name does not include spaces'

set @NamePartial = upper(left(@NamePartial,1)) + right(@NamePartial, len(@NamePartial) - 1 )


return @NamePartial

end