

create or alter function dbo.ParseSingleUTM(@utm nvarchar(20), @utmString nvarchar(255)) RETURNS nvarchar(50) as

/*
	AUTHOR: Joshua Harvey
	ORIG DATE: 2021-08-24
	PURPOSE: extract a single utm parameter value
	NOTES: Must include the equal sign. Possible values to be passed as first argument 
		utm_source=
		utm_medium=
		utm_campaign=
		utm_content=
		utm_keyword=
*/

begin 

--	--> used for development 
--declare @utmString nvarchar(255)
--set @utmString = 'utm_source=yelp&utm_medium=local&utm_campaign=clinic-suncity&utm_content=appt'

--declare @utm nvarchar(20)
--set @utm = 'utm_campaign='

--> ensures an equal sign has been included on the @utm parameter for the function
if charindex('=', 'utm_campaign') = 0
	set @utm = @utm + '='
else 
	set @utm = @utm


declare @utmParamMod nvarchar(255)
set @utmParamMod = 
		substring( @utmString,
			charindex(@utm, @utmString) + len(@utm),
			len(@utmString)
			)

return substring( @utmParamMod,
		0,
		charindex('&', @utmParamMod)
		)

end