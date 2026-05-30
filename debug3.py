import pandas as pd
df = pd.read_excel("/Users/mac/Desktop/TA3AFA/ASSETS/INFORMATION FOR DEV/qatar_pharma_public_product_list.xlsx")
print(df[df['Product Name'].str.contains('5% Dextrose and 0.18% Sodium', case=False, na=False)])
