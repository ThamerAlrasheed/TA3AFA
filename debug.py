import pandas as pd
df = pd.read_excel("/Users/mac/Desktop/TA3AFA/ASSETS/INFORMATION FOR DEV/enrichment_log.xlsx")
print(df.head())
print("Total rows in log:", len(df))
print(df['columns_filled'].value_counts())
