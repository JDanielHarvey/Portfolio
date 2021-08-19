


CREATE OR ALTER FUNCTION dbo.ChkValidHomeAddress(@ADDRESS varchar(255)) RETURNS bit as

/*
	AUTHOR: Joshua Harvey
	ORIG DATE: 2021-05-06
	PURPOSE: determine validity of home address based on street address formatting prefix
	NOTES: this does not verify if home residence is accurate / up-to-date for a patient 
*/

BEGIN     
  DECLARE @bitAddressVal as Bit
  DECLARE @AddressText varchar(255)

  SET @AddressText = lower(ltrim(rtrim(isnull(@ADDRESS,''))))

  SET @bitAddressVal = case 
                          when trim(@AddressText) = '' then 0 
						 
                          when @AddressText like ('!@#$%^&*()[]{}"?/:;,.<>\') then 0

						  when len(@AddressText) < 6 then 0

						  when patindex('%[0-9]%', @AddressText) = 0 then 0

						  when @AddressText like 'p%o%box%' then 0
						  when @AddressText like 'apt%' then 0
						  when @AddressText like 'lot%' then 0
						  when @AddressText like 'unit%' then 0                       
                          when @AddressText like 'spc%' then 0
						  when @AddressText like 'box%' then 0
						  when @AddressText like 'number%' then 0
						  when @AddressText like 'site%' then 0
						  when @AddressText like 'p.o.%' then 0
						  when @AddressText like 'po%' then 0
						  when @AddressText like 'tlr%' then 0

                          else 1 
                      end
  RETURN @bitAddressVal
END 
GO