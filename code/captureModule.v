module captureModule(
    output reg [15:0] pixel, 
    output reg pixel_valid,
    output reg frame_start_flag,
    output reg [9:0] pixel_no,
    output reg [8:0] line_no,
    input  pclk,
    input  vsync,
    input  href,
    input  wire [7:0] d,
    input  en_sync,
    input  reset_sync_n
);

    reg high_byte, vsync_d, href_d, start_capturing;

    always @(posedge pclk)
    begin
        vsync_d <= vsync;
        href_d <= href;
        
        if (reset_sync_n == 1'b0 || en_sync == 1'b0)
        begin
            pixel_valid <= 1'b0;
            frame_start_flag <= 1'b0;
            pixel_no <= 10'd0;
            line_no <= 9'd0;
            high_byte <= 1'b1;
            start_capturing <= 1'b0;
        end

        else
        begin
            frame_start_flag <= 1'b0;
            pixel_valid <= 1'b0;

            if (pixel_valid)
                pixel_no <= pixel_no + 1;

            if (vsync == 1'b1 && vsync_d == 1'b0)
            begin
                frame_start_flag <= 1'b1;
                start_capturing <= 1'b1;
                line_no <= 9'd0;
                pixel_no <= 10'd0;
                high_byte <= 1'b1;
            end

            if (href == 1'b0 && href_d == 1'b1)
            begin
                line_no <= line_no + 1;
                pixel_no <= 10'd0;
                high_byte <= 1'b1;
            end

            if (start_capturing && href)
            begin
                if (high_byte)
                begin
                    pixel[15:8] <= d;
                    high_byte <= 1'b0;
                end

                else
                begin
                    pixel[7:0] <= d;
                    high_byte <= 1'b1;
                    pixel_valid <= 1'b1;
                end
            end
        end
    end

endmodule