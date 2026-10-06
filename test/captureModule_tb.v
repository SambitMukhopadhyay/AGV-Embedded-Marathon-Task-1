`timescale 1ns/1ps

module captureModule_tb;

    // ---------- Frame size (shrunk so the waveform is readable) ----------
    localparam PIX   = 4;            // pixels per line
    localparam LINES = 3;            // lines per frame
    localparam TOTAL = PIX * LINES;  // pixels per frame = 12

    // ---------- Signals ----------
    reg        pclk        = 0;
    reg        vsync       = 0;
    reg        href        = 0;
    reg  [7:0] d           = 0;
    reg        en_sync          = 0;
    reg        reset_sync_n  = 0;     // active low

    wire [15:0] pixel;
    wire        pixel_valid;
    wire        frame_start_flag;
    wire [9:0]  pixel_no;
    wire [8:0]  line_no;

    // ---------- DUT ----------
    captureModule dut (
        .pixel            (pixel),
        .pixel_valid      (pixel_valid),
        .frame_start_flag (frame_start_flag),
        .pixel_no         (pixel_no),
        .line_no          (line_no),
        .pclk             (pclk),
        .vsync            (vsync),
        .href             (href),
        .d                (d),
        .en_sync          (en_sync),
        .reset_sync_n     (reset_sync_n)
    );

    // ---------- Clock: 40 ns period ----------
    always #20 pclk = ~pclk;

    // ---------- Expected pixels (an array: 12 entries of 16 bits) ----------
    reg [15:0] exp_pixel [0:TOTAL-1];
    reg [7:0]  hi, lo;
    integer    k;

    // ---------- Camera model ----------
    // Everything changes on the FALLING edge of pclk; the DUT samples on the rising edge.

    task send_line(input integer ln);
        integer x, n;
        begin
            href = 1;
            for (x = 0; x < PIX; x = x + 1) begin
                n = ln * PIX + x;          // pixel number within the frame
                d = 8'hA0 + n;             // high byte
                @(negedge pclk);
                d = 8'h50 + n;             // low byte
                @(negedge pclk);
            end
            href = 0;
            d    = 0;
            repeat (4) @(negedge pclk);    // gap between lines
        end
    endtask

    task send_frame;
        integer ln;
        begin
            vsync = 1;
            repeat (4) @(negedge pclk);    // VSYNC pulse
            vsync = 0;
            repeat (6) @(negedge pclk);    // idle lines before the picture
            for (ln = 0; ln < LINES; ln = ln + 1)
                send_line(ln);
            repeat (6) @(negedge pclk);    // idle lines after the picture
        end
    endtask

    // ---------- Checker ----------
    integer chk_idx  = 0;
    integer errors   = 0;
    integer pix_cnt  = 0;
    integer fs_cnt   = 0;

    always @(posedge pclk) begin
        if (frame_start_flag)
            fs_cnt = fs_cnt + 1;

        if (pixel_valid) begin
            pix_cnt = pix_cnt + 1;
            $display("pixel=%h  pixel_no=%0d  line_no=%0d", pixel, pixel_no, line_no);

            if (pixel    !== exp_pixel[chk_idx] ||
                pixel_no !== (chk_idx % PIX)    ||
                line_no  !== (chk_idx / PIX)) begin
                errors = errors + 1;
                $display("  MISMATCH: expected pixel=%h pixel_no=%0d line_no=%0d",
                         exp_pixel[chk_idx], chk_idx % PIX, chk_idx / PIX);
            end

            if (chk_idx == TOTAL - 1) chk_idx = 0;
            else                      chk_idx = chk_idx + 1;
        end
    end

    // ---------- Main sequence ----------
    initial begin
        $dumpfile("cap.vcd");
        $dumpvars(0, captureModule_tb);

        // Fill the expected array
        for (k = 0; k < TOTAL; k = k + 1) begin
            hi = 8'hA0 + k;
            lo = 8'h50 + k;
            exp_pixel[k] = {hi, lo};
        end

        // Reset, then enable
        repeat (5) @(negedge pclk);
        reset_sync_n = 1;
        repeat (3) @(negedge pclk);
        en_sync = 1;
        repeat (3) @(negedge pclk);

        // Two clean frames
        send_frame;
        send_frame;

        repeat (10) @(negedge pclk);

        $display("----------------------------------------");
        $display("pixels seen : %0d (expected %0d)", pix_cnt, 2 * TOTAL);
        $display("frame starts: %0d (expected 2)", fs_cnt);
        $display("errors      : %0d", errors);
        if (errors == 0 && pix_cnt == 2 * TOTAL && fs_cnt == 2)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");
        $finish;
    end

endmodule