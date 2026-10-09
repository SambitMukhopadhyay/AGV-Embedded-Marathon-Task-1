`timescale 1ns/1ps

// ---------------------------------------------------------------
// Stand-ins for the Quartus-generated PLLs (simulation only).
// Do NOT add this file to the Quartus project, and compile it WITHOUT
// the real cam_pll.v / pix_pll.v and WITHOUT the other testbench files
// (outputTopModule_tb.v also defines a pix_pll stand-in).
// Both stand-ins lock by themselves after 500 ns.
// ---------------------------------------------------------------
module cam_pll (
    input  inclk0,
    output reg c0,
    output locked
);
    reg lock_en;
    assign locked = lock_en;
    initial begin
        c0 = 1'b0;
        lock_en = 1'b0;
        #500 lock_en = 1'b1;
    end
    always #20.8333 c0 = ~c0;    // about 24 MHz
endmodule

module pix_pll (
    input  inclk0,
    output reg c0,
    output locked
);
    reg lock_en;
    assign locked = lock_en;
    initial begin
        c0 = 1'b0;
        lock_en = 1'b0;
        #500 lock_en = 1'b1;
    end
    always #20 c0 = ~c0;         // 25 MHz
endmodule


module topModule_tb;

    // ---- Small camera frame (the buffer and capture don't care about the size) ----
    localparam W   = 16;             // pixels per line
    localparam H   = 8;              // lines per frame
    localparam GAP = 8;              // idle PCLK ticks at the end of each line
    localparam LT  = 2 * W + GAP;    // PCLK ticks per camera line
    localparam FL  = H + 7;          // 3 VSYNC lines + 2 idle + H picture + 2 idle

    reg  clk_50MHz = 1'b0;
    reg  reset_async_n;

    // camera stand-in outputs
    reg        vsync = 1'b0;
    reg        href  = 1'b0;
    reg  [7:0] d     = 8'd0;
    wire       pclk;

    tri1       siod;                 // pulled up, like the real SCCB bus
    wire       sioc, cam_reset_n, pwdn, xclk, vsync_n, hsync_n;
    wire [15:0] colour;

    always #10 clk_50MHz = ~clk_50MHz;

    topModule dut (
        .clk_50MHz    (clk_50MHz),
        .reset_async_n(reset_async_n),
        .pclk         (pclk),
        .vsync        (vsync),
        .href         (href),
        .d            (d),
        .siod         (siod),
        .sioc         (sioc),
        .cam_reset_n  (cam_reset_n),
        .pwdn         (pwdn),
        .xclk         (xclk),
        .vsync_n      (vsync_n),
        .hsync_n      (hsync_n),
        .colour       (colour)
    );

    // Shorten the long waits (only the testbench does this)
    defparam dut.iTM.cARC.WAIT_CYCLES_AFTER_RESET = 20;
    defparam dut.iTM.cARC.WAIT_CYCLES_AFTER_PWDN  = 5;
    defparam dut.iTM.s.WAIT_COUNT                 = 20;

    integer errors = 0;

    // ---- Colour of camera pixel (c, r). Never zero for kept pixels. ----
    function [15:0] pix_f(input integer c, input integer r);
        begin
            pix_f = c * 7 + r * 13 + 16'h1234;
        end
    endfunction

    // ---- Camera stand-in: PCLK = XCLK, but only while awake (RESET high, PWDN low) ----
    assign pclk = (cam_reset_n === 1'b1 && pwdn === 1'b0) ? xclk : 1'b0;

    integer tick = 0, line = FL - 1, cam_frames = 0;
    reg [15:0] pv;

    always @(negedge pclk or negedge cam_reset_n) begin
        if (cam_reset_n !== 1'b1) begin
            tick = 0;
            line = FL - 1;
            vsync <= 1'b0;
            href  <= 1'b0;
            d     <= 8'd0;
        end
        else begin
            if (tick == LT - 1) begin
                tick = 0;
                line = (line == FL - 1) ? 0 : line + 1;
            end
            else begin
                tick = tick + 1;
            end
            if (line == 0 && tick == 0) cam_frames = cam_frames + 1;

            vsync <= (line < 3);
            if (line >= 5 && line < 5 + H && tick < 2 * W) begin
                pv = pix_f(tick / 2, line - 5);
                href <= 1'b1;
                d    <= (tick % 2 == 0) ? pv[15:8] : pv[7:0];   // high byte first
            end
            else begin
                href <= 1'b0;
                d    <= 8'd0;
            end
        end
    end

    // ---- Monitor 1: power-up order at the camera pins ----
    always @(posedge cam_reset_n) begin
        if (pwdn !== 1'b0) begin
            errors = errors + 1;
            $display("ERR: cam_reset_n rose while PWDN was still high");
        end
    end

    // ---- Monitor 2: SCCB writes (decodes 3-byte writes, ignores the ACK slot) ----
    reg        sccb_active = 1'b0;
    integer    sccb_bit = 0, sccb_writes = 0;
    reg        first_flag = 1'b1;
    reg [7:0]  sb0, sb1, sb2;

    always @(negedge siod) begin
        #1;                                          // ignore SIOD moving as SIOC falls
        if (sioc === 1'b1 && siod === 1'b0) begin    // start marker
            if (dut.iTM.cam_ready !== 1'b1) begin
                errors = errors + 1;
                $display("ERR: SCCB start before cam_ready");
            end
            sccb_active = 1'b1;
            sccb_bit = 0;
            sb0 = 8'd0; sb1 = 8'd0; sb2 = 8'd0;
        end
    end

    always @(posedge sioc) begin
        if (sccb_active) begin
            if (sccb_bit % 9 != 8) begin             // 9th slot of each byte is the ACK
                case (sccb_bit / 9)
                    0: sb0 = {sb0[6:0], siod};
                    1: sb1 = {sb1[6:0], siod};
                    2: sb2 = {sb2[6:0], siod};
                endcase
            end
            sccb_bit = sccb_bit + 1;
        end
    end

    always @(posedge siod) begin
        #1;
        if (sccb_active && sioc === 1'b1 && siod === 1'b1) begin   // stop marker
            sccb_active = 1'b0;
            // 27 bit pulses (3 bytes x 8 data + ACK) plus the SIOC rise of the stop
            // marker itself, which is counted before SIOD rises: 28 in total
            if (sccb_bit != 28) begin
                errors = errors + 1;
                $display("ERR: SCCB write had %0d SIOC rises, expected 28 (27 bits + stop)", sccb_bit);
            end
            else begin
                sccb_writes = sccb_writes + 1;
                if (first_flag) begin                // first write after reset = soft reset
                    if (sb0 !== 8'h42 || sb1 !== 8'h12 || sb2 !== 8'h80) begin
                        errors = errors + 1;
                        $display("ERR: first SCCB write was %h %h %h, expected 42 12 80",
                                 sb0, sb1, sb2);
                    end
                    first_flag = 1'b0;
                end
            end
        end
    end

    // ---- Monitor 3: capture output (checked on PCLK, away from its edge) ----
    integer valid_total = 0, pix_errors = 0;
    always @(negedge pclk) begin
        if (dut.pixel_valid === 1'b1) begin
            valid_total = valid_total + 1;
            if (dut.iTM.en_pclk_sync !== 1'b1) begin
                errors = errors + 1;
                $display("ERR: pixel_valid while en was low");
            end
            if (dut.pixel_no >= W || dut.line_no >= H ||
                dut.pixel !== pix_f(dut.pixel_no, dut.line_no)) begin
                errors = errors + 1;
                pix_errors = pix_errors + 1;
                if (pix_errors <= 10)
                    $display("ERR: captured pixel no=%0d line=%0d value=%h expected=%h",
                             dut.pixel_no, dut.line_no, dut.pixel,
                             pix_f(dut.pixel_no, dut.line_no));
            end
        end
    end

    // ---- Monitor 4: VGA pins ----
    // colour at the pins belongs to the x,y of ONE clock earlier, same as visible
    reg [9:0] px = 10'd0, py = 10'd0;
    reg       have_prev = 1'b0, check_on = 1'b0;
    integer   region_checks = 0, vga_errors = 0;

    always @(negedge dut.clk_pix) begin
        if (dut.oTM.reset_pix_sync_n === 1'b1) begin
            if (dut.oTM.visible !== 1'b1 && colour !== 16'h0000) begin
                errors = errors + 1;
                $display("ERR: colour %h is not black outside the visible area", colour);
            end
            // Stored camera pixels sit in the top-left 16 x 8 corner, each as a 4x4 block
            if (check_on && have_prev && dut.oTM.visible === 1'b1 && px < 16 && py < 8) begin
                region_checks = region_checks + 1;
                if (colour !== pix_f(4 * (px / 4), 4 * (py / 4))) begin
                    errors = errors + 1;
                    vga_errors = vga_errors + 1;
                    if (vga_errors <= 10)
                        $display("ERR: VGA (%0d,%0d) colour %h expected %h",
                                 px, py, colour, pix_f(4 * (px / 4), 4 * (py / 4)));
                end
            end
        end
        px = dut.x;
        py = dut.y;
        have_prev = 1'b1;
    end

    // ---- Helpers ----
    task wait_config_done(input integer limit);
        integer i;
        begin
            i = 0;
            while (dut.iTM.config_done !== 1'b1 && i < limit) begin
                @(negedge clk_50MHz);
                i = i + 1;
            end
            if (dut.iTM.config_done !== 1'b1) begin
                errors = errors + 1;
                $display("ERR: timeout waiting for config_done");
            end
        end
    endtask

    task wait_en(input integer limit);
        integer i;
        begin
            i = 0;
            while (dut.iTM.en_pclk_sync !== 1'b1 && i < limit) begin
                @(negedge clk_50MHz);
                i = i + 1;
            end
            if (dut.iTM.en_pclk_sync !== 1'b1) begin
                errors = errors + 1;
                $display("ERR: timeout waiting for en");
            end
        end
    endtask

    // en is up: capture should start at the next VSYNC and deliver full frames
    task run_and_check_frames(input integer id);
        integer before;
        begin
            before = valid_total;
            repeat (3) @(posedge vsync);
            if (valid_total - before < 2 * W * H) begin
                errors = errors + 1;
                $display("ERR [%0d]: only %0d valid pixels in two camera frames, expected %0d",
                         id, valid_total - before, 2 * W * H);
            end
            region_checks = 0;
            check_on = 1'b1;
            @(negedge vsync_n);              // from here on, a full VGA frame is checked
            @(negedge vsync_n);
            check_on = 1'b0;
            if (region_checks < 16 * 8) begin
                errors = errors + 1;
                $display("ERR [%0d]: only %0d VGA pixels were checked", id, region_checks);
            end
        end
    endtask

    // ---- Main test ----
    initial begin
        reset_async_n = 1'b1;
        #5 reset_async_n = 1'b0;
        repeat (20) @(negedge clk_50MHz);
        reset_async_n = 1'b1;

        // A. Normal start-up: camera wake-up, SCCB configuration, capture, display
        wait_config_done(5000000);
        if (sccb_writes < 1) begin
            errors = errors + 1;
            $display("ERR: no SCCB write was seen before config_done");
        end
        wait_en(100);
        run_and_check_frames(1);

        // B. Button pressed while running: everything restarts and works again
        reset_async_n = 1'b0;
        first_flag = 1'b1;                   // next first write must again be the soft reset
        repeat (10) @(negedge clk_50MHz);
        if (pwdn !== 1'b1 || cam_reset_n !== 1'b0 ||
            dut.iTM.cam_ready !== 1'b0 || dut.iTM.config_done !== 1'b0) begin
            errors = errors + 1;
            $display("ERR [2]: not back in reset (pwdn=%b cam_reset_n=%b cam_ready=%b config_done=%b)",
                     pwdn, cam_reset_n, dut.iTM.cam_ready, dut.iTM.config_done);
        end
        reset_async_n = 1'b1;
        wait_config_done(5000000);
        wait_en(100);
        run_and_check_frames(3);

        $display("SCCB writes seen: %0d, camera frames: %0d, valid pixels: %0d",
                 sccb_writes, cam_frames, valid_total);
        $display("Errors: %0d", errors);
        if (errors == 0) $display("PASS");
        else             $display("FAIL");
        $finish;
    end

    // Watchdog
    initial begin
        #1000000000;
        $display("ERR: watchdog timeout");
        $display("FAIL");
        $finish;
    end

endmodule
