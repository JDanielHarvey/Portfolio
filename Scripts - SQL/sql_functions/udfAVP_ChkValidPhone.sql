

CREATE OR ALTER FUNCTION dbo.ChkValidPhone (@PHONE varchar(255)) RETURNS bit as

/*
	AUTHOR: Joshua Harvey
	ORIG DATE: 2021-03-25
	PURPOSE: determine validity of phone based on formatting of phone
	NOTES: this does not verify if a phone number is in service
	SOURCE:
		https://docs.google.com/spreadsheets/d/1akoy3F98TqZJfJhZg_laLw5RWUrtECcB5e7bHJRspbE/edit#gid=0
*/

BEGIN     
  DECLARE @bitPhoneVal as Bit
  DECLARE @PhoneText varchar(100)
  DECLARE @PhoneAreaCode varchar(3)


  SET @PhoneText=ltrim(rtrim(isnull(@PHONE,'')))
  SET @PhoneAreaCode = left(@PhoneText,3)
 

  SET @bitPhoneVal = case 
						when len(@PhoneText) != 10 then 0
						when @PhoneText = '' then 0
						when @PhoneText like '% %' then 0
						when @PhoneText like ('%@[#$^&"(),:;<>\]*%') then 0
						when @PhoneAreaCode not in (select area_code from vwAVP_valid_area_codes) then 0
						
						else 1 
                     end


  RETURN @bitPhoneVal
END 
GO