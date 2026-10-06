module vgaTimingGenerator#(
    parameter HFPORCH = 16,
    parameter HS = 96,
    parameter HBPORCH = 48,
    parameter VFPORCH = 10,
    parameter VS = 2,
    parameter VBPORCH = 33,
    parameter PIXELS = 640,
    parameter LINES = 480
)(
    input clk_pix,
    input reset_n,
    output reg hsync_n,
    output reg vsync_n,
    output reg visible,
    output reg [$clog2(PIXELS + HFPORCH + HS + HBPORCH)-1:0] x,
    output reg [$clog2(LINES + VFPORCH + VS + VBPORCH)-1:0] y
);

    localparam HSYNC_START = PIXELS + HFPORCH - 1;
    localparam HSYNC_END = PIXELS + HFPORCH + HS - 1;
    localparam VSYNC_START = LINES + VFPORCH - 1;
    localparam VSYNC_END = LINES + VFPORCH + VS - 1;

    always @(posedge clk_pix)
    begin
        if (reset_n == 1'b0)
        begin
            hsync_n <= 1'b1;
            vsync_n <= 1'b1;
            visible <= 1'b0;
            x <= 0;
            y <= 0;
        end

        else
        begin
            visible <= 1'b0;
            hsync_n <= 1'b1;
            vsync_n <= 1'b1;
            x <= x + 1;
            if (x == HSYNC_END + HBPORCH)
            begin
                x <= 0;
                if (y == VSYNC_END + VBPORCH)
                    y <= 0;
                else
                    y <= y + 1;
            end
            if (x >= HSYNC_START && x < HSYNC_END)
                hsync_n <= 1'b0;
            if (y > VSYNC_START && y <= VSYNC_END)
                vsync_n <= 1'b0;
            if (x < PIXELS && y < LINES)
                visible <= 1'b1;
            
        end
    end
endmodule