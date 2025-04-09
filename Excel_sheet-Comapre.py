import pandas as pd

# Load the Excel file (change the file name as needed)
file_path = 'your_excel_file.xlsx'  # Replace with your actual file path
xls = pd.ExcelFile(file_path)

# Read both sheets
legacy_df = xls.parse('Legacy')
sscd_df = xls.parse('SSCD')

# Drop completely blank rows (optional, but recommended)
legacy_df = legacy_df.dropna(how='all')
sscd_df = sscd_df.dropna(how='all')

# Convert each row to a tuple for set comparison
legacy_rows = set(tuple(row) for row in legacy_df.values)
sscd_rows = set(tuple(row) for row in sscd_df.values)

# Perform comparison
common_rows = legacy_rows & sscd_rows
only_in_legacy = legacy_rows - sscd_rows
only_in_sscd = sscd_rows - legacy_rows

# Display summary
print(f"✅ Common rows: {len(common_rows)}")
print(f"❌ Rows only in Legacy: {len(only_in_legacy)}")
print(f"❌ Rows only in SSCD: {len(only_in_sscd)}")

# Optional: Write differences to Excel
output = pd.ExcelWriter('comparison_result.xlsx', engine='xlsxwriter')
pd.DataFrame(list(only_in_legacy)).to_excel(output, sheet_name='Only_in_Legacy', index=False, header=False)
pd.DataFrame(list(only_in_sscd)).to_excel(output, sheet_name='Only_in_SSCD', index=False, header=False)
pd.DataFrame(list(common_rows)).to_excel(output, sheet_name='Common_Rows', index=False, header=False)
output.save()
print("📄 Results saved to 'comparison_result.xlsx'")
