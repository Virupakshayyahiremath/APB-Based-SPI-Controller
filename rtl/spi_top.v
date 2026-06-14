`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09.06.2026 16:06:33
// Design Name: 
// Module Name: spi_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: APB-based SPI controller top module.
//               Connects four sub-blocks:
//                 1. spi_baud_generator  - SCLK and sample-enable generation
//                 2. spi_slave_select    - SS#, TIP, receive_data pulse
//                 3. shift_reg           - MOSI shift-out / MISO shift-in
//                 4. apb_slave           - APB register map, FSMs, interrupt
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module spi_top (
    // APB bus
    input            PCLK,
    input            PRESET_n,
    input  [2:0]     PADDR_i,
    input            PWRITE_i,
    input            PSEL_i,
    input            PENABLE_i,
    input  [7:0]     PWDATA_i,
 
    // SPI physical pins
    input            miso_i,
 
    // APB read-data and response
    output [7:0]     PRDATA_o,
    output           PREADY_o,
    output           PSLVERR_o,
 
    // SPI physical outputs
    output           sclk_o,
    output           mosi_o,
    output           ss_o,
 
    // Interrupt to system
    output           spi_interrupt_req_o
);
 
    // =========================================================================
    // Internal wires - grouped by source sub-block
    // =========================================================================
 
    // --- apb_slave outputs ---
    wire        mstr_w;
    wire        cpol_w;
    wire        cpha_w;
    wire        lsbfe_w;
    wire        spiswai_w;
    wire [2:0]  sppr_w;
    wire [2:0]  spr_w;
    wire        send_data_w;
    wire [7:0]  mosi_data_w;   // parallel data to be shifted out
    wire [1:0]  spi_mode_w;
 
    // --- spi_baud_generator outputs ---
    wire        miso_receive_sclk_w;
    wire        miso_receive_sclk0_w;
    wire        mosi_send_sclk_w;
    wire        mosi_send_sclk0_w;
    wire [11:0] BaudRateDivisor_12_w;
 
    // 12-bit divisor zero-extended to 16 bits for spi_slave_select
    wire [15:0] BaudRateDivisor_16_w;
    assign BaudRateDivisor_16_w = {4'b0000, BaudRateDivisor_12_w};
 
    // --- spi_slave_select outputs ---
    wire        receive_data_w;  // 1-cycle pulse: frame done, latch MISO
    wire        ss_w;            // active-low slave select
    wire        tip_w;           // transfer-in-progress = ~ss_w
 
    // --- shift_reg outputs ---
    wire [7:0]  data_miso_w;     // received byte (to apb_slave as miso_data)
 
    // =========================================================================
    // 1. APB Slave Interface
    // =========================================================================
    apb_slave u_apb_slave (
        // APB bus
        .PCLK               (PCLK),
        .PRESET_n           (PRESET_n),
        .PADDR_i            (PADDR_i),
        .PWRITE_i           (PWRITE_i),
        .PSEL_i             (PSEL_i),
        .PENABLE_i          (PENABLE_i),
        .PWDATA_i           (PWDATA_i),
 
        // Feedback from SPI datapath
        .ss_i               (ss_w),
        .miso_data_i        (data_miso_w),
        .receive_data_i     (receive_data_w),
        .tip_i              (tip_w),
 
        // APB response
        .PRDATA_o           (PRDATA_o),
        .PREADY_o           (PREADY_o),
        .PSLVERR_o          (PSLVERR_o),
 
        // SPI configuration to other sub-blocks
        .mstr_o             (mstr_w),
        .cpol_o             (cpol_w),
        .cpha_o             (cpha_w),
        .lsbfe_o            (lsbfe_w),
        .spiswai_o          (spiswai_w),
        .sppr_o             (sppr_w),
        .spr_o              (spr_w),
        .spi_mode_o         (spi_mode_w),
 
        // Data path control
        .send_data_o        (send_data_w),
        .mosi_data_o        (mosi_data_w),
 
        // Interrupt
        .spi_interrupt_request_o (spi_interrupt_req_o)
    );
 
    // =========================================================================
    // 2. SPI Baud Rate Generator
    // =========================================================================
    spi_baud_generator u_baud_gen (
        .PCLK               (PCLK),
        .PRESET_n           (PRESET_n),
 
        // Configuration from APB slave
        .spi_mode_i         (spi_mode_w),
        .spiswai_i          (spiswai_w),
        .sppr_i             (sppr_w),
        .spr_i              (spr_w),
        .cpol_i             (cpol_w),
        .cpha_i             (cpha_w),
 
        // SS feedback (baud gen only runs when SS is asserted)
        .ss_i               (ss_w),
 
        // SCLK to top-level pin
        .sclk_o             (sclk_o),
 
        // Sample/shift enable strobes to shift_reg
        .miso_receive_sclk_o  (miso_receive_sclk_w),
        .miso_receive_sclk0_o (miso_receive_sclk0_w),
        .mosi_send_sclk_o     (mosi_send_sclk_w),
        .mosi_send_sclk0_o    (mosi_send_sclk0_w),
 
        // Divisor to slave_select (12-bit)
        .BaudRateDivisor_o    (BaudRateDivisor_12_w)
    );
 
    // =========================================================================
    // 3. SPI Slave Select
    // =========================================================================
    spi_slave_select u_slave_select (
        .PCLK               (PCLK),
        .PRESET_n           (PRESET_n),
 
        // Configuration from APB slave
        .mstr_i             (mstr_w),
        .spiswai_i          (spiswai_w),
        .spi_mode_i         (spi_mode_w),
        .send_data_i        (send_data_w),
 
        // Baud divisor (zero-extended 12→16 bit)
        .BaudRateDivisor_i  (BaudRateDivisor_16_w),
 
        // Outputs
        .receive_data_o     (receive_data_w),   // → apb_slave, shift_reg
        .ss_o               (ss_w),             // → all blocks + top pin
        .tip_o              (tip_w)             // → apb_slave
    );
 
    // =========================================================================
    // 4. Shift Register (SPI shifter)
    // =========================================================================
    shift_reg u_shift_reg (
        .PCLK               (PCLK),
        .PRESET_n           (PRESET_n),
 
        // Control
        .ss_i               (ss_w),
        .send_data_i        (send_data_w),
        .lsbfe_i            (lsbfe_w),
        .cpha_i             (cpha_w),
        .cpol_i             (cpol_w),
 
        // Sample/shift strobes from baud generator
        .miso_receive_sclk_i  (miso_receive_sclk_w),
        .miso_receive_sclk0_i (miso_receive_sclk0_w),
        .mosi_send_sclk_i     (mosi_send_sclk_w),
        .mosi_send_sclk0_i    (mosi_send_sclk0_w),
 
        // Parallel data from APB slave (byte to transmit)
        .data_mosi_i        (mosi_data_w),
 
        // MISO serial input from SPI pin
        .miso_i             (miso_i),
 
        // Receive pulse from slave_select (frame done)
        .receive_data_i     (receive_data_w),
 
        // MOSI serial output to SPI pin
        .mosi_o             (mosi_o),
 
        // Received byte → APB slave register file
        .data_miso_o        (data_miso_w)
    );
 
    // ss_o top-level pin driven directly from slave_select
    assign ss_o = ss_w;
 
endmodule
