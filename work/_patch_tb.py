import re
tb_path = r"D:\new_FPGA\modules\vision_pipeline\vision_pipeline_video_tb.sv"
with open(tb_path, "r", encoding="utf-8") as f:
    c = f.read()
c = re.sub(r'INPUT_FILE\s*=\s*"[^"]*"', 'INPUT_FILE  = "D:/new_FPGA/sim/data/input/vid_2727_640x400.raw"', c)
c = re.sub(r'OUTPUT_FILE\s*=\s*"[^"]*"', 'OUTPUT_FILE = "D:/new_FPGA/sim/data/output/vid_2727_boxed_640x400.raw"', c)
c = re.sub(r'DETS_FILE\s*=\s*"[^"]*"', 'DETS_FILE   = "D:/new_FPGA/sim/data/output/vid_2727_dets.json"', c)
with open(tb_path, "w", encoding="utf-8") as f:
    f.write(c)
print("TB paths updated")
