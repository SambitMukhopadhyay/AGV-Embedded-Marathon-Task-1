module sccbMaster(
    input clk_50MHz,
    input wire [7:0] reg_addr,
    input wire [7:0] reg_data,
    input reset_n,
    input start,
    inout siod,
    output reg busy,
    output reg done,
    output reg sioc
);

    localparam S0 = 4'b0000, S1 = 4'b0001, S2 = 4'b0010, S3 = 4'b0011, S4 = 4'b0100, S5 = 4'b0101, S6 = 4'b0110, S7 = 4'b0111, S8 = 4'b1000, S9 = 4'b1001;

    reg siod_temp, tick_400kHz, ignore_bit;
    reg [4:0] index;
    reg [3:0] state;
    reg [6:0] counter;
    reg [7:0] reg_addr_temp;
    reg [7:0] reg_data_temp;
    wire [26:0] data;

    assign data = {8'h42, 1'b0, reg_addr_temp, 1'b0, reg_data_temp, 1'b0};
    assign siod = ignore_bit ? 1'bz : siod_temp;

    always @(posedge clk_50MHz)
    begin
        if (reset_n == 1'b0)
        begin
            busy <= 1'b0;
            done <= 1'b0;
            sioc <= 1'b1;
            siod_temp <= 1'b1;
            tick_400kHz <= 1'b0;
            ignore_bit <= 1'b0;
            index <= 5'd26;
            state <= S0;
            counter <= 7'd0;
        end

        else
        begin
            done <= 1'b0;
            tick_400kHz <= 1'b0;

            counter <= counter + 1;
            if (counter == 7'd124)
            begin
                tick_400kHz <= 1'b1;
                counter <= 7'd0;
            end

            if (start == 1'b1 && busy == 1'b0)
            begin
                busy <= 1'b1;
                reg_addr_temp <= reg_addr;
                reg_data_temp <= reg_data;
                state <= S0;
                index <= 5'd26;
            end

            if (tick_400kHz && busy)
            begin
                case(state)
                    S0: begin
                            state <= S1;
                            siod_temp <= 1'b1;
                            sioc <= 1'b1;
                        end

                    S1: begin
                            state <= S2;
                            siod_temp <= 1'b0;
                        end

                    S2: begin
                            state <= S3;
                            sioc <= 1'b0;
                        end

                    S3: begin
                            state <= S4;
                            if (index == 5'd0 || index == 5'd9 || index == 5'd18)
                                ignore_bit <= 1'b1;
                            siod_temp <= data[index];
                        end

                    S4: begin
                            state <= S5;
                            sioc <= 1'b1;
                        end

                    S5: state <= S6;

                    S6: begin
                            index <= index - 1;
                            if (index == 5'd0)
                                state <= S7;
                            else
                                state <= S3;
                            sioc <= 1'b0;
                            ignore_bit <= 1'b0;
                        end

                    S7: begin
                            state <= S8;
                            sioc <= 1'b1;
                        end

                    S8: begin
                            state <= S9;
                            siod_temp <= 1'b1;
                        end

                    S9: begin
                            state <= S9;
                            busy <= 1'b0;
                            done <= 1'b1;
                        end

                    default: begin
                            state <= S0;
                            sioc <= 1'b0;
                        end
                endcase
            end
        end
    end

endmodule