import re
with open(r'D:\new_FPGA\modules\vision_pipeline\vision_pipeline_video_tb.sv', 'r') as f:
    c = f.read()
c = re.sub(r'INPUT_FILE\s*=\s*\"[^\"]*\"', 'INPUT_FILE  = \"D:/new_FPGA/sim/data/input/out_1_640x400.raw\"', c)
c = re.sub(r'OUTPUT_FILE\s*=\s*\"[^\"]*\"', 'OUTPUT_FILE = \"D:/new_FPGA/sim/data/output/out_1_boxed_640x400.raw\"', c)
c = re.sub(r'DETS_FILE\s*=\s*\"[^\"]*\"', 'DETS_FILE   = \"D:/new_FPGA/sim/data/output/out_1_detections_new.json\"', c)
c = re.sub(r'MAX_FRAMES\s*=\s*\d+', 'MAX_FRAMES = 0', c)
with open(r'D:\new_FPGA\modules\vision_pipeline\vision_pipeline_video_tb.sv', 'w') as f:
    f.write(c)
print('TB updated')
