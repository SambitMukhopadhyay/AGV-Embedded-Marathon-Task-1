`timescale 1ns/1ps

// Testbench for buffer.v (+ sobel.v)
//
// Each test sends one 640x480 frame: a square of a given RGB565 colour on a
// black background, then reads the stored edge map back and checks it.
//   Square: x = 200..439, y = 160..319  ->  160x120 coords: cols 50..109, rows 40..79
//
// Edge map is shifted +1 col / +1 row (result is written at the incoming
// pixel's address), so the edge lines are:
//   cols 50,51 and 110,111   rows 40,41 and 80,81
//
// Expected edge value = min(255, 2*grey), because
//   Gx = 4*grey,  mag = |Gx|+|Gy| = 4*grey,  half = mag/2 = 2*grey
//   grey = (R8 + 2*G8 + B8) >> 2
//
//   Test 1  white   0xFFFF  grey=255  -> 255 (saturated)   1 pixel / clock
//   Test 2  dark    0x4208  grey= 65  -> 130 (not saturated) camera timing
//   Test 3  red     0xF800  grey= 63  -> 126               1 pixel / clock
//   Test 4  green   0x07E0  grey=127  -> 254               1 pixel / clock
//   Test 5  blue    0x001F  grey= 63  -> 126               camera timing
//
// "Camera timing" = one pixel every 2 pclk cycles (pixel_valid high only on
// the second cycle), like RGB565 where each pixel takes two bytes.

module tb_buffer;

    reg pclk = 0;
    reg clk_pix = 0;
    reg [15:0] pixel = 0;
    reg pixel_valid = 0;
    reg [9:0] pixel_no = 0;
    reg [8:0] line_no = 0;
    reg [9:0] x = 0;
    reg [9:0] y = 0;
    wire [7:0] rd_data;

    buffer dut(pclk, pixel, pixel_valid, pixel_no, line_no, clk_pix, x, y, rd_data);

    always #21 pclk    = ~pclk;      // ~24 MHz
    always #20 clk_pix = ~clk_pix;   // 25 MHz (different clock, on purpose)

    integer errors = 0;
    integer checks = 0;
    integer test_errors;
    integer px, ln, i;

    // ---------- send one frame ----------
    // colour   : RGB565 colour of the square
    // cam_mode : 0 = one pixel per clock, 1 = one pixel per 2 clocks
    task send_frame;
        input [15:0] colour;
        input cam_mode;
        begin
            for (ln = 0; ln < 480; ln = ln + 1) begin
                for (px = 0; px < 640; px = px + 1) begin
                    if (cam_mode) begin
                        // first byte: data not yet complete
                        @(posedge pclk);
                        pixel_valid <= 0;
                        pixel_no    <= px;
                        line_no     <= ln;
                    end
                    @(posedge pclk);
                    pixel_valid <= 1;
                    pixel_no    <= px;
                    line_no     <= ln;
                    if (px >= 200 && px < 440 && ln >= 160 && ln < 320)
                        pixel <= colour;
                    else
                        pixel <= 16'h0000;
                end
                // gap between lines (HREF low)
                repeat (8) begin
                    @(posedge pclk);
                    pixel_valid <= 0;
                end
            end
            @(posedge pclk);
            pixel_valid <= 0;
            repeat (30) @(posedge pclk);   // let the Sobel pipeline flush
        end
    endtask

    // ---------- read one stored pixel (160x120 coords) and compare ----------
    task check;
        input [7:0] c;
        input [6:0] r;
        input [7:0] expected;
        begin
            @(posedge clk_pix);
            x <= c * 4;
            y <= r * 4;
            repeat (3) @(posedge clk_pix);   // read latency + settle
            checks = checks + 1;
            if (rd_data !== expected) begin
                errors = errors + 1;
                test_errors = test_errors + 1;
                $display("  FAIL: col=%0d row=%0d  got=%0d  expected=%0d", c, r, rd_data, expected);
            end
        end
    endtask

    // ---------- all checks for one frame; e = expected edge value ----------
    task check_frame;
        input [7:0] e;
        begin
            // background, interior
            check(10,  10, 0);
            check(150, 110, 0);
            check(80,  60, 0);
            check(70,  50, 0);

            // left edge
            check(48, 60, 0);
            check(49, 60, 0);
            check(50, 60, e);
            check(51, 60, e);
            check(52, 60, 0);

            // right edge (negative gradient -> tests the absolute value)
            check(108, 60, 0);
            check(109, 60, 0);
            check(110, 60, e);
            check(111, 60, e);
            check(112, 60, 0);

            // top edge
            check(80, 38, 0);
            check(80, 39, 0);
            check(80, 40, e);
            check(80, 41, e);
            check(80, 42, 0);

            // bottom edge
            check(80, 78, 0);
            check(80, 79, 0);
            check(80, 80, e);
            check(80, 81, e);
            check(80, 82, 0);

            // forced-zero border
            check(0, 0, 0);
            check(1, 1, 0);
            check(0, 60, 0);
            check(100, 0, 0);

            // sweep along row 60
            for (i = 0; i < 160; i = i + 1) begin
                if (i == 50 || i == 51 || i == 110 || i == 111)
                    check(i, 60, e);
                else
                    check(i, 60, 0);
            end

            // sweep down column 80
            for (i = 0; i < 120; i = i + 1) begin
                if (i == 40 || i == 41 || i == 80 || i == 81)
                    check(80, i, e);
                else
                    check(80, i, 0);
            end
        end
    endtask

    // ---------- run one test ----------
    task run_test;
        input [8*24:1] name;
        input [15:0] colour;
        input cam_mode;
        input [7:0] e;
        begin
            test_errors = 0;
            $display("%0s: colour=0x%04h, expected edge=%0d, %0s", name, colour, e,
                     cam_mode ? "camera timing" : "1 pixel/clock");
            send_frame(colour, cam_mode);
            check_frame(e);
            if (test_errors == 0)
                $display("  -> OK");
            else
                $display("  -> %0d errors", test_errors);
        end
    endtask

    initial begin
        $dumpfile("tb_buffer.vcd");
        $dumpvars(0, tb_buffer);

        repeat (5) @(posedge pclk);

        run_test("Test 1: white",      16'hFFFF, 0, 8'd255);
        run_test("Test 2: dark grey",  16'h4208, 1, 8'd130);
        run_test("Test 3: red",        16'hF800, 0, 8'd126);
        run_test("Test 4: green",      16'h07E0, 0, 8'd254);
        run_test("Test 5: blue",       16'h001F, 1, 8'd126);

        $display("--------------------------------");
        if (errors == 0)
            $display("PASS: %0d checks, 0 errors", checks);
        else
            $display("FAIL: %0d errors out of %0d checks", errors, checks);
        $display("--------------------------------");
        $finish;
    end

endmodule