`timescale 1ns/1ps

// ---------------------------------------------------------------
// Stand-in for the Quartus-generated cam_pll (simulation only).
// Do NOT add this file to the Quartus project. In simulation, compile
// this file and leave out the real cam_pll.v.
// 'locked' is controlled by the testbench through lock_en.
// ---------------------------------------------------------------
module cam_pll (
    input  inclk0,
    output reg c0,
    output locked
);
    reg lock_en = 1'b0;          // low from time zero
    assign locked = lock_en;

    initial c0 = 1'b0;
    always #20.8333 c0 = ~c0;    // roughly 24 MHz
endmodule


module clockAndResetControl_tb;

    // Shortened waits so the run is fast (keep both >= 2)
    localparam W_RST  = 500000;
    localparam W_PWDN = 1000;
    localparam LIMIT = W_PWDN + W_RST + 200;

    reg clk     = 1'b0;
    reg reset_n = 1'b0;

    wire xclk, cam_reset_n, pwdn, cam_ready, sys_reset_n;

    clockAndResetControl #(
        .WAIT_CYCLES_AFTER_RESET(W_RST),
        .WAIT_CYCLES_AFTER_PWDN (W_PWDN)
    ) dut (
        .clk_50MHz  (clk),
        .reset_n    (reset_n),
        .xclk       (xclk),
        .cam_reset_n(cam_reset_n),
        .pwdn       (pwdn),
        .cam_ready  (cam_ready),
        .sys_reset_n(sys_reset_n)
    );

    always #10 clk = ~clk;       // 50 MHz, 20 ns period

    integer errors = 0;
    integer t_pwdn = 0, t_rst = 0, t_ready = 0;

    // Event timestamps (all changes happen right after a rising clock edge)
    always @(negedge pwdn) begin
        t_pwdn = $time;
        if (cam_reset_n !== 1'b0) begin
            $display("ERR: PWDN fell while cam_reset_n was not low");
            errors = errors + 1;
        end
    end

    always @(posedge cam_reset_n) begin
        t_rst = $time;
        if (pwdn !== 1'b0) begin
            $display("ERR: cam_reset_n rose while PWDN was still high");
            errors = errors + 1;
        end
    end

    always @(posedge cam_ready) begin
        t_ready = $time;
        if (cam_reset_n !== 1'b1) begin
            $display("ERR: cam_ready rose while cam_reset_n was low");
            errors = errors + 1;
        end
    end

    // Everything is sampled on the falling edge, away from the DUT's edge
    task tick(input integer n);
        begin
            repeat (n) @(negedge clk);
        end
    endtask

    task check_idle(input integer id);
        begin
            if (pwdn !== 1'b1 || cam_reset_n !== 1'b0 ||
                sys_reset_n !== 1'b0 || cam_ready !== 1'b0) begin
                $display("ERR [%0d]: outputs not idle (pwdn=%b cam_reset_n=%b sys_reset_n=%b cam_ready=%b)",
                         id, pwdn, cam_reset_n, sys_reset_n, cam_ready);
                errors = errors + 1;
            end
        end
    endtask

    task wait_ready(input integer limit);
        integer i;
        begin
            i = 0;
            while (cam_ready !== 1'b1 && i < limit) begin
                @(negedge clk);
                i = i + 1;
            end
            if (cam_ready !== 1'b1) begin
                $display("ERR: timeout waiting for cam_ready");
                errors = errors + 1;
            end
        end
    endtask

    task wait_cam_reset_release(input integer limit);
        integer i;
        begin
            i = 0;
            while (cam_reset_n !== 1'b1 && i < limit) begin
                @(negedge clk);
                i = i + 1;
            end
            if (cam_reset_n !== 1'b1) begin
                $display("ERR: timeout waiting for cam_reset_n");
                errors = errors + 1;
            end
        end
    endtask

    // PWDN falls first, RESET rises W_PWDN+1 clocks later,
    // cam_ready rises W_RST+1 clocks after that.
    task check_sequence(input integer id);
        begin
            if (!(t_pwdn < t_rst && t_rst < t_ready)) begin
                $display("ERR [%0d]: wrong order of events", id);
                errors = errors + 1;
            end
            if ((t_rst - t_pwdn) / 20 != W_PWDN + 1) begin
                $display("ERR [%0d]: PWDN->RESET gap %0d clocks, expected %0d",
                         id, (t_rst - t_pwdn) / 20, W_PWDN + 1);
                errors = errors + 1;
            end
            if ((t_ready - t_rst) / 20 != W_RST + 1) begin
                $display("ERR [%0d]: RESET->ready gap %0d clocks, expected %0d",
                         id, (t_ready - t_rst) / 20, W_RST + 1);
                errors = errors + 1;
            end
            if (sys_reset_n !== 1'b1 || pwdn !== 1'b0 || cam_reset_n !== 1'b1) begin
                $display("ERR [%0d]: wrong output levels once ready", id);
                errors = errors + 1;
            end
        end
    endtask

    // Watchdog
    initial begin
        #(20 * LIMIT * 10);
        $display("ERR: watchdog timeout");
        $display("FAIL");
        $finish;
    end

    initial begin
        // 1. Button reset active at start, PLL not locked
        reset_n = 1'b0;
        tick(5);
        check_idle(1);

        // 2. Reset released but PLL still unlocked: must stay idle
        reset_n = 1'b1;
        tick(20);
        check_idle(2);

        // 3. PLL locks: full power-up sequence
        dut.pll1.lock_en = 1'b1;
        wait_ready(LIMIT);
        check_sequence(3);

        // 4. Lock lost after ready: everything returns to idle
        dut.pll1.lock_en = 1'b0;
        tick(4);
        check_idle(4);

        // 5. Lock comes back: sequence runs again from the start
        dut.pll1.lock_en = 1'b1;
        wait_ready(LIMIT);
        check_sequence(5);

        // 6. Lock lost, then regained in the middle of the long wait.
        //    The wait must restart from zero (gap check proves it).
        dut.pll1.lock_en = 1'b0;
        tick(4);
        check_idle(6);
        dut.pll1.lock_en = 1'b1;
        wait_cam_reset_release(LIMIT);
        tick(8);
        dut.pll1.lock_en = 1'b0;
        tick(4);
        check_idle(7);
        dut.pll1.lock_en = 1'b1;
        wait_ready(LIMIT);
        check_sequence(8);

        // 7. Button reset while ready
        reset_n = 1'b0;
        tick(3);
        check_idle(9);
        reset_n = 1'b1;
        wait_ready(LIMIT);
        check_sequence(10);

        // 8. Button reset during the PWDN gap
        reset_n = 1'b0;
        tick(3);
        reset_n = 1'b1;
        while (pwdn !== 1'b0) @(negedge clk);
        tick(2);
        reset_n = 1'b0;
        tick(3);
        check_idle(11);
        reset_n = 1'b1;
        wait_ready(LIMIT);
        check_sequence(12);

        $display("Errors: %0d", errors);
        if (errors == 0) $display("PASS");
        else             $display("FAIL");
        $finish;
    end

endmodule