// dynamic date table using two date columns
// intended to be used with DAX USERELATIONSHIP rather than multiple date tables

let
    Source = fValue,
    #"Removed Other Columns" = Table.SelectColumns(Source,{"call_date", "pageview_date"}),
    #"Changed Type" = Table.TransformColumnTypes(#"Removed Other Columns",{{"call_date", type number}, {"pageview_date", type number}}),
    Custom2 = Table.SelectColumns(#"Changed Type", {"call_date"}), // selects the first column
    Custom3 = Table.SelectColumns(#"Changed Type", {"pageview_date"}), // selects the second column
    Custom1 = Table.Combine({Table.SelectColumns(#"Changed Type", {"call_date"}), Table.RenameColumns(Table.SelectColumns(#"Changed Type", {"pageview_date"}),{{"pageview_date","call_date"}})}), // merges the two columns
    #"Calculated Minimum" = {Number.Round(List.Min(Custom1[call_date]),0)..Number.Round(List.Max(Custom1[call_date]),0)+180}, // creates the dynamic list using min and max
    #"Converted to Table" = Table.FromList(#"Calculated Minimum", Splitter.SplitByNothing(), null, null, ExtraValues.Error),
    #"Changed Type1" = Table.TransformColumnTypes(#"Converted to Table",{{"Column1", type date}}),
    #"Renamed Columns" = Table.RenameColumns(#"Changed Type1",{{"Column1", "dDate"}})
	
	// add all other desired date dimensions after this step

in
    #"Renamed Columns"