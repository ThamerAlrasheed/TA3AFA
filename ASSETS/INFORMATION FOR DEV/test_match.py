import pandas as pd
import os
import re

folder = "/Users/mac/Desktop/TA3AFA/ASSETS/INFORMATION FOR DEV/"

# Load MOH
moh_file = os.path.join(folder, "MOHDrugPrice_17Nov2025_KSP_only_Composition_Indications (1) (1).xlsx")
moh_df = pd.read_excel(moh_file)
moh_df['PRODUCT_NAME_CLEAN'] = moh_df['PRODUCT NAME'].fillna('').astype(str).str.lower()
moh_df['MANUFACTURER_CLEAN'] = moh_df['MANUFACTURER NAME'].fillna('').astype(str).str.lower()

# Map file to company and column details
files = [
    ("algorithm_lb_products.xlsx", 0, "Product Name", "algorithm"),
    ("almirall_products.xlsx", 0, "Product / Brand", "almirall"),
    ("astrazeneca_medicines.xlsx", 0, "Medicine / Brand", "astrazeneca"),
    ("bayer_drug_information.xlsx", 3, "Input Query", "bayer"),
    ("julphar_general_medicines.xlsx", 0, "Brand", "julphar"),
    ("martindale_pharma_product_list.xlsx", 0, "Product Name", "martindale"),
    ("pfizer_product_list.xlsx", 0, "Product Name", "pfizer"),
    ("qatar_pharma_public_product_list.xlsx", 0, "Product Name", "qatar"),
    ("tabuk_pharmaceuticals_products_scrape.xlsx", 3, "Product Name", "tabuk"),
]

medications = {}
for f, head, col, company in files:
    path = os.path.join(folder, f)
    try:
        df = pd.read_excel(path, header=head)
        prods = df[col].astype(str).tolist()
        cleaned_prods = []
        for p in prods:
            p = re.sub(r'[\u2122\xae]', '', p) # remove TM and R
            p = p.strip().lower()
            if p and p != 'nan':
                cleaned_prods.append(p)
        medications[company] = cleaned_prods
    except Exception as e:
        print(f"Error reading {f}: {e}")

matched_indices = set()

for idx, row in moh_df.iterrows():
    mfg = str(row['MANUFACTURER_CLEAN'])
    prod = str(row['PRODUCT_NAME_CLEAN'])
    
    # Check which company it might be
    possible_companies = [c for c in medications.keys() if c in mfg]
    
    for c in possible_companies:
        for med in medications[c]:
            if med in prod:
                if len(med) < 5 and not re.search(r'\b' + re.escape(med) + r'\b', prod):
                    continue
                matched_indices.add(idx)
                break 

print(f"Total MOH rows: {len(moh_df)}")
print(f"Matched rows: {len(matched_indices)}")
