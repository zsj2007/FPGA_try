// Replay the events read THROUGH AXI in XSim using the actual PS C code.
#include "ccl_axi.h"
#include <assert.h>
#include <stdio.h>
#include <inttypes.h>
static ccl_context ctx;
int main(int argc, char **argv) {
    if (argc != 2) { fprintf(stderr,"usage: test_xsim_events <ccl_axi_events.txt>\n"); return 2; }
    FILE *f=fopen(argv[1],"r");
    if (!f) { perror(argv[1]); return 2; }
    unsigned frames=0;
    uint32_t w[8];
    while (fscanf(f,"%" SCNx32 " %" SCNx32 " %" SCNx32 " %" SCNx32
                    " %" SCNx32 " %" SCNx32 " %" SCNx32 " %" SCNx32,
                    &w[0],&w[1],&w[2],&w[3],&w[4],&w[5],&w[6],&w[7])==8) {
        int status=ccl_ps_feed(&ctx,w);
        if ((w[0]&255)!=3) { assert(status==0); continue; }
        ccl_target t=ccl_ps_select(&ctx,1);
        if (frames==2) { assert(status==-1 && !t.valid); }
        else {
            assert(status==1);
            if(frames==0) {
                assert(t.valid && t.blob.area==6 && t.center_x==1 && t.center_y==0);
                assert(t.blob.min_x==0 && t.blob.max_x==2 && t.blob.min_y==0 && t.blob.max_y==2);
            } else if(frames==1) assert(!t.valid);
            else if(frames==3) assert(t.valid && t.blob.area==32 && t.center_x==3 && t.center_y==1);
            else if(frames==4) assert(t.valid && t.blob.area==24 && t.blob.sum_x==80 && t.blob.sum_y==40);
            else assert(0);
        }
        // Exercise C result packing for the same register map used by RTL.
        volatile uint32_t mmio[24]={0};
        ccl_axi_write_target(mmio,&t,frames);
        assert(mmio[0x50/4]==(uint32_t)t.valid && mmio[0x54/4]==frames && mmio[0x58/4]==1);
        assert((mmio[0x40/4]&65535)==t.center_x && (mmio[0x40/4]>>16)==t.center_y);
        printf("PS C frame %u: status=%d target=%u area=%" PRIu64 "\n",frames,status,t.valid,t.blob.area);
        ++frames;
    }
    fclose(f);
    assert(frames==5);
    puts("PASS: XSim AXI event stream replayed through PS C union/find and result packing");
    return 0;
}
