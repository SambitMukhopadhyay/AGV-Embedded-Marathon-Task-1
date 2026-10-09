module sequencer#(
    parameter TOTAL_ENTRIES = 174,
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
        // OV7670 configuration table: VGA 640x480, RGB565.
        // Values come from the Linux kernel ov7670 driver (GPL-2.0; register set originally supplied by OmniVision),
        // NOT from the datasheet PDF. Lines marked CHECK differ from or are not covered by that source.
        // TOTAL_ENTRIES = 174   (entry 0 must stay the soft reset; entry index width = $clog2(TOTAL_ENTRIES)+1 = 9 bits)
        case (entry_idx)
            0: rom_word = {8'h12, 8'h80};   // COM7: soft reset (must stay entry 0; sequencer waits after it)
            1: rom_word = {8'h3a, 8'h04};   // TSLB
            2: rom_word = {8'h17, 8'h13};   // HSTART
            3: rom_word = {8'h18, 8'h01};   // HSTOP
            4: rom_word = {8'h32, 8'hb6};   // HREF
            5: rom_word = {8'h19, 8'h02};   // VSTART
            6: rom_word = {8'h1a, 8'h7a};   // VSTOP
            7: rom_word = {8'h03, 8'h0a};   // VREF
            8: rom_word = {8'h0c, 8'h00};   // COM3
            9: rom_word = {8'h3e, 8'h00};   // COM14
            10: rom_word = {8'h70, 8'h3a};   // scaling (OV magic)
            11: rom_word = {8'h71, 8'h35};   // scaling (OV magic)
            12: rom_word = {8'h72, 8'h11};   // scaling (OV magic)
            13: rom_word = {8'h73, 8'hf0};   // scaling (OV magic)
            14: rom_word = {8'ha2, 8'h02};   // reserved
            15: rom_word = {8'h15, 8'h00};   // COM10: VSYNC/HREF/PCLK polarity+mode defaults
            16: rom_word = {8'h7a, 8'h20};   // gamma curve
            17: rom_word = {8'h7b, 8'h10};   // gamma curve
            18: rom_word = {8'h7c, 8'h1e};   // gamma curve
            19: rom_word = {8'h7d, 8'h35};   // gamma curve
            20: rom_word = {8'h7e, 8'h5a};   // gamma curve
            21: rom_word = {8'h7f, 8'h69};   // gamma curve
            22: rom_word = {8'h80, 8'h76};   // gamma curve
            23: rom_word = {8'h81, 8'h80};   // gamma curve
            24: rom_word = {8'h82, 8'h88};   // gamma curve
            25: rom_word = {8'h83, 8'h8f};   // gamma curve
            26: rom_word = {8'h84, 8'h96};   // gamma curve
            27: rom_word = {8'h85, 8'ha3};   // gamma curve
            28: rom_word = {8'h86, 8'haf};   // gamma curve
            29: rom_word = {8'h87, 8'hc4};   // gamma curve
            30: rom_word = {8'h88, 8'hd7};   // gamma curve
            31: rom_word = {8'h89, 8'he8};   // gamma curve
            32: rom_word = {8'h13, 8'he0};   // COM8: AGC/AEC/AWB off while tuning
            33: rom_word = {8'h00, 8'h00};   // GAIN
            34: rom_word = {8'h10, 8'h00};   // AECH
            35: rom_word = {8'h0d, 8'h40};   // COM4
            36: rom_word = {8'h14, 8'h18};   // COM9
            37: rom_word = {8'ha5, 8'h05};   // BD50MAX
            38: rom_word = {8'hab, 8'h07};   // BD60MAX
            39: rom_word = {8'h24, 8'h95};   // AEW
            40: rom_word = {8'h25, 8'h33};   // AEB
            41: rom_word = {8'h26, 8'he3};   // VPT
            42: rom_word = {8'h9f, 8'h78};   // HAECC1
            43: rom_word = {8'ha0, 8'h68};   // HAECC2
            44: rom_word = {8'ha1, 8'h03};   // reserved
            45: rom_word = {8'ha6, 8'hd8};   // HAECC3
            46: rom_word = {8'ha7, 8'hd8};   // HAECC4
            47: rom_word = {8'ha8, 8'hf0};   // HAECC5
            48: rom_word = {8'ha9, 8'h90};   // HAECC6
            49: rom_word = {8'haa, 8'h94};   // HAECC7
            50: rom_word = {8'h13, 8'he5};   // COM8: AGC + AEC on
            51: rom_word = {8'h0e, 8'h61};   // COM5
            52: rom_word = {8'h0f, 8'h4b};   // COM6
            53: rom_word = {8'h16, 8'h02};   // reserved
            54: rom_word = {8'h1e, 8'h07};   // MVFP: mirror/flip
            55: rom_word = {8'h21, 8'h02};   // reserved
            56: rom_word = {8'h22, 8'h91};   // reserved
            57: rom_word = {8'h29, 8'h07};   // reserved
            58: rom_word = {8'h33, 8'h0b};   // reserved
            59: rom_word = {8'h35, 8'h0b};   // reserved
            60: rom_word = {8'h37, 8'h1d};   // reserved
            61: rom_word = {8'h38, 8'h71};   // reserved
            62: rom_word = {8'h39, 8'h2a};   // reserved
            63: rom_word = {8'h3c, 8'h78};   // COM12: HREF only on valid lines
            64: rom_word = {8'h4d, 8'h40};   // reserved
            65: rom_word = {8'h4e, 8'h20};   // reserved
            66: rom_word = {8'h69, 8'h00};   // GFIX
            67: rom_word = {8'h6b, 8'h0a};   // DBLV: PLL bypass  ** CHECK vs datasheet (Linux list has 0x4a = PLL x4) **
            68: rom_word = {8'h74, 8'h10};   // reserved
            69: rom_word = {8'h8d, 8'h4f};   // reserved
            70: rom_word = {8'h8e, 8'h00};   // reserved
            71: rom_word = {8'h8f, 8'h00};   // reserved
            72: rom_word = {8'h90, 8'h00};   // reserved
            73: rom_word = {8'h91, 8'h00};   // reserved
            74: rom_word = {8'h96, 8'h00};   // reserved
            75: rom_word = {8'h9a, 8'h00};   // reserved
            76: rom_word = {8'hb0, 8'h84};   // reserved
            77: rom_word = {8'hb1, 8'h0c};   // reserved
            78: rom_word = {8'hb2, 8'h0e};   // reserved
            79: rom_word = {8'hb3, 8'h82};   // reserved
            80: rom_word = {8'hb8, 8'h0a};   // reserved
            81: rom_word = {8'h43, 8'h0a};   // AWB
            82: rom_word = {8'h44, 8'hf0};   // AWB
            83: rom_word = {8'h45, 8'h34};   // AWB
            84: rom_word = {8'h46, 8'h58};   // AWB
            85: rom_word = {8'h47, 8'h28};   // AWB
            86: rom_word = {8'h48, 8'h3a};   // AWB
            87: rom_word = {8'h59, 8'h88};   // AWB
            88: rom_word = {8'h5a, 8'h88};   // AWB
            89: rom_word = {8'h5b, 8'h44};   // AWB
            90: rom_word = {8'h5c, 8'h67};   // AWB
            91: rom_word = {8'h5d, 8'h49};   // AWB
            92: rom_word = {8'h5e, 8'h0e};   // AWB
            93: rom_word = {8'h6c, 8'h0a};   // AWB
            94: rom_word = {8'h6d, 8'h55};   // AWB
            95: rom_word = {8'h6e, 8'h11};   // AWB
            96: rom_word = {8'h6f, 8'h9f};   // AWB
            97: rom_word = {8'h6a, 8'h40};   // reserved
            98: rom_word = {8'h01, 8'h40};   // BLUE gain
            99: rom_word = {8'h02, 8'h60};   // RED gain
            100: rom_word = {8'h13, 8'he7};   // COM8: AGC + AEC + AWB on
            101: rom_word = {8'h4f, 8'h80};   // colour matrix (YUV defaults; RGB values written below)
            102: rom_word = {8'h50, 8'h80};   // colour matrix (YUV defaults; RGB values written below)
            103: rom_word = {8'h51, 8'h00};   // colour matrix (YUV defaults; RGB values written below)
            104: rom_word = {8'h52, 8'h22};   // colour matrix (YUV defaults; RGB values written below)
            105: rom_word = {8'h53, 8'h5e};   // colour matrix (YUV defaults; RGB values written below)
            106: rom_word = {8'h54, 8'h80};   // colour matrix (YUV defaults; RGB values written below)
            107: rom_word = {8'h58, 8'h9e};   // colour matrix (YUV defaults; RGB values written below)
            108: rom_word = {8'h41, 8'h08};   // COM16
            109: rom_word = {8'h3f, 8'h00};   // EDGE
            110: rom_word = {8'h75, 8'h05};   // reserved
            111: rom_word = {8'h76, 8'he1};   // REG76: pixel correction
            112: rom_word = {8'h4c, 8'h00};   // DNSTH
            113: rom_word = {8'h77, 8'h01};   // reserved
            114: rom_word = {8'h3d, 8'hc3};   // COM13
            115: rom_word = {8'h4b, 8'h09};   // reserved
            116: rom_word = {8'hc9, 8'h60};   // SATCTR
            117: rom_word = {8'h41, 8'h38};   // COM16
            118: rom_word = {8'h56, 8'h40};   // CONTRAS
            119: rom_word = {8'h34, 8'h11};   // reserved
            120: rom_word = {8'h3b, 8'h12};   // COM11: night off, 50/60 Hz auto
            121: rom_word = {8'ha4, 8'h88};   // reserved
            122: rom_word = {8'h96, 8'h00};   // reserved
            123: rom_word = {8'h97, 8'h30};   // reserved
            124: rom_word = {8'h98, 8'h20};   // reserved
            125: rom_word = {8'h99, 8'h30};   // reserved
            126: rom_word = {8'h9a, 8'h84};   // reserved
            127: rom_word = {8'h9b, 8'h29};   // reserved
            128: rom_word = {8'h9c, 8'h03};   // reserved
            129: rom_word = {8'h9d, 8'h4c};   // BD50ST
            130: rom_word = {8'h9e, 8'h3f};   // BD60ST
            131: rom_word = {8'h78, 8'h04};   // reserved
            132: rom_word = {8'h79, 8'h01};   // indirect register index
            133: rom_word = {8'hc8, 8'hf0};   // indirect register data
            134: rom_word = {8'h79, 8'h0f};   // indirect register index
            135: rom_word = {8'hc8, 8'h00};   // indirect register data
            136: rom_word = {8'h79, 8'h10};   // indirect register index
            137: rom_word = {8'hc8, 8'h7e};   // indirect register data
            138: rom_word = {8'h79, 8'h0a};   // indirect register index
            139: rom_word = {8'hc8, 8'h80};   // indirect register data
            140: rom_word = {8'h79, 8'h0b};   // indirect register index
            141: rom_word = {8'hc8, 8'h01};   // indirect register data
            142: rom_word = {8'h79, 8'h0c};   // indirect register index
            143: rom_word = {8'hc8, 8'h0f};   // indirect register data
            144: rom_word = {8'h79, 8'h0d};   // indirect register index
            145: rom_word = {8'hc8, 8'h20};   // indirect register data
            146: rom_word = {8'h79, 8'h09};   // indirect register index
            147: rom_word = {8'hc8, 8'h80};   // indirect register data
            148: rom_word = {8'h79, 8'h02};   // indirect register index
            149: rom_word = {8'hc8, 8'hc0};   // indirect register data
            150: rom_word = {8'h79, 8'h03};   // indirect register index
            151: rom_word = {8'hc8, 8'h40};   // indirect register data
            152: rom_word = {8'h79, 8'h05};   // indirect register index
            153: rom_word = {8'hc8, 8'h30};   // indirect register data
            154: rom_word = {8'h79, 8'h26};   // indirect register index
            155: rom_word = {8'h12, 8'h04};   // COM7: RGB output, VGA size
            156: rom_word = {8'h8c, 8'h00};   // RGB444 off
            157: rom_word = {8'h04, 8'h00};   // COM1
            158: rom_word = {8'h40, 8'h10};   // COM15: RGB565, range 10-F0 (0xD0 = full range 00-FF)
            159: rom_word = {8'h14, 8'h38};   // COM9
            160: rom_word = {8'h4f, 8'hb3};   // colour matrix (RGB)
            161: rom_word = {8'h50, 8'hb3};   // colour matrix (RGB)
            162: rom_word = {8'h51, 8'h00};   // colour matrix (RGB)
            163: rom_word = {8'h52, 8'h3d};   // colour matrix (RGB)
            164: rom_word = {8'h53, 8'ha7};   // colour matrix (RGB)
            165: rom_word = {8'h54, 8'he4};   // colour matrix (RGB)
            166: rom_word = {8'h3d, 8'hc0};   // COM13: gamma + UV auto saturation
            167: rom_word = {8'h17, 8'h13};   // HSTART
            168: rom_word = {8'h18, 8'h01};   // HSTOP
            169: rom_word = {8'h32, 8'hb6};   // HREF
            170: rom_word = {8'h19, 8'h02};   // VSTART
            171: rom_word = {8'h1a, 8'h7a};   // VSTOP
            172: rom_word = {8'h03, 8'h0a};   // VREF
            173: rom_word = {8'h11, 8'h01};   // CLKRC: PCLK = XCLK/2 (assumed)  ** CHECK vs datasheet; measure PCLK **
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