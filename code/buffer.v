// Assumes 640×480 input from capture
// stores every 4th pixel of every 4th line (160×120)
// reads each stored pixel as a 4×4 block.

module buffer(
    input pclk,
    input wire [15:0] pixel,
    input pixel_valid,
    input [9:0] pixel_no,
    input [8:0] line_no,
    input clk_pix,
    input wire [9:0] x,
    input wire [9:0] y,
    output reg [7:0] rd_data
);

    wire [7:0] r8 = {pixel[15:11], pixel[15:13]};
    wire [7:0] g8 = {pixel[10:5], pixel[10:9]};
    wire [7:0] b8 = {pixel[4:0], pixel[4:2]};

    wire [9:0] greysum = r8 + (g8<<1) + b8;
    wire [7:0] grey = greysum[9:2];

//Every 4th pixel of every4th line is taken into consideration

    wire wen = pixel_valid && !(pixel_no[1] || pixel_no[0] || line_no[1] || line_no[0]);
    wire [7:0] whidx = pixel_no >> 2;             //pixel_no/4
    wire [6:0] wvidx = line_no >> 2;              //col_np/4

//Sobel implementation:

    wire swen;
    wire [14:0] sidx;
    wire [7:0] sdata;

    sobel sb(pclk, wen, whidx, wvidx, grey, swen, sidx, sdata);

    reg [7:0] memory [0:19199];

    always @(posedge pclk)
        if(swen)
            memory[sidx] <= sdata;
    
//For reading on the VGA side:
    wire [7:0] rhidx = x>>2;
    wire [6:0] rvidx = y>>2;
    wire [14:0] ridx = rhidx + rvidx*160;

    always @(posedge clk_pix)
        rd_data <= memory[ridx];

endmodule