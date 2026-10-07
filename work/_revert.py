path = r"D:\new_FPGA\modules\blob_analyzer\ccl_analyzer.sv"
with open(path, "r") as f:
    c = f.read()
c = c.replace("MAX_LABELS       = 256", "MAX_LABELS       = 64")
c = c.replace("LABEL_BITS       = 9",   "LABEL_BITS       = 8")
c = c.replace("9'd1", "8'd1")
with open(path, "w") as f:
    f.write(c)
print("Reverted to MAX_LABELS=64, LABEL_BITS=8")
