module sobelEdgeDetector#(
    parameter PIXELS = 640,
    parameter LINES = 480,
    parameter THRESHOLD = 1204
)(
    input pclk,
    input reset_n,
    input wire [15:0] pixel,
    input pixel_valid,
    input [$clog2(PIXELS+1)-1:0] pixel_no,
    input [$clog2(LINES+1)-1:0] line_no,
    output reg [$clog2(PIXELS+1)-1:0] pix_idx,
    output reg [$clog2(LINES+1)-1:0] lin_idx,
    output reg edgeValid,
    output isEdge
);

    reg [7:0] lb1 [0:PIXELS-1];
    reg [7:0] lb2 [0:PIXELS-1];
    reg [7:0] matrix [0:8];

    reg signed [10:0] Gx, Gy; // ranges from -1020 to 1020

    wire [11:0] V = (Gx >= 0) ? ((Gy >= 0) ? (Gx + Gy) : (Gx - Gy)) : ((Gy >= 0) ? (-Gx + Gy) : (-Gx - Gy)); // ranges from 0 to 2040
    assign isEdge = (V >= THRESHOLD) ? 1'b1 : 1'b0;

    wire [7:0] red = {pixel[15:11], pixel[15:13]};
    wire [7:0] green = {pixel[10:5], pixel[10:9]};
    wire [7:0] blue = {pixel[4:0], pixel[4:2]};
    wire [9:0] weighted_sum = red + (green << 1) + blue;
    wire [7:0] grayscale = (weighted_sum >> 2);

    always @(posedge pclk)
    begin
        edgeValid <= 1'b0;

        if (reset_n && pixel_valid)
        begin
            if (line_no == 0)
                lb1[pixel_no] <= grayscale;

            else if (line_no == 1)
                lb2[pixel_no] <= grayscale;

            else 
            begin
                lb1[pixel_no] <= lb2[pixel_no];
                lb2[pixel_no] <= grayscale;
                matrix[0] <= matrix[1];
                matrix[1] <= matrix[2];
                matrix[2] <= lb1[pixel_no];
                matrix[3] <= matrix[4];
                matrix[4] <= matrix[5];
                matrix[5] <= lb2[pixel_no];
                matrix[6] <= matrix[7];
                matrix[7] <= matrix[8];
                matrix[8] <= grayscale;
    
                if (pixel_no >= 3)
                begin
                    edgeValid <= 1'b1;
                    pix_idx <= pixel_no - 2;
                    lin_idx <= line_no - 1;
                end

                else if (pixel_no == 0 && line_no >= 3)
                begin
                    edgeValid <= 1'b1;
                    pix_idx <= PIXELS - 2;
                    lin_idx <= line_no - 2;
                end

                Gx <= matrix[8] - matrix[6] + ((matrix[5] - matrix[3]) << 1) + matrix[2] - matrix[0];
                Gy <= matrix[0] - matrix[6] + ((matrix[1] - matrix[7]) << 1) + matrix[2] - matrix[8];
            end
        end
    end

endmodule