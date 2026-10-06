module enSynchronizer(
    input pclk,
    input config_done,
    input reset_sync_n,
    output reg en_sync
);
    reg en_meta;

    always @(posedge pclk)
    begin
        if (reset_sync_n == 1'b0)
        begin
            en_meta <= 1'b0;
            en_sync <= 1'b0;
        end

        else
        begin
            en_meta <= config_done;
            en_sync <= en_meta;
        end
    end
endmodule