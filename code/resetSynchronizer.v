module resetSynchronizer(
    input clk,
    input reset_async_n,
    output reg reset_sync_n
);
    reg reset_meta_n;

    always @(posedge clk, negedge reset_async_n)
    begin
        if (reset_async_n == 1'b0)
        begin
            reset_meta_n <= 1'b0;
            reset_sync_n <= 1'b0;
        end

        else
        begin
            reset_meta_n <= 1'b1;
            reset_sync_n <= reset_meta_n;
        end
    end
endmodule