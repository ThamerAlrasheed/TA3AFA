import pandas as pd
import glob
import os

main_file = "/Users/mac/Desktop/TA3AFA/ASSETS/INFORMATION FOR DEV/MOHDrugPrice_17Nov2025_KSP_only_Composition_Indications (1) (1)(1).xlsx"
print("MAIN FILE:", pd.read_excel(main_file, nrows=0).columns.tolist())

files = glob.glob("/Users/mac/Desktop/TA3AFA/ASSETS/INFORMATION FOR DEV/*.xlsx")
for f in files:
    if "MOHDrugPrice" not in f:
        print(f"--- {os.path.basename(f)} ---")
        try:
            print("Row 0:", pd.read_excel(f, nrows=0).columns.tolist())
        except Exception as e:
            print("Error:", e)
        try:
            # Sometime headers are at row 3 like bayer
            print("Row 3:", pd.read_excel(f, header=3, nrows=0).columns.tolist())
        except Exception as e:
            pass
