module clockAndResetControl#(
    parameter WAIT_CYCLES_AFTER_RESET = 500000,
    parameter WAIT_CYCLES_AFTER_PWDN = 50000
)(
    input clk_50MHz,
    input reset_n,
    output xclk,
    output reg cam_reset_n,
    output reg pwdn,
    output reg cam_ready,
    output reg sys_reset_n
);

    localparam S0 = 3'b000, S1 = 3'b001, S2 = 3'b010, S3 = 3'b011, S4 = 3'b100;
    localparam rst_wt_cnt_width = $clog2(WAIT_CYCLES_AFTER_RESET);
    localparam pwdn_wt_cnt_width = $clog2(WAIT_CYCLES_AFTER_PWDN);

    wire lock;
    reg lock_meta, lock_sync;
    reg [2:0] state;
    reg [rst_wt_cnt_width-1:0] rst_wait_counter;
    reg [pwdn_wt_cnt_width-1:0] pwdn_wait_counter;

    cam_pll pll1(clk_50MHz, xclk, lock);

    always @(posedge clk_50MHz)
    begin
        lock_meta <= lock;
        lock_sync <= lock_meta;

        if (reset_n == 1'b0)
        begin
            lock_meta <= 1'b0;
            lock_sync <= 1'b0;
        end

        if (reset_n == 1'b0 || lock_sync == 1'b0)
        begin
            cam_reset_n <= 1'b0;
            pwdn <= 1'b1;
            cam_ready <= 1'b0;
            sys_reset_n <= 1'b0;
            rst_wait_counter <= 0;
            pwdn_wait_counter <= 0;
            state <= S0;
        end

        else
        begin
            case(state)
                S0: begin
                        state <= S1;
                        pwdn <= 1'b0;
                        sys_reset_n <= 1'b1;
                        pwdn_wait_counter <= 0;
                    end

                S1: begin
                        if (pwdn_wait_counter == WAIT_CYCLES_AFTER_PWDN - 1)
                            state <= S2;
                        else
                        begin
                            pwdn_wait_counter <= pwdn_wait_counter + 1;
                            state <= S1;
                        end
                    end
                
                S2: begin
                        state <= S3;
                        cam_reset_n <= 1'b1;
                        rst_wait_counter <= 0;
                    end

                S3: begin
                        if (rst_wait_counter == WAIT_CYCLES_AFTER_RESET - 1)
                            state <= S4;
                        else
                        begin
                            rst_wait_counter <= rst_wait_counter + 1;
                            state <= S3;
                        end
                    end

                S4: begin
                        cam_ready <= 1'b1;
                        state <= S4;
                    end

                default: state <= S0;
            endcase
        end
    end
endmodule