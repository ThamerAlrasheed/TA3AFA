import pandas as pd
import numpy as np
import glob
import os
import re
from difflib import SequenceMatcher

folder = "/Users/mac/Desktop/TA3AFA/ASSETS/INFORMATION FOR DEV/"
main_file = os.path.join(folder, "MOHDrugPrice_17Nov2025_KSP_only_Composition_Indications (1) (1)(1).xlsx")
output_file = "/Users/mac/Desktop/TA3AFA/ASSETS/INFORMATION FOR DEV/MOHDrugPrice_17Nov2025_KSP_enriched_filled_only.xlsx"
log_file = "/Users/mac/Desktop/TA3AFA/ASSETS/INFORMATION FOR DEV/enrichment_log.xlsx"

def is_missing(val):
    if pd.isna(val): return True
    v = str(val).strip().upper()
    if v in ["", "NAN", "N/M", "NA", "N/A", "UNKNOWN", "NONE", "NULL"]:
        return True
    return False

def normalize_name(name):
    if pd.isna(name): return ""
    name = str(name).lower()
    # remove duplicate spaces
    name = re.sub(r'\s+', ' ', name)
    # remove punctuation noise
    name = re.sub(r'[^\w\s]', '', name)
    return name.strip()

def similarity(a, b):
    return SequenceMatcher(None, a, b).ratio()

# 1. Load Main Workbook
df_main = pd.read_excel(main_file)
original_columns = df_main.columns.tolist()
original_shape = df_main.shape

file_mappings = {
    'pfizer_product_list.xlsx': {'header': 0, 'product': 'Product Name', 'ingredients': 'Active Ingredient / Description', 'manufacturer': 'Company'},
    'ksp_products_drug_list.xlsx': {'header': 0, 'product': 'Product Name', 'manufacturer': 'Manufacturer', 'pack_qty': 'Pack Qty', 'composition': 'Composition', 'indications': 'Indications'},
    'almirall_products.xlsx': {'header': 0, 'product': 'Product / Brand', 'ingredients': 'Active ingredient(s)', 'indications': 'Therapeutic area / condition', 'pack_qty': 'Modality / form'},
    'algorithm_lb_products.xlsx': {'header': 0, 'product': 'Product Name', 'indications': 'Therapeutic Area', 'ingredients': 'Active Ingredient', 'pack_qty': 'Presentation'},
    'bayer_drug_information.xlsx': {'header': 3, 'product': 'Matched Bayer Product', 'indications': 'Field of Activity', 'ingredients': 'Active Ingredient'},
    'julphar_general_medicines.xlsx': {'header': 0, 'product': 'Brand', 'ingredients': 'Generic Name', 'pack_qty': 'Forms', 'indications': 'Therapeutic Area / Type'},
    'martindale_pharma_product_list.xlsx': {'header': 0, 'product': 'Product Name', 'manufacturer': 'Company', 'ingredients': 'Active Ingredient(s)', 'pack_qty': 'Dosage Form'},
    'GSK_PDF_Product_Extraction.xlsx': {'header': 0, 'product': 'Product Name', 'pack_qty': 'Dosage', 'ingredients': 'Ingredients (Composition)', 'indications': 'Indications'},
    'tabuk_pharmaceuticals_products_scrape.xlsx': {'header': 3, 'product': 'Product Name'},
    'qatar_pharma_public_product_list.xlsx': {'header': 0, 'product': 'Product Name', 'pack_qty': 'Description / Pack', 'manufacturer': 'Company'},
    'astrazeneca_medicines.xlsx': {'header': 0, 'product': 'Medicine / Brand', 'ingredients': 'Active Ingredient', 'indications': 'Therapy Area'},
}

# 3. Build index
source_data = []

for f_name, mapping in file_mappings.items():
    f_path = os.path.join(folder, f_name)
    if not os.path.exists(f_path):
        continue
    
    try:
        df_src = pd.read_excel(f_path, header=mapping['header'])
    except Exception as e:
        print(f"Error reading {f_name}: {e}")
        continue
        
    for idx, row in df_src.iterrows():
        prod_val = row.get(mapping.get('product'))
        if pd.isna(prod_val): continue
        
        entry = {
            'file': f_name,
            'row_idx': idx + mapping['header'] + 2, # excel row approx
            'product': str(prod_val),
            'norm_product': normalize_name(prod_val),
            'manufacturer': "",
            'pack_qty': "",
            'ingredients': "",
            'indications': "",
            'interactions': "",
            'wholesale': "",
            'retail': ""
        }
        
        # manufacturer logic
        if 'manufacturer' in mapping and mapping['manufacturer'] in row:
            entry['manufacturer'] = str(row[mapping['manufacturer']])
        else:
            # infer manufacturer from file name
            mfg = f_name.split('_')[0]
            if mfg == 'GSK': mfg = 'GSK'
            entry['manufacturer'] = mfg
            
        if 'pack_qty' in mapping and mapping['pack_qty'] in row:
            entry['pack_qty'] = str(row[mapping['pack_qty']])
            
        if 'ingredients' in mapping and mapping['ingredients'] in row:
            entry['ingredients'] = str(row[mapping['ingredients']])
        if 'composition' in mapping and mapping['composition'] in row:
            entry['ingredients'] = str(row[mapping['composition']])
            
        if 'indications' in mapping and mapping['indications'] in row:
            entry['indications'] = str(row[mapping['indications']])
            
        entry['norm_manufacturer'] = normalize_name(entry['manufacturer'])
        source_data.append(entry)

