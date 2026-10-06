`timescale 1ns/1ps

module sequencer_tb;

    // ---------- Test settings ----------
    localparam TOTAL_ENTRIES = 3;
    localparam WAIT_COUNT    = 300;   // shortened post-reset wait (real value: 500000)
    localparam WRITE_CYCLES  = 100;   // fake SCCB write length; must stay below WAIT_COUNT

    // ---------- Signals ----------
    reg  clk_50MHz = 0;
    reg  reset_n   = 0;
    reg  cam_ready = 0;
    reg  sccb_busy = 0;      // driven by the fake SCCB master below
    reg  sccb_done = 0;

    wire [7:0] reg_addr;
    wire [7:0] reg_data;
    wire       start;
    wire       config_done;

    // ---------- DUT ----------
    sequencer #(
        .TOTAL_ENTRIES (TOTAL_ENTRIES),
        .WAIT_COUNT    (WAIT_COUNT)
    ) dut (
        .clk_50MHz   (clk_50MHz),
        .reset_n     (reset_n),
        .cam_ready   (cam_ready),
        .sccb_busy   (sccb_busy),
        .sccb_done   (sccb_done),
        .reg_addr    (reg_addr),
        .reg_data    (reg_data),
        .start       (start),
        .config_done (config_done)
    );

    // ---------- 50 MHz clock ----------
    always #10 clk_50MHz = ~clk_50MHz;

    // ---------- Expected table (must match the sequencer's ROM) ----------
    reg [15:0] exp_word [0:TOTAL_ENTRIES-1];
    initial begin
        exp_word[0] = {8'h12, 8'h80};
        exp_word[1] = {8'h11, 8'h01};
        exp_word[2] = {8'h40, 8'hD0};
    end

    // ---------- Bookkeeping ----------
    integer errors = 0;
    integer writes = 0;       // writes accepted by the fake master
    integer dones  = 0;       // done pulses sent by the fake master
    integer cnt    = 0;       // fake write length counter
    integer gap01, gap12;
    time    t_start [0:7];    // time each write was accepted
    reg     start_d = 0;

    // ---------- Fake SCCB master + protocol monitors (one block, no races) ----------
    always @(posedge clk_50MHz) begin
        // --- checks on what the sequencer is doing ---
        if (start && start_d) begin
            errors = errors + 1;
            $display("[%0d ns] ERROR: start was high for more than one cycle", $time);
        end
        if (start && sccb_busy) begin
            errors = errors + 1;
            $display("[%0d ns] ERROR: start while the master was busy", $time);
        end
        if (start && !cam_ready) begin
            errors = errors + 1;
            $display("[%0d ns] ERROR: start before cam_ready", $time);
        end
        if (start && config_done) begin
            errors = errors + 1;
            $display("[%0d ns] ERROR: start after config_done", $time);
        end
        if (config_done && (dones != writes || (writes % TOTAL_ENTRIES) != 0 || writes == 0)) begin
            errors = errors + 1;
            $display("[%0d ns] ERROR: config_done high before the last write finished", $time);
        end

        // --- fake master ---
        sccb_done <= 1'b0;
        if (sccb_done) dones = dones + 1;

        if (sccb_busy) begin
            if (cnt == WRITE_CYCLES - 1) begin
                sccb_busy <= 1'b0;
                sccb_done <= 1'b1;
            end
            cnt = cnt + 1;
        end
        else if (start) begin
            $display("[%0d ns] write %0d: addr=%h data=%h", $time, writes, reg_addr, reg_data);
            if ({reg_addr, reg_data} !== exp_word[writes % TOTAL_ENTRIES]) begin
                errors = errors + 1;
                $display("  MISMATCH: expected %h", exp_word[writes % TOTAL_ENTRIES]);
            end
            if (writes < 8) t_start[writes] = $time;
            writes    = writes + 1;
            sccb_busy <= 1'b1;
            cnt       = 0;
        end

        start_d <= start;
    end

    // ---------- Main sequence ----------
    initial begin
        $dumpfile("seq.vcd");
        $dumpvars(0, sequencer_tb);

        // Phase 0: reset released but camera not ready, so nothing should happen
        repeat (5) @(negedge clk_50MHz);
        reset_n = 1;
        repeat (50) @(negedge clk_50MHz);
        if (writes != 0 || start !== 1'b0 || config_done !== 1'b0) begin
            errors = errors + 1;
            $display("ERROR: sequencer active while cam_ready was low");
        end

        // Phase 1: camera ready, full run
        cam_ready = 1;
        @(posedge config_done);
        repeat (50) @(negedge clk_50MHz);       // it must stay high, with no extra writes
        if (writes != TOTAL_ENTRIES || dones != TOTAL_ENTRIES || config_done !== 1'b1) begin
            errors = errors + 1;
            $display("ERROR: after run 1, writes=%0d dones=%0d config_done=%b",
                     writes, dones, config_done);
        end
        gap01 = (t_start[1] - t_start[0]) / 20;   // in clock cycles
        gap12 = (t_start[2] - t_start[1]) / 20;
        $display("gap entry0->entry1: %0d cycles (expect about %0d)", gap01, WAIT_COUNT);
        $display("gap entry1->entry2: %0d cycles (expect about %0d)", gap12, WRITE_CYCLES);
        if (gap01 < WAIT_COUNT || gap01 > WAIT_COUNT + 10) begin
            errors = errors + 1;
            $display("ERROR: wait after the soft reset is the wrong length");
        end
        if (gap12 < WRITE_CYCLES || gap12 > WRITE_CYCLES + 10) begin
            errors = errors + 1;
            $display("ERROR: entry 2 was not sent right after entry 1 finished");
        end

        // Phase 2: reset while finished; it must restart from entry 0
        reset_n = 0;
        repeat (5) @(negedge clk_50MHz);
        if (config_done !== 1'b0) begin
            errors = errors + 1;
            $display("ERROR: config_done not cleared by reset");
        end
        reset_n = 1;
        @(posedge config_done);
        repeat (50) @(negedge clk_50MHz);

        $display("----------------------------------------");
        $display("writes accepted : %0d (expected %0d)", writes, 2 * TOTAL_ENTRIES);
        $display("done pulses     : %0d (expected %0d)", dones,  2 * TOTAL_ENTRIES);
        $display("errors          : %0d", errors);
        if (errors == 0 && writes == 2 * TOTAL_ENTRIES && dones == 2 * TOTAL_ENTRIES)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");
        $finish;
    end

    // Watchdog
    initial begin
        #500000;
        $display("TIMEOUT: simulation stuck");
        $finish;
    end

endmodule