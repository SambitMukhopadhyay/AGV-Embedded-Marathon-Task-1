`timescale 1ns/1ps
module buffer_tb;

    reg         pclk = 1'b0;
    reg         clk_pix = 1'b0;
    reg  [15:0] pixel = 16'd0;
    reg         pixel_valid = 1'b0;
    reg  [9:0]  pixel_no = 10'd0;
    reg  [8:0]  line_no = 9'd0;
    reg  [9:0]  x = 10'd0;
    reg  [9:0]  y = 10'd0;
    wire [15:0] rd_data;

    buffer dut (
        .pclk       (pclk),
        .pixel      (pixel),
        .pixel_valid(pixel_valid),
        .pixel_no   (pixel_no),
        .line_no    (line_no),
        .clk_pix    (clk_pix),
        .x          (x),
        .y          (y),
        .rd_data    (rd_data)
    );

    // Two unrelated clocks
    always #20 pclk    = ~pclk;      // 40 ns period
    always #19 clk_pix = ~clk_pix;   // 38 ns period

    // Every camera position gets its own colour, so a wrong slot, a wrong
    // address or a stray write shows up as a mismatch.
    // (For kept pixels the value can never equal 16'hDEAD: it is always even
    //  while 16'hDEAD - 16'h1234 is odd.)
    function [15:0] colour(input integer c, input integer r);
        begin
            colour = c * 7 + r * 13 + 16'h1234;
        end
    endfunction

    integer c, r;
    integer errors = 0;
    reg [15:0] expected;
    reg        have_expected = 1'b0;

    task check;
        begin
            if (rd_data !== expected) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("ERR: x=%0d y=%0d rd_data=%h expected=%h (time %0t)",
                             x, y, rd_data, expected, $time);
            end
        end
    endtask

    initial begin
        // ---- Write phase: all 640 x 480 positions, one pixel at a time.
        // After every valid pixel comes one NOT-valid cycle with a garbage colour
        // and the position numbers held, like the capture module does.
        // If pixel_valid doesn't gate the write, the garbage overwrites the data.
        for (r = 0; r < 480; r = r + 1) begin
            for (c = 0; c < 640; c = c + 1) begin
                @(negedge pclk);
                pixel_valid = 1'b1;
                pixel_no    = c;
                line_no     = r;
                pixel       = colour(c, r);
                @(negedge pclk);
                pixel_valid = 1'b0;
                pixel       = 16'hDEAD;
            end
        end
        @(negedge pclk);
        pixel_valid = 1'b0;

        // ---- Read phase: x and y change on every clock, as in real use.
        // rd_data must show the pixel for the x,y of exactly ONE clock earlier
        // (one-clock latency). Each stored pixel must appear as a 4x4 block.
        for (r = 0; r < 480; r = r + 1) begin
            for (c = 0; c < 640; c = c + 1) begin
                @(negedge clk_pix);
                if (have_expected) check;
                x = c;
                y = r;
                expected = colour(4 * (c / 4), 4 * (r / 4));
                have_expected = 1'b1;
            end
        end
        @(negedge clk_pix);
        check;

        $display("Errors: %0d", errors);
        if (errors == 0) $display("PASS");
        else             $display("FAIL");
        $finish;
    end

    // Watchdog (the run needs about 40 ms of simulated time)
    initial begin
        #100000000;
        $display("ERR: watchdog timeout");
        $display("FAIL");
        $finish;
    end

endmodule