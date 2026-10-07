
import numpy as np, cv2, os
W,H,FRAMES=640,400,677
raw=np.fromfile(r'D:\new_FPGA\sim\data\output\vid_2727_boxed_640x400.raw',dtype=np.uint8)
data=raw[:W*H*FRAMES].reshape(FRAMES,H,W)
print(f'Frame 0: min={data[0].min()} max={data[0].max()}')
fourcc=cv2.VideoWriter_fourcc(*'avc1')
out=cv2.VideoWriter(r'D:\new_FPGA\sim\data\output\vid_2727_boxed.mp4',fourcc,30,(W,H),True)
for i in range(FRAMES):
    out.write(cv2.cvtColor(data[i],cv2.COLOR_GRAY2BGR))
    if i%100==0: print(f'Frame {i}')
out.release()
print(f'Done: {os.path.getsize(r"D:\\new_FPGA\\sim\\data\\output\\vid_2727_boxed.mp4")/1024/1024:.1f}MB')
