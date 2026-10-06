module inputTopModule(
    input clk_50MHz,
    input reset_async_n,
    input pclk,
    input vsync,
    input href,
    input wire [7:0] d,
    inout siod,
    output sioc,
    output xclk,
    output cam_reset_n,
    output pwdn,
    output [15:0] pixel,
    output pixel_valid,
    output [9:0] pixel_no,
    output [8:0] line_no
);
    
    wire reset_50MHz_sync_n, frame_start_flag, en_pclk_sync, reset_pclk_sync_n, sccb_busy, sccb_done;
    wire start, config_done, cam_ready, sys_reset_n;
    wire[7:0] reg_addr, reg_data;

    resetSynchronizer clk_50MHz_sync(clk_50MHz, reset_async_n, reset_50MHz_sync_n);
    resetSynchronizer pclk_sync(pclk, sys_reset_n, reset_pclk_sync_n);
    enSynchronizer eS(pclk, config_done, reset_pclk_sync_n, en_pclk_sync);
    captureModule cM(pixel, pixel_valid, frame_start_flag, pixel_no, line_no, pclk, vsync, href, d, en_pclk_sync, reset_pclk_sync_n);
    sccbMaster sM(clk_50MHz, reg_addr, reg_data, sys_reset_n, start, siod, sccb_busy, sccb_done, sioc);
    sequencer s(clk_50MHz, sys_reset_n, cam_ready, sccb_busy, sccb_done, reg_addr, reg_data, start, config_done);
    clockAndResetControl cARC(clk_50MHz, reset_50MHz_sync_n, xclk, cam_reset_n, pwdn, cam_ready, sys_reset_n);

endmodule