`timescale 1ns/1ps
module vgaTimingGenerator_tb;

    localparam HFP = 2, HS = 3, HBP = 3, PIX = 8;
    localparam VFP = 2, VS = 2, VBP = 3, LIN = 4;
    localparam HT = PIX + HFP + HS + HBP;   // 16
    localparam VT = LIN + VFP + VS + VBP;   // 11

    reg clk = 0, reset_n = 0;
    wire hsync_n, vsync_n, visible;
    wire [$clog2(HT)-1:0] x;
    wire [$clog2(VT)-1:0] y;

    vgaTimingGenerator #(
        .HFPORCH(HFP), .HS(HS), .HBPORCH(HBP),
        .VFPORCH(VFP), .VS(VS), .VBPORCH(VBP),
        .PIXELS(PIX),  .LINES(LIN)
    ) dut (
        .clk_pix(clk), .reset_n(reset_n),
        .hsync_n(hsync_n), .vsync_n(vsync_n), .visible(visible),
        .x(x), .y(y)
    );

    always #20 clk = ~clk;

    integer errors = 0;
    integer frame_clk = 0, vis_cnt = 0, h_low = 0, v_low = 0;
    integer xmax = 0, ymax = 0, frames = 0;
    reg hs_prev = 1, vs_prev = 1, started = 0;

    // Monitor: samples on the falling edge, away from the DUT's edge
    always @(negedge clk) if (reset_n) begin
        if (x > xmax) xmax = x;
        if (y > ymax) ymax = y;
        if (started) begin
            frame_clk = frame_clk + 1;
            if (visible) vis_cnt = vis_cnt + 1;
        end

        // HSYNC pulse width
        if (!hsync_n) h_low = h_low + 1;
        if (hsync_n && !hs_prev) begin
            if (h_low != HS) begin
                $display("ERR: HSYNC width %0d, expected %0d", h_low, HS);
                errors = errors + 1;
            end
            h_low = 0;
        end

        // VSYNC pulse width (in clocks)
        if (!vsync_n) v_low = v_low + 1;
        if (vsync_n && !vs_prev) begin
            if (v_low != VS * HT) begin
                $display("ERR: VSYNC width %0d clocks, expected %0d", v_low, VS * HT);
                errors = errors + 1;
            end
            v_low = 0;
        end

        // Frame length and visible count, measured between VSYNC falls
        if (!vsync_n && vs_prev) begin
            if (started) begin
                frames = frames + 1;
                if (frame_clk != HT * VT) begin
                    $display("ERR: frame %0d clocks, expected %0d", frame_clk, HT * VT);
                    errors = errors + 1;
                end
                if (vis_cnt != PIX * LIN) begin
                    $display("ERR: %0d visible clocks, expected %0d", vis_cnt, PIX * LIN);
                    errors = errors + 1;
                end
            end
            started = 1;
            frame_clk = 0;
            vis_cnt = 0;
        end

        hs_prev = hsync_n;
        vs_prev = vsync_n;
    end

    initial begin
        repeat (4) @(posedge clk);
        #1 reset_n = 1;

        // reset values
        // (checked while still in reset above: outputs idle)
        repeat (HT * VT * 4 + 10) @(posedge clk);

        // counter ranges
        if (xmax != HT - 1) begin
            $display("ERR: x max %0d, expected %0d", xmax, HT - 1);
            errors = errors + 1;
        end
        if (ymax != VT - 1) begin
            $display("ERR: y max %0d, expected %0d", ymax, VT - 1);
            errors = errors + 1;
        end

        // reset in the middle of a frame
        repeat (37) @(posedge clk);
        #1 reset_n = 0;
        @(posedge clk); #1;
        if (hsync_n !== 1 || vsync_n !== 1 || visible !== 0 || x !== 0 || y !== 0) begin
            $display("ERR: outputs not idle after reset");
            errors = errors + 1;
        end
        started = 0; h_low = 0; v_low = 0; hs_prev = 1; vs_prev = 1;
        repeat (3) @(posedge clk);
        #1 reset_n = 1;
        repeat (HT * VT * 3 + 10) @(posedge clk);

        $display("Frames checked: %0d, errors: %0d", frames, errors);
        if (errors == 0) $display("PASS");
        else             $display("FAIL");
        $finish;
    end

endmodule