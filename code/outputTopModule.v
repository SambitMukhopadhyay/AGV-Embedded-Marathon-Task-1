module outputTopModule(
    input clk_50MHz,
    input reset_async_n,
    input wire [7:0] rd_data,
    output wire clk_pix,
    output wire [9:0] x,
    output wire [9:0] y,
    output wire vsync_n,
    output wire hsync_n,
    output wire [15:0] colour
);

    wire lock, reset_pix_sync_n, visible, reset_raw_n;

    assign reset_raw_n = reset_async_n & lock;
    wire [15:0] grey565 = {rd_data[7:3], rd_data[7:2], rd_data[7:3]};
    assign colour = visible ? grey565 : 16'h0000;

    pix_pll pll2(clk_50MHz, clk_pix, lock);
    resetSynchronizer pix_sync(clk_pix, reset_raw_n, reset_pix_sync_n);
    vgaTimingGenerator vgaTG(clk_pix, reset_pix_sync_n, hsync_n, vsync_n, visible, x, y);

endmodule