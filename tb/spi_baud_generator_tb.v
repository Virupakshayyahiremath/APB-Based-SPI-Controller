`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 16.01.2026 21:58:08
// Design Name: 
// Module Name: spi_baud_generator_tb
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


module spi_baud_generator_tb;
 
// ----------------------------------------------------------------
// DUT ports
// ----------------------------------------------------------------
reg        PCLK;
reg        PRESET_n;
reg  [1:0] spi_mode_i;
reg        spiswai_i;
reg  [2:0] sppr_i, spr_i;
reg        cpol_i, cpha_i;
reg        ss_i;
 
wire        sclk_o;
wire        miso_receive_sclk_o;
wire        miso_receive_sclk0_o;
wire        mosi_send_sclk_o;
wire        mosi_send_sclk0_o;
wire [11:0] BaudRateDivisor_o;
 
// ----------------------------------------------------------------
// Encoding constants - MUST match apb_slave localparams
// ----------------------------------------------------------------
localparam SPI_RUN  = 2'b10;
localparam SPI_WAIT = 2'b01;
localparam SPI_STOP = 2'b00;
 
// ----------------------------------------------------------------
// DUT instantiation
// ----------------------------------------------------------------
spi_baud_generator dut (
    .PCLK                 (PCLK),
    .PRESET_n             (PRESET_n),
    .spi_mode_i           (spi_mode_i),
    .spiswai_i            (spiswai_i),
    .sppr_i               (sppr_i),
    .spr_i                (spr_i),
    .cpol_i               (cpol_i),
    .cpha_i               (cpha_i),
    .ss_i                 (ss_i),
    .sclk_o               (sclk_o),
    .miso_receive_sclk_o  (miso_receive_sclk_o),
    .miso_receive_sclk0_o (miso_receive_sclk0_o),
    .mosi_send_sclk_o     (mosi_send_sclk_o),
    .mosi_send_sclk0_o    (mosi_send_sclk0_o),
    .BaudRateDivisor_o    (BaudRateDivisor_o)
);
 
// ----------------------------------------------------------------
// Clock - 10 ns period (100 MHz)
// ----------------------------------------------------------------
initial PCLK = 1'b0;
always #5 PCLK = ~PCLK;
 
// ----------------------------------------------------------------
// TASKS
// ----------------------------------------------------------------
 
// Active-low reset
task reset_dut;
begin
    PRESET_n = 1'b0;
    repeat(4) @(posedge PCLK);
    PRESET_n = 1'b1;
    @(posedge PCLK);
end
endtask
 
// Safe idle state
task initialize;
begin
    spi_mode_i = SPI_STOP;  // 2'b00 - disabled
    spiswai_i  = 1'b0;
    sppr_i     = 3'b000;
    spr_i      = 3'b000;
    cpol_i     = 1'b0;
    cpha_i     = 1'b0;
    ss_i       = 1'b1;      // deasserted (active-low)
end
endtask
 
// Set clock polarity / phase
task clock_mode;
    input cpol, cpha;
begin
    cpol_i = cpol;
    cpha_i = cpha;
end
endtask
 
// Set baud-rate divisor inputs
task set_divisor;
    input [2:0] sppr, spr;
begin
    sppr_i = sppr;
    spr_i  = spr;
end
endtask
 
// Set SPI enable controls
// mode must use SPI_RUN/SPI_WAIT/SPI_STOP constants above
task set_enable;
    input        ss, swai;
    input [1:0]  mode;
begin
    ss_i       = ss;
    spiswai_i  = swai;
    spi_mode_i = mode;
end
endtask
 
// Flush: deassert ss + stop mode for a full BRD period to cleanly reset
task flush_state;
begin
    set_enable(1'b1, 1'b0, SPI_STOP);
    repeat(BaudRateDivisor_o) @(posedge PCLK);
end
endtask
 
// Wait N full sclk half-periods (each = BaudRateDivisor/2 PCLKs)
task wait_half_periods;
    input integer n;
    integer i;
begin
    for (i = 0; i < n; i = i + 1)
        repeat(BaudRateDivisor_o >> 1) @(posedge PCLK);
end
endtask
 
// ----------------------------------------------------------------
// DISPLAY HELPER
// ----------------------------------------------------------------
task print_state;
begin
    $display("T=%0t | sclk=%b | CPOL=%b CPHA=%b | BRD=%0d | cnt=%0d | miso_sclk=%b miso_sclk0=%b | mosi_sclk=%b mosi_sclk0=%b",
             $time, sclk_o, cpol_i, cpha_i, BaudRateDivisor_o, dut.count,
             miso_receive_sclk_o, miso_receive_sclk0_o,
             mosi_send_sclk_o,    mosi_send_sclk0_o);
end
endtask
 
// ----------------------------------------------------------------
// STIMULUS
// ----------------------------------------------------------------
initial begin
    $dumpfile("spi_baud_generator_tb.vcd");
    $dumpvars(0, spi_baud_generator_tb);
 
    initialize();
    reset_dut();
 
    // ============================================================
    // TEST 1 : CPOL=0, CPHA=0  (exor_in=0)
    //          SPPR=1, SPR=0 → BRD=4, half-period=2 PCLKs
    //          FIX: mode = SPI_RUN (2'b10) not 2'b00
    // ============================================================
    $display("\n===== TEST 1 : CPOL=0 CPHA=0, BRD=4 =====");
    clock_mode(0, 0);
    set_divisor(3'b001, 3'b000);
    flush_state();                          // clean start
    set_enable(1'b0, 1'b0, SPI_RUN);       // ss=0, mode=SPI_RUN
    wait_half_periods(8);
    flush_state();
 
    // ============================================================
    // TEST 2 : CPOL=0, CPHA=1  (exor_in=1)
    //          FIX: mode = SPI_RUN
    // ============================================================
    $display("\n===== TEST 2 : CPOL=0 CPHA=1, BRD=4 =====");
    clock_mode(0, 1);
    set_divisor(3'b001, 3'b000);
    flush_state();
    set_enable(1'b0, 1'b0, SPI_RUN);
    wait_half_periods(8);
    flush_state();
 
    // ============================================================
    // TEST 3 : CPOL=1, CPHA=0  (exor_in=1)
    //          sclk idles HIGH when disabled
    // ============================================================
    $display("\n===== TEST 3 : CPOL=1 CPHA=0, BRD=4 =====");
    clock_mode(1, 0);
    set_divisor(3'b001, 3'b000);
    flush_state();
    set_enable(1'b0, 1'b0, SPI_RUN);
    wait_half_periods(8);
    flush_state();
 
    // ============================================================
    // TEST 4 : CPOL=1, CPHA=1  (exor_in=0)
    // ============================================================
    $display("\n===== TEST 4 : CPOL=1 CPHA=1, BRD=4 =====");
    clock_mode(1, 1);
    set_divisor(3'b001, 3'b000);
    flush_state();
    set_enable(1'b0, 1'b0, SPI_RUN);
    wait_half_periods(8);
    flush_state();
 
    // ============================================================
    // TEST 5 : Larger divisor - SPPR=2, SPR=2
    //          BRD = (2+1)*2^(2+1) = 24, half-period=12 PCLKs
    // ============================================================
    $display("\n===== TEST 5 : CPOL=0 CPHA=0, BRD=24 =====");
    clock_mode(0, 0);
    set_divisor(3'b010, 3'b010);
    flush_state();
    set_enable(1'b0, 1'b0, SPI_RUN);
    wait_half_periods(6);
    flush_state();
 
    // ============================================================
    // TEST 6 : SS de-assert mid-transfer then re-assert
    //          FIX: wait full BRD after deassert before re-assert
    // ============================================================
    $display("\n===== TEST 6 : SS toggle mid-transfer =====");
    clock_mode(0, 0);
    set_divisor(3'b001, 3'b000);
    flush_state();
    set_enable(1'b0, 1'b0, SPI_RUN);
    wait_half_periods(4);               // 2 sclk cycles active
    // Deassert SS - sclk must return to idle (0 for CPOL=0)
    set_enable(1'b1, 1'b0, SPI_RUN);
    repeat(BaudRateDivisor_o) @(posedge PCLK);   // full flush
    $display("T=%0t | After SS deassert: sclk_o=%b (expect 0)", $time, sclk_o);
    // Re-assert SS - transfer resumes cleanly from cycle start
    set_enable(1'b0, 1'b0, SPI_RUN);
    wait_half_periods(4);
    flush_state();
 
    // ============================================================
    // TEST 7 : SPISWAI disable - sclk must freeze at idle
    //          FIX: wait full BRD before re-enabling
    // ============================================================
    $display("\n===== TEST 7 : SPISWAI disable =====");
    clock_mode(0, 0);
    set_divisor(3'b001, 3'b000);
    flush_state();
    set_enable(1'b0, 1'b0, SPI_RUN);
    wait_half_periods(3);
    // Assert SPISWAI - baud gen must stop
    set_enable(1'b0, 1'b1, SPI_RUN);
    repeat(BaudRateDivisor_o) @(posedge PCLK);   // full flush
    $display("T=%0t | After SPISWAI: sclk_o=%b (expect 0)", $time, sclk_o);
    flush_state();
    set_enable(1'b0, 1'b0, SPI_RUN);
    wait_half_periods(4);
    flush_state();
 
    // ============================================================
    // TEST 8 : SPI_STOP mode - sclk must NOT toggle
    //          FIX: drive SPI_STOP (2'b00) not SPI_RUN (2'b10)
    //          Previous TB drove 2'b10 calling it "slave mode"
    //          but 2'b10 = SPI_RUN = enables baud gen!
    // ============================================================
    $display("\n===== TEST 8 : SPI_STOP mode (2b00) - no toggle =====");
    clock_mode(0, 0);
    set_divisor(3'b001, 3'b000);
    flush_state();
    set_enable(1'b0, 1'b0, SPI_STOP);   // SPI_STOP = 2'b00
    repeat(20) @(posedge PCLK);
    $display("T=%0t | SPI_STOP: sclk_o=%b (expect 0, no toggle)", $time, sclk_o);
    // Also verify SPI_WAIT (2'b01) - should enable baud gen
    $display("T=%0t | Switching to SPI_WAIT (2b01)...", $time);
    set_enable(1'b0, 1'b0, SPI_WAIT);
    wait_half_periods(4);
    $display("T=%0t | SPI_WAIT: sclk_o=%b (expect toggling)", $time, sclk_o);
    flush_state();
 
    // ============================================================
    // TEST 9 : Reset during active transfer
    // ============================================================
    $display("\n===== TEST 9 : Reset during active transfer =====");
    clock_mode(0, 1);
    set_divisor(3'b001, 3'b000);
    flush_state();
    set_enable(1'b0, 1'b0, SPI_STOP);
    wait_half_periods(3);
    $display("T=%0t | Asserting reset mid-transfer", $time);
    PRESET_n = 1'b0;
    repeat(2) @(posedge PCLK);
    $display("T=%0t | During reset: sclk_o=%b count=%0d", $time, sclk_o, dut.count);
    PRESET_n = 1'b1;
    repeat(2) @(posedge PCLK);
    $display("T=%0t | After reset: sclk_o=%b count=%0d (expect 0)", $time, sclk_o, dut.count);
    flush_state();
 
    $display("\n===== ALL TESTS COMPLETE =====");
    #20;
    $finish;
end
 
// ----------------------------------------------------------------
// MONITORS
// ----------------------------------------------------------------
always @(posedge sclk_o or negedge sclk_o)
    print_state();
 
always @(posedge miso_receive_sclk_o or posedge miso_receive_sclk0_o or
         posedge mosi_send_sclk_o    or posedge mosi_send_sclk0_o) begin
    $display("T=%0t | STROBE >> miso_sclk=%b miso_sclk0=%b mosi_sclk=%b mosi_sclk0=%b",
             $time,
             miso_receive_sclk_o, miso_receive_sclk0_o,
             mosi_send_sclk_o,    mosi_send_sclk0_o);
end
 
endmodule