import pandas as pd
import re
from difflib import SequenceMatcher

def normalize_name(name):
    if pd.isna(name): return ""
    name = str(name).lower()
    name = re.sub(r'\s+', ' ', name)
    name = re.sub(r'[^\w\s]', '', name)
    return name.strip()

main_file = "/Users/mac/Desktop/TA3AFA/ASSETS/INFORMATION FOR DEV/MOHDrugPrice_17Nov2025_KSP_only_Composition_Indications (1) (1)(1).xlsx"
df_main = pd.read_excel(main_file)

qatar = pd.read_excel("/Users/mac/Desktop/TA3AFA/ASSETS/INFORMATION FOR DEV/qatar_pharma_public_product_list.xlsx")

print("Qatar matches:")
for i, r in qatar.iterrows():
    p = normalize_name(r['Product Name'])
    # check if any in df_main match
    for j, mr in df_main.iterrows():
        mp = normalize_name(mr['PRODUCT NAME'])
        if 'qatar' in str(mr['MANUFACTURER NAME']).lower():
            if p and p in mp:
                print(f"Sub-match: {mr['PRODUCT NAME']} <--> {r['Product Name']}")
