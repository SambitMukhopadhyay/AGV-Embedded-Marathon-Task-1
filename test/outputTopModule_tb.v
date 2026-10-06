`timescale 1ns/1ps

// ---------------------------------------------------------------
// Stand-in for the Quartus-generated pix_pll (simulation only).
// Do NOT add this file to the Quartus project, and leave the real
// pix_pll.v out of the simulation.
// 'locked' is controlled by the testbench through lock_en.
// ---------------------------------------------------------------
module pix_pll (
    input  inclk0,
    output reg c0,
    output locked
);
    reg lock_en = 1'b0;
    assign locked = lock_en;

    initial c0 = 1'b0;
    always #20 c0 = ~c0;         // 25 MHz, runs even when "unlocked"
endmodule


module outputTopModule_tb;

    reg         clk_50MHz = 1'b0;
    reg         reset_async_n;
    reg  [15:0] rd_data = 16'd1;

    wire        clk_pix;
    wire [9:0]  x, y;
    wire        vsync_n, hsync_n;
    wire [15:0] colour;

    always #10 clk_50MHz = ~clk_50MHz;

    outputTopModule dut (
        .clk_50MHz    (clk_50MHz),
        .reset_async_n(reset_async_n),
        .rd_data      (rd_data),
        .clk_pix      (clk_pix),
        .x            (x),
        .y            (y),
        .vsync_n      (vsync_n),
        .hsync_n      (hsync_n),
        .colour       (colour)
    );

    integer errors = 0;

    // Stand-in for the buffer: a never-zero value that changes every clock
    always @(posedge clk_pix)
        rd_data <= (rd_data == 16'hFFFF) ? 16'd1 : rd_data + 16'd1;

    // Colour stage: black while not visible, rd_data while visible
    always @(negedge clk_pix) begin
        if (dut.reset_pix_sync_n === 1'b1) begin
            if (colour !== (dut.visible ? rd_data : 16'h0000)) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("ERR: colour %h, visible=%b, rd_data=%h (time %0t)",
                             colour, dut.visible, rd_data, $time);
            end
        end
    end

    // Visible clocks per frame, measured between VSYNC falls
    integer vis_cnt = 0, frames_checked = 0;
    reg started = 1'b0, prev_vs = 1'b1;
    always @(negedge clk_pix) begin
        if (dut.reset_pix_sync_n === 1'b1) begin
            if (!vsync_n && prev_vs) begin
                if (started) begin
                    frames_checked = frames_checked + 1;
                    if (vis_cnt != 640 * 480) begin
                        errors = errors + 1;
                        $display("ERR: %0d visible clocks in a frame, expected %0d",
                                 vis_cnt, 640 * 480);
                    end
                end
                started = 1'b1;
                vis_cnt = 0;
            end
            if (dut.visible) vis_cnt = vis_cnt + 1;
            prev_vs = vsync_n;
        end
    end

    task check_idle(input integer id);
        begin
            if (x !== 10'd0 || y !== 10'd0 || hsync_n !== 1'b1 || vsync_n !== 1'b1 ||
                colour !== 16'h0000 || dut.reset_pix_sync_n !== 1'b0) begin
                errors = errors + 1;
                $display("ERR [%0d]: pixel side not idle (x=%0d y=%0d hs=%b vs=%b colour=%h rst=%b)",
                         id, x, y, hsync_n, vsync_n, colour, dut.reset_pix_sync_n);
            end
        end
    endtask

    initial begin
        // 1. Button held, PLL not locked
        reset_async_n = 1'b0;
        repeat (20) @(negedge clk_50MHz);
        check_idle(1);

        // 2. Button released, PLL still not locked: must stay idle
        reset_async_n = 1'b1;
        repeat (100) @(negedge clk_pix);
        check_idle(2);

        // 3. PLL locks: pixel reset releases exactly two clk_pix edges later
        @(negedge clk_pix);
        dut.pll2.lock_en = 1'b1;
        @(negedge clk_pix);                       // after edge 1
        if (dut.reset_pix_sync_n !== 1'b0) begin
            errors = errors + 1; $display("ERR [3]: reset released after 1 edge");
        end
        @(negedge clk_pix);                       // after edge 2
        if (dut.reset_pix_sync_n !== 1'b1) begin
            errors = errors + 1; $display("ERR [4]: reset not released after 2 edges");
        end

        // 4. Run a bit over two frames: colour stage and visible count are monitored
        repeat (1000000) @(negedge clk_pix);
        if (frames_checked < 1) begin
            errors = errors + 1; $display("ERR [5]: no complete frame was measured");
        end

        // 5. PLL loses lock mid-frame: reset asserts at once, pixel side goes idle
        dut.pll2.lock_en = 1'b0;
        #1;
        if (dut.reset_pix_sync_n !== 1'b0) begin
            errors = errors + 1; $display("ERR [6]: reset did not assert on lost lock");
        end
        repeat (3) @(negedge clk_pix);
        check_idle(7);
        started = 1'b0;

        // 6. Lock returns: the pixel side restarts and x advances
        dut.pll2.lock_en = 1'b1;
        repeat (6) @(negedge clk_pix);
        if (x === 10'd0) begin
            errors = errors + 1; $display("ERR [8]: x did not advance after lock returned");
        end

        // 7. Button pressed mid-frame
        reset_async_n = 1'b0;
        #1;
        if (dut.reset_pix_sync_n !== 1'b0) begin
            errors = errors + 1; $display("ERR [9]: reset did not assert on button press");
        end
        repeat (3) @(negedge clk_pix);
        check_idle(10);
        started = 1'b0;
        reset_async_n = 1'b1;
        repeat (6) @(negedge clk_pix);
        if (x === 10'd0) begin
            errors = errors + 1; $display("ERR [11]: x did not advance after button release");
        end

        $display("Frames checked: %0d, errors: %0d", frames_checked, errors);
        if (errors == 0) $display("PASS");
        else             $display("FAIL");
        $finish;
    end

    // Watchdog (the run needs about 45 ms of simulated time)
    initial begin
        #300000000;
        $display("ERR: watchdog timeout");
        $display("FAIL");
        $finish;
    end

endmodule