
CREATE OR ALTER FUNCTION dbo.PersonalEmail(@EMAIL varchar(255)) RETURNS bit as

/*
	AUTHOR: Joshua Harvey
	ORIG DATE: 2021-04-15
	PURPOSE: determine if email uses generic public esp domain 
	NOTES: this does not verify if the email belongs to a person
	
*/

BEGIN     
  DECLARE @bitEmailVal as Bit
  DECLARE @EmailText varchar(100)
  DECLARE @EmailDomain varchar(100)

 
  SET @EmailText=ltrim(rtrim(isnull(@EMAIL,'')))
  SET @EmailDomain = SUBSTRING(@EmailText, CHARINDEX('@', @EmailText)+1, LEN(@EmailText))
  SET @bitEmailVal = 
		CASE 
			WHEN @EmailDomain IN (select esp_domain from vwAVP_valid_major_emailServiceProviders)
			THEN 1
			ELSE 0
		END

  RETURN @bitEmailVal
END 
GO