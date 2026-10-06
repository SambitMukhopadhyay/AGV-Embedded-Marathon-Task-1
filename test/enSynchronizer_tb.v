`timescale 1ns/1ps
module enSynchronizer_tb;

    reg  pclk         = 1'b0;
    reg  config_done  = 1'b0;
    reg  reset_sync_n = 1'b0;
    wire en_sync;

    enSynchronizer dut (
        .pclk        (pclk),
        .config_done (config_done),
        .reset_sync_n(reset_sync_n),
        .en_sync     (en_sync)
    );

    always #20 pclk = ~pclk;     // 25 MHz, stands in for PCLK

    integer errors = 0;

    // Everything is driven and sampled on the falling edge, away from the DUT's edge
    task tick(input integer n);
        begin
            repeat (n) @(negedge pclk);
        end
    endtask

    task expect_en(input integer id, input value);
        begin
            if (en_sync !== value) begin
                $display("ERR [%0d]: en_sync = %b, expected %b (time %0t)",
                         id, en_sync, value, $time);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        // 1. Reset active from time zero, config_done already high:
        //    en_sync must be a clean 0 after the first edge (never X)
        config_done  = 1'b1;
        reset_sync_n = 1'b0;
        @(negedge pclk);
        expect_en(1, 1'b0);
        tick(3);
        expect_en(2, 1'b0);

        // 2. Reset released, config_done low: stays 0
        reset_sync_n = 1'b0 | 1'b1;
        config_done  = 1'b0;
        tick(4);
        expect_en(3, 1'b0);

        // 3. config_done rises: en_sync rises exactly two PCLK edges later
        config_done = 1'b1;
        @(negedge pclk);              // after edge 1
        expect_en(4, 1'b0);
        if (dut.en_meta !== 1'b1) begin
            $display("ERR [5]: en_meta not 1 after the first edge");
            errors = errors + 1;
        end
        @(negedge pclk);              // after edge 2
        expect_en(6, 1'b1);
        tick(5);
        expect_en(7, 1'b1);           // stays high while config_done is high

        // 4. config_done falls: en_sync falls exactly two edges later
        config_done = 1'b0;
        @(negedge pclk);
        expect_en(8, 1'b1);
        @(negedge pclk);
        expect_en(9, 1'b0);

        // 5. Reset in the middle: config_done high, then reset
        config_done = 1'b1;
        tick(4);
        expect_en(10, 1'b1);
        reset_sync_n = 1'b0;          // config_done is still high
        @(negedge pclk);
        expect_en(11, 1'b0);          // reset beats the shifting
        tick(3);
        expect_en(12, 1'b0);          // held at 0 while reset is low

        // 6. Reset released with config_done still high: two edges to come back
        reset_sync_n = 1'b1;
        @(negedge pclk);
        expect_en(13, 1'b0);
        @(negedge pclk);
        expect_en(14, 1'b1);

        $display("Errors: %0d", errors);
        if (errors == 0) $display("PASS");
        else             $display("FAIL");
        $finish;
    end

    // Watchdog
    initial begin
        #100000;
        $display("ERR: watchdog timeout");
        $display("FAIL");
        $finish;
    end

endmodule