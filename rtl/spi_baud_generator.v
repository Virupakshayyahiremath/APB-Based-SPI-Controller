`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 16.01.2026 20:48:06
// Design Name: 
// Module Name: spi_baud_generator
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: SPI Baud-Rate / Clock Generator
//            Generates sclk, miso-receive strobes, and
//            mosi-send strobes aligned to the SPI mode.
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module spi_baud_generator (
    // ---- System ----
    input        PCLK,
    input        PRESET_n,
 
    // ---- SPI configuration ----
    input  [1:0] spi_mode_i,   // 2'b00 / 2'b01 = master modes
    input        spiswai_i,    // SPI stop-in-wait
    input  [2:0] sppr_i,       // Baud-rate pre-scaler prescaler bits
    input  [2:0] spr_i,        // Baud-rate scaler bits
    input        cpol_i,       // Clock polarity
    input        cpha_i,       // Clock phase
    input        ss_i,         // Slave-select (active-low)
 
    // ---- Outputs ----
    output reg        sclk_o,
    output reg        miso_receive_sclk_o,
    output reg        miso_receive_sclk0_o,
    output reg        mosi_send_sclk_o,
    output reg        mosi_send_sclk0_o,
    output     [11:0] BaudRateDivisor_o
);
 
// ============================================================
// 1.  BAUD-RATE DIVISOR
//     BaudRateDivisor = (SPPR+1) * 2^(SPR+1)
//     Using left-shift for the power-of-2 multiply.
// ============================================================
assign BaudRateDivisor_o = (sppr_i + 1'b1) * (1'b1 << (spr_i + 1'b1));
 
// ============================================================
// 2.  PRE-SCLK  (idle level determined by CPOL)
// ============================================================
wire Pre_Sclk;
assign Pre_Sclk = cpol_i ? 1'b1 : 1'b0;
 
// ============================================================
// 3.  INTERNAL SIGNALS
// ============================================================
reg  [11:0] count;
 
// enable: master mode active, SS asserted (low), not in wait
wire enable;
assign enable = (  (spi_mode_i == 2'b10) || (spi_mode_i == 2'b01)  )
                && (~ss_i)
                && (~spiswai_i);
 
// Half-period compare values
//   hit  fires at  (BaudRateDivisor/2 - 1)  → toggle sclk, latch MISO
//   hit1 fires at  (BaudRateDivisor/2 - 2)  → advance MOSI (one cycle early)
wire hit;
wire hit1;
assign hit  = (count == ((BaudRateDivisor_o >> 1) - 1'b1));
assign hit1 = (count == ((BaudRateDivisor_o >> 1) - 2'b10));
 
// exor_in selects the active sclk edge for sampling / shifting
//   CPOL=0,CPHA=0 → exor_in=0  sample on rising  edge (sclk goes 0→1)
//   CPOL=0,CPHA=1 → exor_in=1  sample on falling edge (sclk goes 1→0)
//   CPOL=1,CPHA=0 → exor_in=1
//   CPOL=1,CPHA=1 → exor_in=0
wire exor_in;
assign exor_in = cpol_i ^ cpha_i;
 
// ============================================================
// 4.  COUNTER
//     Counts from 0 to (BaudRateDivisor/2 - 1) then wraps.
//     Resets to 0 whenever the block is disabled.
// ============================================================
always @(posedge PCLK or negedge PRESET_n) begin
    if (!PRESET_n)
        count <= 12'b0;
    else begin
        if (!enable)
            count <= 12'b0;
        else if (hit)
            count <= 12'b0;
        else
            count <= count + 1'b1;
    end
end
 
// ============================================================
// 5.  SCLK GENERATION
//     Toggles every (BaudRateDivisor/2) PCLK cycles.
//     Idles at Pre_Sclk when disabled.
// ============================================================
always @(posedge PCLK or negedge PRESET_n) begin
    if (!PRESET_n)
        sclk_o <= Pre_Sclk;
    else begin
        if (!enable)
            sclk_o <= Pre_Sclk;
        else if (hit)
            sclk_o <= ~sclk_o;
        // else hold
    end
end
 
// ============================================================
// 6.  MISO RECEIVE STROBES
//
//  exor_in = 1  →  sample on the rising edge of sclk
//                  strobe = miso_receive_sclk0_o
//                  fires when sclk_o is HIGH and hit occurs
//                  (next edge will be falling)
//
//  exor_in = 0  →  sample on the falling edge of sclk
//                  strobe = miso_receive_sclk_o
//                  fires when sclk_o is LOW  and hit occurs
//                  (next edge will be rising)
//
//  The unused strobe is always held at 0.
// ============================================================
always @(posedge PCLK or negedge PRESET_n) begin
    if (!PRESET_n) begin
        miso_receive_sclk_o  <= 1'b0;
        miso_receive_sclk0_o <= 1'b0;
    end
    else begin
        if (exor_in) begin
            // --- sample on sclk rising edge ---
            miso_receive_sclk_o  <= 1'b0;          // unused path → 0
            if (sclk_o && hit)
                miso_receive_sclk0_o <= 1'b1;      // pulse one PCLK wide
            else
                miso_receive_sclk0_o <= 1'b0;
        end
        else begin
            // --- sample on sclk falling edge ---
            miso_receive_sclk0_o <= 1'b0;          // unused path → 0
            if (!sclk_o && hit)
                miso_receive_sclk_o  <= 1'b1;      // pulse one PCLK wide
            else
                miso_receive_sclk_o  <= 1'b0;
        end
    end
end
 
// ============================================================
// 7.  MOSI SEND STROBES
//
//  MOSI data must be placed on the bus BEFORE the sampling edge,
//  so the strobe fires one count earlier (hit1 instead of hit).
//
//  exor_in = 1  →  shift out just before sclk rising edge
//                  strobe = mosi_send_sclk_o
//                  fires when sclk_o is HIGH and hit1 occurs
//
//  exor_in = 0  →  shift out just before sclk falling edge
//                  strobe = mosi_send_sclk0_o
//                  fires when sclk_o is LOW  and hit1 occurs
//
//  The unused strobe is always held at 0.
// ============================================================
always @(posedge PCLK or negedge PRESET_n) begin
    if (!PRESET_n) begin
        mosi_send_sclk_o  <= 1'b0;
        mosi_send_sclk0_o <= 1'b0;
    end
    else begin
        if (exor_in) begin
            // --- shift before sclk rising edge ---
            mosi_send_sclk0_o <= 1'b0;             // unused path → 0
            if (sclk_o && hit1)
                mosi_send_sclk_o  <= 1'b1;
            else
                mosi_send_sclk_o  <= 1'b0;
        end
        else begin
            // --- shift before sclk falling edge ---
            mosi_send_sclk_o  <= 1'b0;             // unused path → 0
            if (!sclk_o && hit1)
                mosi_send_sclk0_o <= 1'b1;
            else
                mosi_send_sclk0_o <= 1'b0;
        end
    end
end
 
endmodule
