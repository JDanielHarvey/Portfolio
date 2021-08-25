// Everything that is not preceeded by "//" is custom written M code

let
    Source = src_BISQL_avail,
    //#"Changed Type" = Table.TransformColumnTypes(Source,{{"InsertDate", type date}}),
    //#"Removed Columns1" = Table.RemoveColumns(#"Changed Type",{"weekdayname", "rankX", "category"}),
    Custom1 = Table.SelectRows(#"Removed Columns1", each ([ProviderType] = "Cataract" or [ProviderType] = "OD")),
    //#"Removed Errors" = Table.RemoveRowsWithErrors(Custom1),
    //#"Grouped Rows" = Table.Group(#"Removed Errors", {"practice_name", "location_name", "loc_id", "wek"}, {{"InsertDate", each List.Min([InsertDate])}, {"min_long", each List.Min([DateDiff]), type number}, {"avg_long", each List.Average([DateDiff]), type number}, {"sdv_long", each List.StandardDeviation([DateDiff]), type number}, {"med_long", each List.Median([DateDiff]), type number}, {"max_long", each List.Max([DateDiff]), type number}}),
    //#"Changed Type1" = Table.TransformColumnTypes(#"Grouped Rows",{{"min_long", Int64.Type}, {"avg_long", Int64.Type}, {"med_long", Int64.Type}, {"max_long", Int64.Type}}),
    #"Added Custom" = Table.AddColumn(#"Changed Type1", "availability_text", each if [min_long] >= 30 or ([avg_long] >= 30 and [med_long] >= 20)
 then "low_avail" 

else if [min_long] <= 7 and [avg_long] <= 7 
then "high_avail"


else if [min_long] <= 14 and [avg_long] <= 14 
then "avail"


else "mod_avail"),
    custom_weighting = Table.AddColumn(#"Added Custom", "Custom", each if [availability_text] = "low_avail" then 0.5 else if [availability_text] = "mod_avail" then 2 else if [availability_text] = "avail" then 3 else if [availability_text] = "high_avail" then 4 else 0),
    //Weekly_NestedTable = Table.Group(custom_weighting, {"practice_name", "location_name", "loc_id"}, {{"Nested_Table", each _, type table}}),
    nested_index = Table.TransformColumns(Weekly_NestedTable,  {  "Nested_Table", each Table.AddIndexColumn(_,  "Index", Table.RowCount(_) , -1 ) } ),
    CreateExponentialProgression = Table.TransformColumns(#"nested_index",  { "Nested_Table", (IT) => Table.AddColumn(IT, "ExponentialProgression", (IIT) =>  Number.Power(1/2, IIT[Index]), Int64.Type )  } ),
    NestedTableRowCount = Table.TransformColumns(#"CreateExponentialProgression",  { "Nested_Table", (IT) => Table.AddColumn(IT, "TotalRows", (IIT) => Table.RowCount(IT) ) } ),
    SumExponential = Table.AddColumn(NestedTableRowCount, "Custom", each List.Sum([Nested_Table][ExponentialProgression])),
    NormalizeExponential = Table.AddColumn(SumExponential, "Custom.1", (OT) => Table.AddColumn(OT[Nested_Table], "Normalized", (IT) => IT[ExponentialProgression]/OT[Custom], Int64.Type) ),
    #"Weight*Normalized" = Table.TransformColumns(NormalizeExponential,  { "Custom.1", (IT) => Table.AddColumn(IT, "Final", (IIT) => IIT[Custom]*IIT[Normalized], Int64.Type ) } ),
    #"Removed Other Columns" = Table.SelectColumns(#"Weight*Normalized",{"Custom.1"}),
    Custom2 = Table.AddColumn(#"Removed Other Columns", "TotalScore", each Number.Round(List.Sum([Custom.1][Final]),2)),
   //#"Expanded Custom.1" = Table.ExpandTableColumn(Custom2, "Custom.1", {"practice_name", "location_name", "loc_id", "InsertDate", "min_long", "avg_long", "med_long", "max_long", "availability_text", "Final"}, {"practice_name", "location_name", "loc_id", "InsertDate", "min_long", "avg_long", "med_long", "max_long", "availability_text", "Final"}),
    //#"Changed Type2" = Table.TransformColumnTypes(#"Expanded Custom.1",{{"InsertDate", type date}}),
    //#"Sorted Rows" = Table.Sort(#"Changed Type2",{{"location_name", Order.Ascending}, {"InsertDate", Order.Ascending}})
in
    #"Sorted Rows"