import pandas as pd
import os
import re

folder = "/Users/mac/Desktop/TA3AFA/ASSETS/INFORMATION FOR DEV/"
moh_file = os.path.join(folder, "MOHDrugPrice_17Nov2025_KSP_only_Composition_Indications (1) (1).xlsx")
moh_df = pd.read_excel(moh_file)
moh_df['PRODUCT_NAME_CLEAN'] = moh_df['PRODUCT NAME'].fillna('').astype(str).str.lower()
moh_df['MANUFACTURER_CLEAN'] = moh_df['MANUFACTURER NAME'].fillna('').astype(str).str.lower()

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
        cleaned = []
        for p in prods:
            p = re.sub(r'[\u2122\xae]', '', p).strip().lower()
            if p and p != 'nan':
                cleaned.append(p)
        medications[company] = cleaned
    except Exception as e:
        pass

matched_indices = set()

def is_match(med, prod):
    if med in prod:
        return True
    words = [w for w in re.split(r'[^a-z0-9]', med) if len(w) >= 4]
    if len(words) > 0:
        if words[0] in prod:
            return True
    return False

for idx, row in moh_df.iterrows():
    mfg = str(row['MANUFACTURER_CLEAN'])
    prod = str(row['PRODUCT_NAME_CLEAN'])
    
    possible_companies = [c for c in medications.keys() if c in mfg]
    for c in possible_companies:
        for med in medications[c]:
            if is_match(med, prod):
                matched_indices.add(idx)
                break 

print(f"Matched rows: {len(matched_indices)}")
