import pandas as pd
main_file = "/Users/mac/Desktop/TA3AFA/ASSETS/INFORMATION FOR DEV/MOHDrugPrice_17Nov2025_KSP_only_Composition_Indications (1) (1)(1).xlsx"
df_main = pd.read_excel(main_file)
print("Main Row 19 (excel row 21):")
print(df_main.iloc[19].to_dict())
