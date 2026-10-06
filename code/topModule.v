module topModule(
    input clk_50MHz,
    input reset_async_n,
    input pclk,
    input vsync,
    input href,
    input wire [7:0] d,
    inout siod,
    output sioc,
    output cam_reset_n,
    output pwdn,
    output xclk,
    output vsync_n,
    output hsync_n,
    output wire [15:0] colour
);

    wire pixel_valid, clk_pix;
    wire [15:0] pixel, rd_data;
    wire [9:0] pixel_no, x, y;
    wire [8:0] line_no;

    inputTopModule iTM(clk_50MHz, reset_async_n, pclk, vsync, href, d, siod, sioc, xclk, cam_reset_n, pwdn, pixel, pixel_valid, pixel_no, line_no);
    outputTopModule oTM(clk_50MHz, reset_async_n, rd_data, clk_pix, x, y, vsync_n, hsync_n, colour);
    buffer b(pclk, pixel, pixel_valid, pixel_no, line_no, clk_pix, x, y, rd_data);

endmodule