module sequencer#(
    parameter TOTAL_ENTRIES = 3,
    parameter WAIT_COUNT = 500000
)(
    input clk_50MHz,
    input reset_n,
    input cam_ready,
    input sccb_busy,
    input sccb_done,
    output reg [7:0] reg_addr,
    output reg [7:0] reg_data,
    output reg start,
    output reg config_done
);

    localparam ent_cnt_width = $clog2(TOTAL_ENTRIES) + 1;
    localparam wt_cnt_width = $clog2(WAIT_COUNT) + 1;
    localparam S0 = 3'b000, S1 = 3'b001, S2 = 3'b010, S3 = 3'b011, S4 = 3'b100;

    reg [ent_cnt_width-1:0] entry_idx;
    reg [wt_cnt_width-1:0] wait_counter;
    reg [2:0] state;
    reg [15:0] rom_word;

    always @(*)
    begin
        case (entry_idx)
            0: rom_word = {8'h12, 8'h80};   // COM7: soft reset (must stay entry 0)
            1: rom_word = {8'h11, 8'h01};   // CLKRC: prescaler (placeholder value)
            2: rom_word = {8'h40, 8'hD0};   // COM15: RGB565 (placeholder value)
            // ... one line per register
            default: rom_word = 16'hFFFF;   // end marker
        endcase
    end

    always @(posedge clk_50MHz)
    begin
        if (reset_n == 1'b0 || cam_ready == 1'b0)
        begin
            start <= 1'b0;
            config_done <= 1'b0;
            entry_idx <= 0;
            wait_counter <= 0;
            state <= S0;
        end

        else
        begin
            start <= 1'b0;
            case(state)
                S0: begin
                        state <= S1;
                        {reg_addr, reg_data} <= rom_word;
                        entry_idx <= entry_idx + 1;
                        start <= 1'b1;
                        wait_counter <= 0;
                    end
                
                S1: begin
                        if (wait_counter == WAIT_COUNT - 1)
                            state <= S2;
                        else
                        begin
                            state <= S1;
                            wait_counter <= wait_counter + 1;
                        end
                    end

                S2: begin
                        state <= S3;
                        if (sccb_busy == 1'b0)
                        begin
                            {reg_addr, reg_data} <= rom_word;
                            entry_idx <= entry_idx + 1;
                            start <= 1'b1;
                        end
                    end

                S3: begin
                        if (sccb_done == 1'b1)
                        begin
                            if (entry_idx == TOTAL_ENTRIES)
                                state <= S4;
                            else
                                state <= S2;
                        end

                        else
                            state <= S3;
                    end

                S4: begin
                        state <= S4;
                        config_done <= 1'b1;
                    end

                default: state <= S0;
            endcase
        end
    end
endmodule