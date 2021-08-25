
CREATE OR ALTER FUNCTION dbo.ChkValid_US_AreaCode (@AREACODE varchar(3)) RETURNS bit as

/*
	AUTHOR: Joshua Harvey
	ORIG DATE: 2021-08-19
	PURPOSE: determine validity of area code
	NOTES: 
	SOURCE:
		https://docs.google.com/spreadsheets/d/1akoy3F98TqZJfJhZg_laLw5RWUrtECcB5e7bHJRspbE/edit#gid=0
*/

BEGIN     
  DECLARE @bitPhoneVal as Bit
  DECLARE @PhoneAreaCode varchar(3)

  SET @PhoneAreaCode = @AREACODE
 

  SET @bitPhoneVal = case 
						when @PhoneAreaCode not in (select area_code from AVP_Marketing.src.valid_area_codes) then 0
						
						else 1 
                     end


  RETURN @bitPhoneVal
END 
GO