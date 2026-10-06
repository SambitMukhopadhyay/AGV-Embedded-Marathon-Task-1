`timescale 1ns/1ps

module sccbMaster_tb;

    // ---------- Signals ----------
    reg        clk_50MHz = 0;
    reg  [7:0] reg_addr  = 8'h00;
    reg  [7:0] reg_data  = 8'h00;
    reg        reset_n   = 0;
    reg        start     = 0;
    wire       siod;
    wire       busy, done, sioc;

    // Pull-up on SIOD: a released line reads 1, like the real bus
    pullup (siod);

    // ---------- Bookkeeping (declared early, used by tasks and monitors) ----------
    integer errors = 0;
    integer frames = 0;      // complete writes decoded
    integer dones  = 0;      // done pulses seen
    integer ack_bad = 0;     // ACK slots where SIOD was not released
    reg [7:0] exp_addr = 0, exp_data = 0;

    // ---------- DUT ----------
    sccbMaster dut (
        .clk_50MHz (clk_50MHz),
        .reg_addr  (reg_addr),
        .reg_data  (reg_data),
        .reset_n   (reset_n),
        .start     (start),
        .siod      (siod),
        .busy      (busy),
        .done      (done),
        .sioc      (sioc)
    );

    // ---------- 50 MHz clock ----------
    always #10 clk_50MHz = ~clk_50MHz;

    // ---------- Camera-side monitor ----------
    reg        in_frame = 0;
    integer    bit_cnt  = 0;
    integer    byte_cnt = 0;
    reg  [7:0] shreg    = 0;
    reg  [7:0] rx [0:2];

    // START: SIOD falls while SIOC is high
    always @(negedge siod) begin
        if (sioc === 1'b1) begin
            in_frame = 1;
            bit_cnt  = 0;
            byte_cnt = 0;
        end
    end

    // Sample SIOD on every SIOC rising edge: 8 data bits, then the ACK slot
    always @(posedge sioc) begin
        if (in_frame && byte_cnt < 3) begin
            if (bit_cnt < 8) begin
                shreg   = {shreg[6:0], siod};
                bit_cnt = bit_cnt + 1;
            end else begin
                if (siod !== 1'b1) ack_bad = ack_bad + 1;  // released line must read 1
                rx[byte_cnt] = shreg;
                byte_cnt = byte_cnt + 1;
                bit_cnt  = 0;
            end
        end
    end

    // STOP: SIOD rises while SIOC is high, then check the decoded bytes
    always @(posedge siod) begin
        if (sioc === 1'b1 && in_frame) begin
            in_frame = 0;
            frames   = frames + 1;
            $display("[%0d ns] write received: %h %h %h", $time, rx[0], rx[1], rx[2]);
            if (byte_cnt !== 3 || rx[0] !== 8'h42 ||
                rx[1] !== exp_addr || rx[2] !== exp_data) begin
                errors = errors + 1;
                $display("  MISMATCH: expected 42 %h %h", exp_addr, exp_data);
            end
        end
    end

    // Time from busy rising to done: should be about 285 us
    time t_busy = 0;
    time dur;
    always @(posedge busy) t_busy = $time;
    always @(posedge done) begin
        dones = dones + 1;
        dur = $time - t_busy;
        if (dur < 284000 || dur > 288000) begin
            errors = errors + 1;
            $display("  ERROR: write took %0d ns (expected about 285000)", dur);
        end
    end

    // ---------- Stimulus helpers (drive on the falling edge) ----------
    task pulse_start;
        begin
            @(negedge clk_50MHz);
            start = 1;
            @(negedge clk_50MHz);
            start = 0;
            if (busy !== 1'b1) begin
                errors = errors + 1;
                $display("  ERROR: busy did not rise right after start");
            end
        end
    endtask

    task do_write;
        input [7:0] a;
        input [7:0] d;
        input       disturb;   // 1: change the inputs and send a second start mid-write
        begin
            reg_addr = a;  reg_data = d;
            exp_addr = a;  exp_data = d;
            pulse_start;
            if (disturb) begin
                repeat (2000) @(negedge clk_50MHz);   // about 40 us into the write
                reg_addr = 8'hFF;  reg_data = 8'hFF;
                pulse_start;                           // must be ignored
            end
            @(posedge done);
            @(negedge clk_50MHz);
            if (busy !== 1'b0) begin
                errors = errors + 1;
                $display("  ERROR: busy still high after done");
            end
            repeat (4) @(negedge clk_50MHz);
            if (sioc !== 1'b1 || siod !== 1'b1) begin
                errors = errors + 1;
                $display("  ERROR: bus not idle-high after the write");
            end
        end
    endtask

    // ---------- Main sequence ----------
    initial begin
        $dumpfile("sccb.vcd");
        $dumpvars(0, sccbMaster_tb);

        repeat (5) @(negedge clk_50MHz);
        reset_n = 1;
        repeat (3) @(negedge clk_50MHz);

        do_write(8'h12, 8'h80, 0);   // plain write (COM7 soft reset)
        do_write(8'h11, 8'h01, 1);   // inputs changed + extra start mid-write
        do_write(8'h40, 8'hD0, 0);   // back-to-back right after the previous one

        repeat (10) @(negedge clk_50MHz);

        $display("----------------------------------------");
        $display("writes decoded     : %0d (expected 3)", frames);
        $display("done pulses        : %0d (expected 3)", dones);
        $display("ACK slots not free : %0d (expected 0)", ack_bad);
        $display("errors             : %0d", errors);
        if (errors == 0 && frames == 3 && dones == 3 && ack_bad == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");
        $finish;
    end

    // Watchdog
    initial begin
        #3000000;
        $display("TIMEOUT: simulation stuck");
        $finish;
    end

endmodule