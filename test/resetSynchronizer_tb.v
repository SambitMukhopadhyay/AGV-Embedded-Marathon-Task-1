`timescale 1ns/1ps
module resetSynchronizer_tb;

    reg  clk = 1'b0;
    reg  clk_en = 1'b1;          // lets the test stop the clock
    reg  reset_async_n;
    wire reset_sync_n;

    resetSynchronizer dut (
        .clk         (clk),
        .reset_async_n(reset_async_n),
        .reset_sync_n (reset_sync_n)
    );

    always #10 if (clk_en) clk = ~clk;   // posedge at 10, 30, 50 ... ns

    integer errors = 0;

    task expect_out(input integer id, input value);
        begin
            if (reset_sync_n !== value) begin
                $display("ERR [%0d]: reset_sync_n = %b, expected %b (time %0t)",
                         id, reset_sync_n, value, $time);
                errors = errors + 1;
            end
        end
    endtask

    // The release must always land right after a rising clock edge
    always @(posedge reset_sync_n) begin
        if (clk !== 1'b1) begin
            $display("ERR: reset_sync_n rose without a clock edge (time %0t)", $time);
            errors = errors + 1;
        end
    end

    initial begin
        // 1. Assert between clock edges: output must fall at once, before any edge
        reset_async_n = 1'b1;
        #3 reset_async_n = 1'b0;
        #1 expect_out(1, 1'b0);

        // 2. Held in reset across several edges
        repeat (3) @(negedge clk);
        expect_out(2, 1'b0);

        // 3. Release: output rises exactly two clock edges later
        reset_async_n = 1'b1;
        @(negedge clk);                  // after edge 1
        expect_out(3, 1'b0);
        @(negedge clk);                  // after edge 2
        expect_out(4, 1'b1);
        repeat (3) @(negedge clk);
        expect_out(5, 1'b1);

        // 4. Short press between two clock edges: still caught
        @(negedge clk);
        #5 reset_async_n = 1'b0;
        #1 expect_out(6, 1'b0);          // low immediately, no edge needed
        #2 reset_async_n = 1'b1;         // released before the next edge
        @(negedge clk);                  // after edge 1 since release
        expect_out(7, 1'b0);
        @(negedge clk);                  // after edge 2
        expect_out(8, 1'b1);

        // 5. Clock stopped: assert still works, release must wait for the clock
        @(negedge clk);
        clk_en = 1'b0;
        #45 reset_async_n = 1'b0;
        #1 expect_out(9, 1'b0);          // asserted with no clock running
        #20 reset_async_n = 1'b1;
        #100 expect_out(10, 1'b0);       // no clock, so no release
        clk_en = 1'b1;                   // clock restarts
        @(negedge clk);                  // after edge 1
        expect_out(11, 1'b0);
        @(negedge clk);                  // after edge 2
        expect_out(12, 1'b1);

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