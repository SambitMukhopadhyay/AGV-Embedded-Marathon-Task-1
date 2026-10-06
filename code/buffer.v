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
    output reg [15:0] rd_data
);

    localparam ROWS = 120, COLS = 160, IDX_WIDTH = $clog2(ROWS * COLS);

    wire wen;
    wire [7:0] whidx, rhidx, rvidx;
    wire [6:0] wvidx;
    wire [IDX_WIDTH-1:0] widx, ridx;
    reg [15:0] memory [0:ROWS*COLS-1];

    assign wen = pixel_valid && !(pixel_no[1] || pixel_no[0] || line_no[1] || line_no[0]);
    assign whidx = pixel_no >> 2;
    assign wvidx = line_no >> 2;
    assign widx = whidx + COLS * wvidx;

    assign rhidx = x >> 2;
    assign rvidx = y >> 2;
    assign ridx = rhidx + COLS * rvidx;

    always @(posedge pclk)
    begin
        if (wen)
            memory[widx] <= pixel;
    end

    always @(posedge clk_pix)
        rd_data <= memory[ridx];
endmodule