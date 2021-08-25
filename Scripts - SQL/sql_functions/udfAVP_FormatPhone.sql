
CREATE OR ALTER FUNCTION dbo.FormatPhone (@PHONE varchar(255)) RETURNS varchar(100) as

/*
	AUTHOR: Joshua Harvey
	ORIG DATE: 2021-08-24
	PURPOSE: format US phone number
	NOTES: 
*/

begin     
  declare @PhoneText varchar(100)

  set @PhoneText = @PHONE

  set @PhoneText = replace(@PhoneText, '(', '')
  set @PhoneText = replace(@PhoneText, ')', '')
  set @PhoneText = replace(@PhoneText, '-', '')
  set @PhoneText = replace(@PhoneText, '+1', '')
  set @PhoneText = replace(@PhoneText, ' ', '')

  set @PhoneText = ltrim(rtrim(@PhoneText))
 

  return @PhoneText
end 
