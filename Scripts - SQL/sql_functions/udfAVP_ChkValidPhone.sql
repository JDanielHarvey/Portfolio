

CREATE OR ALTER FUNCTION dbo.ChkValidPhone (@PHONE varchar(255)) RETURNS bit as

/*
	AUTHOR: Joshua Harvey
	ORIG DATE: 2021-03-25
	PURPOSE: determine validity of phone based on formatting of phone
	NOTES: this does not verify if a phone number is in service
	SOURCE:
		https://docs.google.com/spreadsheets/d/1akoy3F98TqZJfJhZg_laLw5RWUrtECcB5e7bHJRspbE/edit#gid=0
*/

begin     
  declare @bitPhoneVal as Bit
  declare @PhoneText varchar(100)
  declare @PhoneAreaCode varchar(3)


  set @PhoneText=ltrim(rtrim(isnull(@PHONE,'')))
 
   
   if len(@PhoneText) = 12 and charindex('+1', @PhoneText) > 0
		set @PhoneText = replace(@PhoneText, '+1', '')
	else if len(@PhoneText) = 11 and left(@PhoneText, 1) = 1
		set @PhoneText = right(@PhoneText, 10)
	else 
		set @PhoneText = @PhoneText


	if len(@PhoneText) = 12 and charindex('+1', @PhoneText) > 0
		set @PhoneAreaCode = left( replace(@PhoneText, '+1', ''), 3)
	else if len(@PhoneText) = 11 and left(@PhoneText,1) = 1
		set @PhoneAreaCode = left( right(@PhoneText, 10), 3)
	else if len(@PhoneText) = 10
		set @PhoneAreaCode = left(@PhoneText,3)
   


  set @bitPhoneVal = case 
						when len(@PhoneText) != 10 then 0
						when @PhoneText = '' then 0
						when @PhoneText like '% %' then 0
						when @PhoneText like ('%@[#$^&"(),:;<>\]*%') then 0
						when @PhoneAreaCode not in (select area_code from AVP_Marketing.src.valid_area_codes) then 0
						
						else 1 
                     end


  return @bitPhoneVal
end 
GO