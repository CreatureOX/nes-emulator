import os 

f = os.walk(r'.')

for dirpath, dirnames, filenames in f:
    for filename in filenames:
        if filename.endswith(".pyd") \
            or filename.endswith(".c") \
            or filename.endswith(".h") \
            or filename.endswith(".html"):
            os.remove(dirpath + "\\" + filename)
