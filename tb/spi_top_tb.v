`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09.06.2026 16:09:43
// Design Name: 
// Module Name: spi_top_tb
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

// Tests   : 1. Reset  2. Config+Readback  3. TX-only
//           4. Full-duplex  5. Mid-frame reset

module spi_top_tb;
 
// ------------------------------------------------------------------
// DUT signals
// ------------------------------------------------------------------
reg        PCLK;
reg        PRESET_n;
reg  [2:0] PADDR_i;
reg        PWRITE_i;
reg        PSEL_i;
reg        PENABLE_i;
reg  [7:0] PWDATA_i;
reg        miso_i;
 
wire [7:0] PRDATA_o;
wire       PREADY_o;
wire       PSLVERR_o;
wire       sclk_o;
wire       mosi_o;
wire       ss_o;
wire       spi_interrupt_req_o;
 
// ------------------------------------------------------------------
// DUT
// ------------------------------------------------------------------
spi_top DUT (
    .PCLK                (PCLK),
    .PRESET_n            (PRESET_n),
    .PADDR_i             (PADDR_i),
    .PWRITE_i            (PWRITE_i),
    .PSEL_i              (PSEL_i),
    .PENABLE_i           (PENABLE_i),
    .PWDATA_i            (PWDATA_i),
    .miso_i              (miso_i),
    .PRDATA_o            (PRDATA_o),
    .PREADY_o            (PREADY_o),
    .PSLVERR_o           (PSLVERR_o),
    .sclk_o              (sclk_o),
    .mosi_o              (mosi_o),
    .ss_o                (ss_o),
    .spi_interrupt_req_o (spi_interrupt_req_o)
);
 
// ------------------------------------------------------------------
// Clock  10 ns / 100 MHz
// ------------------------------------------------------------------
initial PCLK = 1'b0;
always  #5 PCLK = ~PCLK;
 
// ------------------------------------------------------------------
// Scoreboard
// ------------------------------------------------------------------
integer pass_cnt, fail_cnt;
reg [7:0] rd_data;
 
// ------------------------------------------------------------------
// MOSI capture
//   Mode 0 : MOSI is driven one PCLK before the FALLING edge of SCLK
//            so it is rock-stable at the RISING edge.
//   We capture on POSEDGE SCLK (what a real slave would see).
//   Bit order : shift_reg sends MSB first (count1 starts at 7).
// ------------------------------------------------------------------
reg [7:0] mosi_cap;
reg [3:0] mosi_bit_idx;
 
always @(negedge ss_o or negedge PRESET_n) begin
    mosi_cap     <= 8'h00;
    mosi_bit_idx <= 4'd0;
end
 
always @(posedge sclk_o) begin
    if (!ss_o && mosi_bit_idx < 4'd8) begin
        mosi_cap[7 - mosi_bit_idx[2:0]] <= mosi_o;
        mosi_bit_idx <= mosi_bit_idx + 1'b1;
    end
end
 
// ==================================================================
// TASKS
// ==================================================================
 
// ------------------------------------------------------------------
// apply_reset : drives active-low reset for 6 PCLK cycles
// ------------------------------------------------------------------
task apply_reset;
begin
    PRESET_n  = 1'b0;
    PSEL_i    = 1'b0;
    PENABLE_i = 1'b0;
    PWRITE_i  = 1'b0;
    PADDR_i   = 3'd0;
    PWDATA_i  = 8'h00;
    miso_i    = 1'b0;
    repeat(6) @(posedge PCLK);
    @(negedge PCLK); PRESET_n = 1'b1;
    repeat(2) @(posedge PCLK);
    $display("[%0t] RESET released", $time);
end
endtask
 
// ------------------------------------------------------------------
// apb_write : full IDLE->SETUP->ENABLE->IDLE cycle
//   Drives on negedge so signals are stable at the next posedge
// ------------------------------------------------------------------
task apb_write;
    input [2:0] addr;
    input [7:0] data;
begin
    // SETUP phase
    @(negedge PCLK);
    PADDR_i   = addr;
    PWDATA_i  = data;
    PWRITE_i  = 1'b1;
    PSEL_i    = 1'b1;
    PENABLE_i = 1'b0;
    // ENABLE phase
    @(negedge PCLK);
    PENABLE_i = 1'b1;
    // Wait for slave to accept
    @(posedge PCLK);
    while (!PREADY_o) @(posedge PCLK);
    // Deassert
    @(negedge PCLK);
    PSEL_i    = 1'b0;
    PENABLE_i = 1'b0;
    PWRITE_i  = 1'b0;
end
endtask
 
// ------------------------------------------------------------------
// apb_read : full IDLE->SETUP->ENABLE->IDLE cycle
//   Result placed in rd_data
// ------------------------------------------------------------------
task apb_read;
    input [2:0] addr;
begin
    // SETUP phase
    @(negedge PCLK);
    PADDR_i   = addr;
    PWRITE_i  = 1'b0;
    PSEL_i    = 1'b1;
    PENABLE_i = 1'b0;
    // ENABLE phase
    @(negedge PCLK);
    PENABLE_i = 1'b1;
    // Wait for slave
    @(posedge PCLK);
    while (!PREADY_o) @(posedge PCLK);
    rd_data = PRDATA_o;
    // Deassert
    @(negedge PCLK);
    PSEL_i    = 1'b0;
    PENABLE_i = 1'b0;
end
endtask
 
// ------------------------------------------------------------------
// wait_frame : waits for SS to go LOW then HIGH (one complete frame)
// ------------------------------------------------------------------
task wait_frame;
    integer i;
begin
    // wait SS assert
    i = 0;
    while (ss_o === 1'b1 && i < 300) begin @(posedge PCLK); i = i+1; end
    if (ss_o !== 1'b0)
        $display("[%0t] WARNING: SS never asserted (timeout)", $time);
 
    // wait SS deassert
    i = 0;
    while (ss_o === 1'b0 && i < 5000) begin @(posedge PCLK); i = i+1; end
    if (ss_o !== 1'b1)
        $display("[%0t] WARNING: frame timeout - SS still low", $time);
    else
        $display("[%0t] Frame done", $time);
 
    repeat(4) @(posedge PCLK);
end
endtask
 
// ------------------------------------------------------------------
// drive_miso : sends rx_byte MSB-first during an active frame
//   Mode 0 (CPOL=0,CPHA=0): master samples MISO on posedge SCLK
//   We present each bit AFTER negedge SCLK so it is stable
//   before the next posedge SCLK.
//   Run this in a fork with apb_write(DR).
// ------------------------------------------------------------------
task drive_miso;
    input [7:0] rx_byte;
    integer b;
begin
    miso_i = 1'b0;
    @(negedge ss_o);          // wait for frame start
    #1 miso_i = rx_byte[7];   // drive MSB immediately (before first posedge sclk)
    for (b = 6; b >= 0; b = b-1) begin
        @(negedge sclk_o);    // after each falling edge
        #1 miso_i = rx_byte[b];
    end
    @(posedge ss_o);          // frame ended
    miso_i = 1'b0;
end
endtask
 
// ------------------------------------------------------------------
// check : compare got vs exp, print PASS/FAIL
// ------------------------------------------------------------------
task check;
    input [63:0] label;
    input [7:0]  got;
    input [7:0]  exp;
begin
    if (got === exp) begin
        $display("[%0t] PASS  %-8s  0x%02h", $time, label, got);
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("[%0t] FAIL  %-8s  got=0x%02h  exp=0x%02h",
                 $time, label, got, exp);
        fail_cnt = fail_cnt + 1;
    end
end
endtask
 
// ==================================================================
// STIMULUS
// ==================================================================
initial begin
    $dumpfile("spi_top_tb.vcd");
    $dumpvars(0, spi_top_tb);
 
    pass_cnt = 0;
    fail_cnt = 0;
 
    // ----------------------------------------------------------------
    // TC1 : Reset - check idle pin states
    // ----------------------------------------------------------------
    $display("\n[%0t] ===== TC1: Reset defaults =====", $time);
    apply_reset;
    repeat(2) @(posedge PCLK);
 
    check("SS_RST",   {7'd0, ss_o},   8'h01);  // deasserted = 1
    check("MOSI_RST", {7'd0, mosi_o}, 8'h00);
    check("SCLK_RST", {7'd0, sclk_o}, 8'h00);  // CPOL=0 idle = 0
 
    // ----------------------------------------------------------------
    // TC2 : Configure registers and read back
    //   CR1 = 0x50 : SPE=1 MSTR=1 CPOL=0 CPHA=0 LSBFE=0
    //   CR2 = 0x00 : defaults
    //   BR  = 0x11 : SPPR=1[6:4] SPR=1[2:0]
    //              → BRD = (1+1)*2^(1+1) = 8
    //              → frame = 8*16 = 128 PCLKs = 1280 ns
    //              → hit=count==3  hit1=count==2  (both safe, no underflow)
    // ----------------------------------------------------------------
    $display("\n[%0t] ===== TC2: Config + readback =====", $time);
    apb_write(3'd0, 8'h50);
    apb_write(3'd1, 8'h00);
    apb_write(3'd2, 8'h11);
 
    apb_read(3'd0); check("CR1", rd_data, 8'h50);
    apb_read(3'd1); check("CR2", rd_data, 8'h00);
    apb_read(3'd2); check("BR",  rd_data, 8'h11);
 
    repeat(2) @(posedge PCLK);
 
    // ----------------------------------------------------------------
    // TC3 : Transmit 0xFF
    // ----------------------------------------------------------------
    $display("\n[%0t] ===== TC3: TX 0xFF =====", $time);
    apb_write(3'd5, 8'hFF);
    wait_frame;
    check("MOSI_FF", mosi_cap, 8'hFF);
 
    repeat(3) @(posedge PCLK);
 
    // ----------------------------------------------------------------
    // TC4 : Transmit 0xA5  (alternating 1010_0101)
    // ----------------------------------------------------------------
    $display("\n[%0t] ===== TC4: TX 0xA5 =====", $time);
    apb_write(3'd5, 8'hA5);
    wait_frame;
    check("MOSI_A5", mosi_cap, 8'hA5);
 
    repeat(3) @(posedge PCLK);
 
    // ----------------------------------------------------------------
    // TC5 : Full-duplex  TX=0xB6  RX=0xC3
    //   Fork: APB thread writes DR and waits, MISO thread drives 0xC3
    // ----------------------------------------------------------------
    $display("\n[%0t] ===== TC5: Full-duplex TX=0xB6 RX=0xC3 =====", $time);
    fork
        begin : TC5_TX
            apb_write(3'd5, 8'hB6);
            wait_frame;
            check("MOSI_B6", mosi_cap, 8'hB6);
            repeat(3) @(posedge PCLK);
            check("RX_C3",   DUT.u_shift_reg.temp_reg, 8'hC3);
        end
        begin : TC5_RX
            drive_miso(8'hC3);
        end
    join
 
    repeat(3) @(posedge PCLK);
 
    // ----------------------------------------------------------------
    // TC6 : Back-to-back  0x12 then 0x34
    // ----------------------------------------------------------------
    $display("\n[%0t] ===== TC6: Back-to-back TX 0x12 then 0x34 =====", $time);
    apb_write(3'd5, 8'h12);
    wait_frame;
    check("MOSI_12", mosi_cap, 8'h12);
 
    repeat(3) @(posedge PCLK);
 
    apb_write(3'd5, 8'h34);
    wait_frame;
    check("MOSI_34", mosi_cap, 8'h34);
 
    // ----------------------------------------------------------------
    // Summary
    // ----------------------------------------------------------------
    repeat(3) @(posedge PCLK);
    $display("\n[%0t] ===== Simulation complete =====", $time);
    $display("[%0t] PASS=%0d  FAIL=%0d", $time, pass_cnt, fail_cnt);
    $finish;
end
 
endmodule