logs = []
stats = {
    'total_scanned': len(df_main),
    'total_matched': 0,
    'total_cells_filled': 0,
    'exact_matches': 0,
    'norm_matches': 0,
    'fuzzy_matches': 0,
    'ambiguous': 0,
    'skipped': 0,
    'filled_cols': {
        'PRODUCT NAME': 0, 'MANUFACTURER NAME': 0, 'Pack Qty Form': 0, 
        'Whole /Sale Price KD': 0, 'Retail /Price KD': 0, 
        'Ingredients (Composition)': 0, 'Indications': 0, 'Interactions': 0
    }
}

for i, row in df_main.iterrows():
    m_prod = str(row['PRODUCT NAME']) if not pd.isna(row['PRODUCT NAME']) else ""
    m_mfg = str(row['MANUFACTURER NAME']) if not pd.isna(row['MANUFACTURER NAME']) else ""
    
    if not m_prod:
        continue
        
    norm_m_prod = normalize_name(m_prod)
    norm_m_mfg = normalize_name(m_mfg)
    
    # Matching logic
    exact_matches = []
    norm_matches = []
    fuzzy_matches = []
    
    for src in source_data:
        mfg_match = False
        if not norm_m_mfg or not src['norm_manufacturer']:
            mfg_match = True # lenient if one is missing
        elif src['norm_manufacturer'] in norm_m_mfg or norm_m_mfg in src['norm_manufacturer']:
            mfg_match = True
        
        if not mfg_match: continue
        
        if m_prod.lower() == src['product'].lower():
            exact_matches.append(src)
        elif norm_m_prod == src['norm_product']:
            norm_matches.append(src)
        else:
            score = similarity(norm_m_prod, src['norm_product'])
            if score >= 0.88:
                # also check if the first word matches exactly to be safe
                m_words = norm_m_prod.split()
                s_words = src['norm_product'].split()
                if m_words and s_words and m_words[0] == s_words[0]:
                    fuzzy_matches.append((score, src))

    best_match = None
    match_type = ""
    match_score = 0
    ambiguous = False
    
    if len(exact_matches) == 1:
        best_match = exact_matches[0]
        match_type = "exact"
        match_score = 1.0
    elif len(exact_matches) > 1:
        ambiguous = True
    elif len(norm_matches) == 1:
        best_match = norm_matches[0]
        match_type = "normalized"
        match_score = 1.0
    elif len(norm_matches) > 1:
        ambiguous = True
    elif len(fuzzy_matches) == 1:
        best_match = fuzzy_matches[0][1]
        match_type = "fuzzy"
        match_score = fuzzy_matches[0][0]
    elif len(fuzzy_matches) > 1:
        # Check if they are all from the same product effectively
        top_score = max(f[0] for f in fuzzy_matches)
        top_matches = [f[1] for f in fuzzy_matches if f[0] == top_score]
        if len(top_matches) == 1:
            best_match = top_matches[0]
            match_type = "fuzzy"
            match_score = top_score
        else:
            ambiguous = True

    if ambiguous:
        stats['ambiguous'] += 1
        logs.append({
            'main_row': i + 2, 'product_name': m_prod, 'manufacturer_name': m_mfg,
            'skipped_reason': 'ambiguous', 'ambiguity_notes': 'Multiple possible matches found.'
        })
        continue
        
    if not best_match:
        stats['skipped'] += 1
        continue
        
    stats['total_matched'] += 1
    if match_type == 'exact': stats['exact_matches'] += 1
    elif match_type == 'normalized': stats['norm_matches'] += 1
    elif match_type == 'fuzzy': stats['fuzzy_matches'] += 1
    
    # Fill missing
    filled_cols = []
    
    mapping_to_main = {
        'Pack Qty Form': 'pack_qty',
        'Ingredients (Composition)': 'ingredients',
        'Indications': 'indications',
        'Interactions': 'interactions',
        'Whole /Sale Price KD': 'wholesale',
        'Retail /Price KD': 'retail'
    }
    
    for main_col, src_col in mapping_to_main.items():
        if main_col in df_main.columns:
            if is_missing(row[main_col]) and best_match[src_col] and not is_missing(best_match[src_col]) and best_match[src_col] != "nan":
                # Validate we are filling only missing cells
                df_main.at[i, main_col] = best_match[src_col]
                filled_cols.append(main_col)
                stats['total_cells_filled'] += 1
                stats['filled_cols'][main_col] += 1
                
    logs.append({
        'main_row': i + 2, 'product_name': m_prod, 'manufacturer_name': m_mfg,
        'matched_source_file': best_match['file'], 'matched_source_row': best_match['row_idx'],
        'match_type': match_type, 'match_score': match_score,
        'columns_filled': ", ".join(filled_cols)
    })

print("Saving enriched workbook...")
df_main.to_excel(output_file, index=False)

print("Saving log file...")
df_logs = pd.DataFrame(logs)
df_logs.to_excel(log_file, index=False)

print("=== Final Summary ===")
print(f"Total rows scanned: {stats['total_scanned']}")
print(f"Total rows matched: {stats['total_matched']}")
print(f"Total cells filled: {stats['total_cells_filled']}")
print(f"Exact matches: {stats['exact_matches']}")
print(f"Normalized matches: {stats['norm_matches']}")
print(f"Fuzzy matches: {stats['fuzzy_matches']}")
print(f"Ambiguous rows: {stats['ambiguous']}")
print(f"Skipped rows: {stats['skipped']}")
print("Per-column fill counts:", stats['filled_cols'])

# Validations
df_final = pd.read_excel(output_file)
if df_final.shape != original_shape:
    print("VALIDATION FAILED: Shape mismatch!")
if df_final.columns.tolist() != original_columns:
    print("VALIDATION FAILED: Columns mismatch!")

print("Process completed.")
