`timescale 1ns/1ps

module sobelEdgeDetector_tb;

    // ---------- Test settings (small frame so waveforms stay readable) ----------
    localparam W  = 12;               // pixels per line
    localparam H  = 9;                // lines per frame
    localparam T  = 200;              // edge threshold used in this test
    localparam PW = $clog2(W+1);
    localparam LW = $clog2(H+1);

    // ---------- Signals ----------
    reg           pclk        = 0;
    reg           reset_n     = 0;
    reg           pixel_valid = 0;
    reg  [15:0]   pixel       = 0;
    reg  [PW-1:0] pixel_no    = 0;
    reg  [LW-1:0] line_no     = 0;

    wire [PW-1:0] pix_idx;
    wire [LW-1:0] lin_idx;
    wire          edgeValid, isEdge;

    // ---------- DUT ----------
    sobelEdgeDetector #(.PIXELS(W), .LINES(H), .THRESHOLD(T)) dut (
        .pclk       (pclk),
        .reset_n    (reset_n),
        .pixel      (pixel),
        .pixel_valid(pixel_valid),
        .pixel_no   (pixel_no),
        .line_no    (line_no),
        .pix_idx    (pix_idx),
        .lin_idx    (lin_idx),
        .edgeValid  (edgeValid),
        .isEdge     (isEdge)
    );

    always #10 pclk = ~pclk;

    // ---------- Frame under test and the reference model ----------
    reg     [15:0] img      [0:W*H-1];
    integer        gray     [0:W*H-1];
    reg            exp_edge [0:W*H-1];
    reg            seen     [0:W*H-1];

    integer errors = 0;
    integer outs   = 0;               // outputs flagged valid in the current frame
    integer n_exp_edges = 0;
    integer seed = 123;
    reg     monitor_on = 0;

    // RGB565 -> 8-bit gray, same integer formula as the design: (R + 2G + B) / 4
    function integer gray_of;
        input [15:0] p;
        reg [7:0] r, g, b;
        reg [9:0] s;
        begin
            r = {p[15:11], p[15:13]};
            g = {p[10:5],  p[10:9]};
            b = {p[4:0],   p[4:2]};
            s = r + (g << 1) + b;
            gray_of = s >> 2;
        end
    endfunction

    // Reference Sobel: |Gx| + |Gy| >= T for every window centre (1..W-2, 1..H-2)
    task compute_expected;
        integer x, y, k, gx, gy, mag;
        begin
            for (k = 0; k < W*H; k = k + 1) begin
                gray[k] = gray_of(img[k]);
                seen[k] = 0;
                exp_edge[k] = 0;
            end
            n_exp_edges = 0;
            for (y = 1; y < H-1; y = y + 1)
                for (x = 1; x < W-1; x = x + 1) begin
                    gx = (gray[(y-1)*W+x+1] + 2*gray[y*W+x+1] + gray[(y+1)*W+x+1])
                       - (gray[(y-1)*W+x-1] + 2*gray[y*W+x-1] + gray[(y+1)*W+x-1]);
                    gy = (gray[(y+1)*W+x-1] + 2*gray[(y+1)*W+x] + gray[(y+1)*W+x+1])
                       - (gray[(y-1)*W+x-1] + 2*gray[(y-1)*W+x] + gray[(y-1)*W+x+1]);
                    mag = ((gx < 0) ? -gx : gx) + ((gy < 0) ? -gy : gy);
                    exp_edge[y*W+x] = (mag >= T);
                    if (mag >= T) n_exp_edges = n_exp_edges + 1;
                end
        end
    endtask

    // ---------- Stimulus (drive on the falling edge) ----------
    task send_frame;
        input integer random_gaps;    // 1: random idle cycles between valid pixels
        integer x, y, g, i;
        begin
            for (y = 0; y < H; y = y + 1) begin
                for (x = 0; x < W; x = x + 1) begin
                    pixel = img[y*W+x];  pixel_no = x;  line_no = y;  pixel_valid = 1;
                    @(negedge pclk);
                    pixel_valid = 0;
                    g = random_gaps ? ($urandom % 4) : 1;
                    for (i = 0; i < g; i = i + 1) @(negedge pclk);
                end
                repeat (3) @(negedge pclk);               // gap between lines
            end
        end
    endtask

    task fill_random;
        integer k;
        begin
            for (k = 0; k < W*H; k = k + 1) img[k] = $random(seed);
        end
    endtask

    task fill_step;                   // bright left half, dark right half, one white stripe
        integer x, y;
        begin
            for (y = 0; y < H; y = y + 1)
                for (x = 0; x < W; x = x + 1)
                    img[y*W+x] = (y == H/2) ? 16'hFFFF : ((x < W/2) ? 16'hF7BE : 16'h2104);
        end
    endtask

    // ---------- Monitor: every output flagged valid is checked on arrival ----------
    always @(posedge pclk) if (monitor_on) begin
        if (edgeValid !== 1'b0 && edgeValid !== 1'b1) begin
            errors = errors + 1;
            $display("[%0t] ERROR: edgeValid is X/Z", $time);
        end else if (edgeValid) begin
            outs = outs + 1;
            if (pix_idx < 1 || pix_idx > W-2 || lin_idx < 1 || lin_idx > H-2) begin
                errors = errors + 1;
                $display("[%0t] ERROR: output labelled (%0d,%0d) is not a valid window centre", $time, pix_idx, lin_idx);
            end else begin
                if (seen[lin_idx*W+pix_idx]) begin
                    errors = errors + 1;
                    $display("[%0t] ERROR: window (%0d,%0d) output twice", $time, pix_idx, lin_idx);
                end
                seen[lin_idx*W+pix_idx] = 1;
                if (isEdge !== exp_edge[lin_idx*W+pix_idx]) begin
                    errors = errors + 1;
                    $display("[%0t] ERROR: window (%0d,%0d): isEdge=%b expected %b", $time, pix_idx, lin_idx, isEdge, exp_edge[lin_idx*W+pix_idx]);
                end
            end
        end
    end

    // After a frame: right number of outputs, and only the last window may be missing
    task check_frame;
        input [8*16-1:0] name;
        integer x, y, missing, bad_missing;
        begin
            repeat (6) @(negedge pclk);
            missing = 0;  bad_missing = 0;
            for (y = 1; y < H-1; y = y + 1)
                for (x = 1; x < W-1; x = x + 1)
                    if (!seen[y*W+x]) begin
                        missing = missing + 1;
                        if (!(x == W-2 && y == H-2)) bad_missing = bad_missing + 1;
                    end
            $display("%0s: %0d outputs (expected %0d), %0d edges expected of %0d windows, %0d unexpected missing",
                     name, outs, (W-2)*(H-2)-1, n_exp_edges, (W-2)*(H-2), bad_missing);
            if (outs != (W-2)*(H-2)-1 || bad_missing != 0) errors = errors + 1;
            if (n_exp_edges == 0 || n_exp_edges == (W-2)*(H-2)) begin
                errors = errors + 1;
                $display("  ERROR: test image is trivial (all edge or no edge)");
            end
        end
    endtask

    task start_frame_check;
        integer k;
        begin
            for (k = 0; k < W*H; k = k + 1) seen[k] = 0;
            outs = 0;
        end
    endtask

    // ---------- Main sequence ----------
    initial begin
        $dumpfile("sobel.vcd");
        $dumpvars(0, sobelEdgeDetector_tb);

        // Phase 1: nothing may come out while reset_n is low
        fill_random;  compute_expected;
        repeat (5) @(negedge pclk);
        monitor_on = 1;  start_frame_check;
        send_frame(0);
        repeat (4) @(negedge pclk);
        if (outs != 0) begin
            errors = errors + 1;
            $display("ERROR: %0d outputs while reset_n was low", outs);
        end else $display("reset phase   : no outputs while reset_n is low");

        // Phase 2: random frame, regular pixel spacing
        reset_n = 1;  repeat (3) @(negedge pclk);
        fill_random;  compute_expected;  start_frame_check;
        send_frame(0);
        check_frame("random frame");

        // Phase 3: step/stripe frame, irregular gaps between valid pixels
        fill_step;  compute_expected;  start_frame_check;
        send_frame(1);
        check_frame("step frame");

        // Phase 4: another random frame immediately after, no pause
        fill_random;  compute_expected;  start_frame_check;
        send_frame(1);
        check_frame("back-to-back");

        $display("----------------------------------------");
        $display("errors: %0d", errors);
        if (errors == 0) $display("RESULT: PASS");
        else             $display("RESULT: FAIL");
        $finish;
    end

    // Watchdog
    initial begin
        #2000000;
        $display("TIMEOUT: simulation stuck");
        $finish;
    end

endmodule