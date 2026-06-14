`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05.02.2026 07:22:59
// Design Name: 
// Module Name: shift_reg_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// Tests     : MSB-first TX, LSB-first TX, MSB-first RX, LSB-first RX,
//             all 4 SPI modes (cpol/cpha), reset mid-frame

module shift_reg_tb();
 
    // -----------------------------------------------------------------------
    // DUT ports
    // -----------------------------------------------------------------------
    reg         PCLK;
    reg         PRESET_n;
    reg         ss_i;
    reg         send_data_i;
    reg         lsbfe_i;
    reg         cpha_i;
    reg         cpol_i;
    reg         miso_receive_sclk_i;
    reg         miso_receive_sclk0_i;
    reg         mosi_send_sclk_i;
    reg         mosi_send_sclk0_i;
    reg  [7:0]  data_mosi_i;
    reg         miso_i;
    reg         receive_data_i;
 
    wire        mosi_o;
    wire [7:0]  data_miso_o;
 
    // variable to capture data_miso_o while receive_data_i is still high
    reg  [7:0]  captured_miso;
 
    // -----------------------------------------------------------------------
    // DUT instantiation
    // -----------------------------------------------------------------------
    shift_reg dut (
        .PCLK                (PCLK),
        .PRESET_n            (PRESET_n),
        .ss_i                (ss_i),
        .send_data_i         (send_data_i),
        .lsbfe_i             (lsbfe_i),
        .cpha_i              (cpha_i),
        .cpol_i              (cpol_i),
        .miso_receive_sclk_i (miso_receive_sclk_i),
        .miso_receive_sclk0_i(miso_receive_sclk0_i),
        .mosi_send_sclk_i    (mosi_send_sclk_i),
        .mosi_send_sclk0_i   (mosi_send_sclk0_i),
        .data_mosi_i         (data_mosi_i),
        .miso_i              (miso_i),
        .receive_data_i      (receive_data_i),
        .mosi_o              (mosi_o),
        .data_miso_o         (data_miso_o)
    );
 
    // -----------------------------------------------------------------------
    // Clock (10 ns period)
    // -----------------------------------------------------------------------
    initial PCLK = 0;
    always  #5 PCLK = ~PCLK;
 
    // -----------------------------------------------------------------------
    // clk_sel: cpha ^ cpol
    //   1 → MOSI/MISO on sclk_i path
    //   0 → MOSI/MISO on sclk0_i path
    // -----------------------------------------------------------------------
    function clk_sel;
        input dummy;
        clk_sel = cpha_i ^ cpol_i;
    endfunction
 
    // -----------------------------------------------------------------------
    // Task: apply_reset
    // -----------------------------------------------------------------------
    task apply_reset;
        begin
            PRESET_n             = 1'b0;
            ss_i                 = 1'b1;
            send_data_i          = 1'b0;
            receive_data_i       = 1'b0;
            miso_receive_sclk_i  = 1'b0;
            miso_receive_sclk0_i = 1'b0;
            mosi_send_sclk_i     = 1'b0;
            mosi_send_sclk0_i    = 1'b0;
            miso_i               = 1'b0;
            data_mosi_i          = 8'h00;
            repeat (3) @(posedge PCLK);
            @(negedge PCLK);
            PRESET_n = 1'b1;
            $display("[%0t] RESET released", $time);
        end
    endtask
 
    // -----------------------------------------------------------------------
    // Task: load_mosi
    // -----------------------------------------------------------------------
    task load_mosi;
        input [7:0] data;
        begin
            @(negedge PCLK);
            send_data_i = 1'b1;
            data_mosi_i = data;
            @(negedge PCLK);
            send_data_i = 1'b0;
            $display("[%0t] Loaded MOSI data = 0x%0h", $time, data);
        end
    endtask
 
    // -----------------------------------------------------------------------
    // Task: start_spi
    // -----------------------------------------------------------------------
    task start_spi;
        begin
            @(negedge PCLK);
            ss_i = 1'b0;
            $display("[%0t] SPI started (ss_i=0)", $time);
        end
    endtask
 
    // -----------------------------------------------------------------------
    // Task: stop_spi
    // -----------------------------------------------------------------------
    task stop_spi;
        begin
            @(negedge PCLK);
            ss_i = 1'b1;
            $display("[%0t] SPI stopped (ss_i=1)", $time);
        end
    endtask
 
    // -----------------------------------------------------------------------
    // Task: send_mosi_bit  (mode-aware sclk selection)
    // -----------------------------------------------------------------------
    task send_mosi_bit;
        begin
            @(negedge PCLK);
            if (clk_sel(0)) begin
                mosi_send_sclk_i  = 1'b1;
                @(negedge PCLK);
                mosi_send_sclk_i  = 1'b0;
            end else begin
                mosi_send_sclk0_i = 1'b1;
                @(negedge PCLK);
                mosi_send_sclk0_i = 1'b0;
            end
        end
    endtask
 
    // -----------------------------------------------------------------------
    // Task: receive_miso_bit  (mode-aware sclk selection)
    //   clk_wire=1 → MISO sampled on sclk0 edge
    //   clk_wire=0 → MISO sampled on sclk  edge
    // -----------------------------------------------------------------------
    task receive_miso_bit;
        input bit_val;
        begin
            @(negedge PCLK);
            miso_i = bit_val;
            if (clk_sel(0)) begin
                miso_receive_sclk0_i = 1'b1;
                @(negedge PCLK);
                miso_receive_sclk0_i = 1'b0;
            end else begin
                miso_receive_sclk_i  = 1'b1;
                @(negedge PCLK);
                miso_receive_sclk_i  = 1'b0;
            end
        end
    endtask
 
    // -----------------------------------------------------------------------
    // Task: read_received_data
    //   FIX: capture data_miso_o WHILE receive_data_i is still high,
    //        before the output mux returns it to 8'h00
    // -----------------------------------------------------------------------
    task read_received_data;
        begin
            @(negedge PCLK);
            receive_data_i = 1'b1;
            @(negedge PCLK);
            // Sample here - receive_data_i still 1, so mux selects temp_reg
            captured_miso  = data_miso_o;
            receive_data_i = 1'b0;
            $display("[%0t] read_received_data: captured = 0x%0h", $time, captured_miso);
        end
    endtask
 
    // -----------------------------------------------------------------------
    // Task: send_8_bits  - transmit full byte, display captured MOSI bits
    // -----------------------------------------------------------------------
    task send_8_bits;
        input [7:0] data;
        reg   [7:0] captured_bits;
        integer i;
        begin
            load_mosi(data);
            start_spi;
            captured_bits = 8'h00;
            for (i = 0; i < 8; i = i + 1) begin
                send_mosi_bit;
                captured_bits[i] = mosi_o;
            end
            $display("[%0t] TX done: sent=0x%0h mosi_bits=%b lsbfe=%b",
                     $time, data, captured_bits, lsbfe_i);
            stop_spi;
        end
    endtask
 
    // -----------------------------------------------------------------------
    // Task: receive_8_bits  - receive full byte, PASS/FAIL check
    //   rx_pattern: the byte whose bits are fed MSB-first in time
    //   expected  : the byte that should appear in data_miso_o
    // -----------------------------------------------------------------------
    task receive_8_bits;
        input [7:0] rx_pattern;
        input [7:0] expected;
        integer i;
        begin
            start_spi;
            for (i = 7; i >= 0; i = i - 1)
                receive_miso_bit(rx_pattern[i]);
            read_received_data;
            // Check captured_miso (sampled while receive_data_i was high)
            if (captured_miso === expected)
                $display("[%0t] PASS: data_miso_o=0x%0h (expected 0x%0h)",
                         $time, captured_miso, expected);
            else
                $display("[%0t] FAIL: data_miso_o=0x%0h (expected 0x%0h)",
                         $time, captured_miso, expected);
            stop_spi;
        end
    endtask
 
    // -----------------------------------------------------------------------
    // Task: test_reset_mid_frame
    // -----------------------------------------------------------------------
    task test_reset_mid_frame;
        begin
            $display("[%0t] TEST: reset mid-frame", $time);
            load_mosi(8'hFF);
            start_spi;
            send_mosi_bit;
            send_mosi_bit;
            send_mosi_bit;
            // Assert reset mid-frame
            PRESET_n = 1'b0;
            repeat (3) @(posedge PCLK);
            @(negedge PCLK);
            PRESET_n = 1'b1;
            repeat (2) @(posedge PCLK);
            if (mosi_o === 1'b0)
                $display("[%0t] PASS: mosi_o=0 after mid-frame reset", $time);
            else
                $display("[%0t] FAIL: mosi_o should be 0 after reset, got %b", $time, mosi_o);
            ss_i = 1'b1;
        end
    endtask
 
    // -----------------------------------------------------------------------
    // Main stimulus
    // -----------------------------------------------------------------------
    initial begin
        $dumpfile("shift_reg_tb.vcd");
        $dumpvars(0, shift_reg_tb);
 
        // ===== Mode 0 (cpol=0,cpha=0) MSB-first TX =====
        $display("\n===== Mode 0 (cpol=0,cpha=0) MSB-first TX =====");
        cpol_i = 0; cpha_i = 0; lsbfe_i = 0;
        apply_reset;
        send_8_bits(8'hA5);
        #20;
 
        // ===== Mode 0 (cpol=0,cpha=0) LSB-first TX =====
        $display("\n===== Mode 0 (cpol=0,cpha=0) LSB-first TX =====");
        lsbfe_i = 1;
        apply_reset;
        send_8_bits(8'hA5);
        #20;
 
        // ===== Mode 0 MSB-first RX: expect 0xCC =====
        $display("\n===== Mode 0 MSB-first RX: expect 0xCC =====");
        cpol_i = 0; cpha_i = 0; lsbfe_i = 0;
        apply_reset;
        // 0xCC = 1100_1100 → feed MSB first: 1,1,0,0,1,1,0,0
        receive_8_bits(8'hCC, 8'hCC);
        #20;
 
        // ===== Mode 0 LSB-first RX =====
        // Feed 0xCC MSB-first in time → LSB-first RX places:
        //   time-bit0(=MSB=1) → temp[0], time-bit1(=1) → temp[1], ...
        //   0xCC fed [7..0] = 1,1,0,0,1,1,0,0 → temp = 0011_0011 = 0x33
        $display("\n===== Mode 0 LSB-first RX: feed 0xCC MSB-first, expect 0x33 =====");
        lsbfe_i = 1;
        apply_reset;
        receive_8_bits(8'hCC, 8'h33);
        #20;
 
        // ===== Mode 1 (cpol=0,cpha=1) MSB-first TX =====
        $display("\n===== Mode 1 (cpol=0,cpha=1) MSB-first TX =====");
        cpol_i = 0; cpha_i = 1; lsbfe_i = 0;
        apply_reset;
        send_8_bits(8'h5A);
        #20;
 
        // ===== Mode 2 (cpol=1,cpha=0) MSB-first TX =====
        $display("\n===== Mode 2 (cpol=1,cpha=0) MSB-first TX =====");
        cpol_i = 1; cpha_i = 0; lsbfe_i = 0;
        apply_reset;
        send_8_bits(8'h5A);
        #20;
 
        // ===== Mode 3 (cpol=1,cpha=1) MSB-first TX =====
        $display("\n===== Mode 3 (cpol=1,cpha=1) MSB-first TX =====");
        cpol_i = 1; cpha_i = 1; lsbfe_i = 0;
        apply_reset;
        send_8_bits(8'h5A);
        #20;
 
        // ===== Mid-frame reset =====
        $display("\n===== Mid-frame reset =====");
        cpol_i = 0; cpha_i = 0; lsbfe_i = 0;
        apply_reset;
        test_reset_mid_frame;
        #20;
 
        $display("\n[%0t] Simulation complete", $time);
        $finish;
    end
 
    // -----------------------------------------------------------------------
    // Monitor
    // -----------------------------------------------------------------------
    initial begin
        $monitor("[%0t] ss=%b send=%b mosi=%b miso=%b rcv=%b data_miso=%h | cnt=%0d cnt1=%0d",
                 $time, ss_i, send_data_i, mosi_o, miso_i,
                 receive_data_i, data_miso_o,
                 dut.count, dut.count1);
    end
 
endmodule