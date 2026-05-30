import pandas as pd
import numpy as np
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

def extract_core_name(name):
    if pd.isna(name): return ""
    name = re.sub(r'[^\w\s]', ' ', str(name).lower())
    words = name.split()
    core_words = []
    stopwords = {'tablets', 'tablet', 'capsules', 'capsule', 'syrup', 'injection', 'bottle', 
                 'ampoule', 'solution', 'drops', 'ointment', 'cream', 'vial', 'suspension', 
                 'powder', 'inhaler', 'suppositories', 'suppository', 'sachet', 'spray', 
                 'lotion', 'gel', 'film', 'coated', 'fc', 'sr', 'er', 'mr', 'xr'}
    for w in words:
        if w in stopwords: continue
        if any(char.isdigit() for char in w): continue
        if w in ['mg', 'ml', 'g', 'mcg', 'iu']: continue
        core_words.append(w)
    return " ".join(core_words).strip()

def normalize_name(name):
    if pd.isna(name): return ""
    name = str(name).lower()
    name = re.sub(r'\s+', ' ', name)
    name = re.sub(r'[^\w\s]', '', name)
    return name.strip()

def is_possible_match(m_prod, s_prod):
    c_m = extract_core_name(m_prod)
    c_s = extract_core_name(s_prod)
    if c_m == c_s and c_m: return "exact_core", 1.0
    
    n_m = normalize_name(m_prod)
    n_s = normalize_name(s_prod)
    if n_m == n_s and n_m: return "exact_norm", 1.0
    
    score = SequenceMatcher(None, n_m, n_s).ratio()
    if score >= 0.88:
        return "fuzzy", score
        
    w_m = c_m.split()
    w_s = c_s.split()
    if not w_m or not w_s: return None, 0
    
    # Prefix match or substring match on core words
    min_len = min(len(w_m), len(w_s))
    if w_m[:min_len] == w_s[:min_len] and len(w_m[0]) >= 4:
        return "fuzzy_core", 0.9
        
    if " ".join(w_s) in " ".join(w_m):
        return "subset", 0.85
        
    return None, 0

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

source_data = []

for f_name, mapping in file_mappings.items():
    f_path = os.path.join(folder, f_name)
    if not os.path.exists(f_path): continue
    
    try:
        df_src = pd.read_excel(f_path, header=mapping['header'])
    except Exception as e:
        continue
        
    for idx, row in df_src.iterrows():
        prod_val = row.get(mapping.get('product'))
        if pd.isna(prod_val): continue
        
        entry = {
            'file': f_name,
            'row_idx': idx + mapping['header'] + 2,
            'product': str(prod_val),
            'manufacturer': "",
            'pack_qty': "",
            'ingredients': "",
            'indications': "",
            'interactions': "",
            'wholesale': "",
            'retail': ""
        }
        
        if 'manufacturer' in mapping and mapping['manufacturer'] in row:
            entry['manufacturer'] = str(row[mapping['manufacturer']])
        else:
            mfg = f_name.split('_')[0]
            if mfg.lower() == 'gsk': mfg = 'GSK'
            entry['manufacturer'] = mfg
            
        if 'pack_qty' in mapping and mapping['pack_qty'] in row: entry['pack_qty'] = str(row[mapping['pack_qty']])
        if 'ingredients' in mapping and mapping['ingredients'] in row: entry['ingredients'] = str(row[mapping['ingredients']])
        if 'composition' in mapping and mapping['composition'] in row: entry['ingredients'] = str(row[mapping['composition']])
        if 'indications' in mapping and mapping['indications'] in row: entry['indications'] = str(row[mapping['indications']])
            
        entry['norm_manufacturer'] = normalize_name(entry['manufacturer'])
        source_data.append(entry)

