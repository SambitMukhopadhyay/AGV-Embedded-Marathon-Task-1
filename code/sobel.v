module sobel(
    input pclk,
    input wen,
    input [7:0] col,
    input [6:0] row,
    input [7:0] grey,
    output reg out_wen,
    output reg [14:0] sidx,
    output reg [7:0] sdata
);

//Line buffers:
    reg [7:0] lb1 [0:159];
    reg [7:0] lb2 [0:159];

//Reading the input data
    reg v0;
    reg[7:0] col0, grey0;
    reg[6:0] row0;

    always @(posedge pclk) begin
        v0 <= wen;
        if(wen) begin
            col0 <= col;
            row0 <= row;
            grey0 <= grey;
        end
    end

//Getting the line buffer reading:
    reg v1;
    reg[7:0] col1, grey1, rd1, rd2;
    reg[6:0] row1;

    always @(posedge pclk) begin
        rd1 <= lb1[col0];
        rd2 <= lb2[col0];
        grey1 <= grey0;
        col1 <= col0;
        row1 <= row0;
        v1 <= v0;
    end

//Updating the line buffers, and the window
    reg v2;
    reg [7:0] col2;
    reg [6:0] row2;
    reg [7:0] w00, w01, w02;    //row-2
    reg [7:0] w10, w11, w12;    //row-1
    reg [7:0] w20, w21, w22;    //present row

    always @(posedge pclk) begin
        v2 <= v1;
        col2 <= col1;
        row2 <= row1;

        if(v1) begin

            lb2[col1] <= rd1;
            lb1[col1] <= grey1;

            w00 <= w01;
            w01 <= w02;
            w02 <= rd2;
            w10 <= w11;
            w11 <= w12;
            w12 <= rd1;
            w20 <= w21;
            w21 <= w22;
            w22 <= grey1;
        end
    end

    wire signed [10:0] p0 = {3'b0, w00};
    wire signed [10:0] p1 = {3'b0, w01};
    wire signed [10:0] p2 = {3'b0, w02};
    wire signed [10:0] p3 = {3'b0, w10};
    wire signed [10:0] p5 = {3'b0, w12};
    wire signed [10:0] p6 = {3'b0, w20};
    wire signed [10:0] p7 = {3'b0, w21};
    wire signed [10:0] p8 = {3'b0, w22};

    reg signed [10:0] gx, gy;
    reg v3, border3;
    reg [14:0] idx;

    always @(posedge pclk) begin
        gx      <= (p2 + (p5 <<< 1) + p8) - (p0 + (p3 <<< 1) + p6);
        gy      <= (p0 + (p1 <<< 1) + p2) - (p6 + (p7 <<< 1) + p8);
        border3 <= (col2 < 2) || (row2 < 2);   // window not full yet
        idx    <= col2 + 160 * row2;
        v3      <= v2;
    end

    wire [10:0] ax = gx[10] ? (~gx + 11'd1) : gx;
    wire [10:0] ay = gy[10] ? (~gy + 11'd1) : gy;
    wire [11:0] mag = ax + ay;
    wire [10:0] half = mag[11:1];
    wire [7:0] strength = (half > 11'd255) ? 8'd255 : half[7:0];

    always @(posedge pclk) begin
        out_wen  <= v3;
        sidx  <= idx;
        sdata <= border3 ? 8'd0 : strength;
        // sdata <= border3 ? 8'd0 : (mag > 12'd150) ? 8'd255 : 8'd0;
    end

endmodule
