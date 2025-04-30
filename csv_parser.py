python3 -c '
import csv, sys
with open("yourfile.csv", newline="") as f:
    reader = csv.reader(f)
    for i, row in enumerate(reader, 1):
        try:
            pass
        except Exception as e:
            print(f"Line {i}: {e}")
' || echo "Parsing error"


awk -F',' '{
  c=gsub(/"/, "&"); 
  if (c % 2 != 0 || NF != expected) {
    print "Line " NR ": " $0
  }
} NR==1 { expected=NF }' yourfile.csv


awk -F',' 'NR==1 {cols=NF} NF!=cols {print "Line " NR ": " $0}' yourfile.csv