logs = []
stats = {
    'total_scanned': len(df_main), 'total_matched': 0, 'total_cells_filled': 0,
    'exact_matches': 0, 'norm_matches': 0, 'fuzzy_matches': 0, 'ambiguous': 0, 'skipped': 0,
    'filled_cols': {'PRODUCT NAME': 0, 'MANUFACTURER NAME': 0, 'Pack Qty Form': 0, 'Whole /Sale Price KD': 0, 'Retail /Price KD': 0, 'Ingredients (Composition)': 0, 'Indications': 0, 'Interactions': 0}
}

for i, row in df_main.iterrows():
    m_prod = str(row['PRODUCT NAME']) if not pd.isna(row['PRODUCT NAME']) else ""
    m_mfg = str(row['MANUFACTURER NAME']) if not pd.isna(row['MANUFACTURER NAME']) else ""
    
    if not m_prod: continue
        
    norm_m_mfg = normalize_name(m_mfg)
    
    possible_matches = []
    
    for src in source_data:
        mfg_match = False
        if not norm_m_mfg or not src['norm_manufacturer']:
            mfg_match = True
        elif src['norm_manufacturer'] in norm_m_mfg or norm_m_mfg in src['norm_manufacturer']:
            mfg_match = True
        
        if not mfg_match: continue
        
        m_type, m_score = is_possible_match(m_prod, src['product'])
        if m_type:
            possible_matches.append((m_score, m_type, src))

    best_match = None
    match_type = ""
    match_score = 0
    ambiguous = False
    
    if possible_matches:
        top_score = max(m[0] for m in possible_matches)
        top_matches = [m for m in possible_matches if m[0] == top_score]
        
        if len(top_matches) == 1:
            best_match = top_matches[0][2]
            match_type = top_matches[0][1]
            match_score = top_score
        else:
            # check if they're all essentially the same source product duplicated
            unique_prods = set(m[2]['product'] for m in top_matches)
            if len(unique_prods) == 1:
                best_match = top_matches[0][2]
                match_type = top_matches[0][1]
                match_score = top_score
            else:
                ambiguous = True

    if ambiguous:
        stats['ambiguous'] += 1
        logs.append({'main_row': i + 2, 'product_name': m_prod, 'manufacturer_name': m_mfg, 'skipped_reason': 'ambiguous', 'ambiguity_notes': 'Multiple possible matches found.'})
        continue
        
    if not best_match:
        stats['skipped'] += 1
        continue
        
    stats['total_matched'] += 1
    if match_type in ['exact_core', 'exact_norm']: stats['exact_matches'] += 1
    else: stats['fuzzy_matches'] += 1
    
    filled_cols = []
    mapping_to_main = {
        'Pack Qty Form': 'pack_qty', 'Ingredients (Composition)': 'ingredients',
        'Indications': 'indications', 'Interactions': 'interactions',
        'Whole /Sale Price KD': 'wholesale', 'Retail /Price KD': 'retail'
    }
    
    for main_col, src_col in mapping_to_main.items():
        if main_col in df_main.columns:
            if is_missing(row[main_col]) and best_match[src_col] and not is_missing(best_match[src_col]):
                val_to_fill = best_match[src_col]
                if val_to_fill.lower() != "nan":
                    df_main.at[i, main_col] = val_to_fill
                    filled_cols.append(main_col)
                    stats['total_cells_filled'] += 1
                    stats['filled_cols'][main_col] += 1
                
    logs.append({
        'main_row': i + 2, 'product_name': m_prod, 'manufacturer_name': m_mfg,
        'matched_source_file': best_match['file'], 'matched_source_row': best_match['row_idx'],
        'match_type': match_type, 'match_score': match_score, 'columns_filled': ", ".join(filled_cols)
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

df_final = pd.read_excel(output_file)
if df_final.shape != original_shape: print("VALIDATION FAILED: Shape mismatch!")
if df_final.columns.tolist() != original_columns: print("VALIDATION FAILED: Columns mismatch!")

print("Process completed.")
