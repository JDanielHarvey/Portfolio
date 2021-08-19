


CREATE OR ALTER FUNCTION dbo.ChkValidEmail(@EMAIL varchar(255)) RETURNS bit as

/*
	AUTHOR: Joshua Harvey
	ORIG DATE: 2021-03-16
	PURPOSE: determine validity of email based on email formatting
	NOTES: this does not verify if an email inbox is valid
*/

BEGIN     
  DECLARE @bitEmailVal as Bit
  DECLARE @EmailText varchar(100)

  SET @EmailText=ltrim(rtrim(isnull(@EMAIL,'')))

  SET @bitEmailVal = case 
                          when trim(@EmailText) = '' then 0 
						  when @EmailText like '% %' then 0
                          when @EmailText like ('%["(),:;<>\]%') then 0
                          when substring(@EmailText,charindex('@',@EmailText),len(@EmailText)) like ('%[!#$%&*+/=?^`_{|]%') then 0
                          when (left(@EmailText,1) like ('[-_.+]') or right(@EmailText,1) like ('[-_.+]')) then 0                                                                                    
                          when (@EmailText like '%[%' or @EmailText like '%]%') then 0
                          when @EmailText LIKE '%@%@%' then 0
                          when @EmailText NOT LIKE '_%@_%._%' then 0
                          else 1 
                      end
  RETURN @bitEmailVal
END 
GO