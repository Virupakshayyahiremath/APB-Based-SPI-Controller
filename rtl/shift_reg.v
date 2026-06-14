`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.02.2026 18:10:51
// Design Name: 
// Module Name: shift_reg
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


// Description : SPI shift register - transmit (MOSI) and receive (MISO)
//               Supports all 4 SPI modes (cpol/cpha) and LSB/MSB first.
module shift_reg(
    input            PCLK,
    input            PRESET_n,
    input            ss_i,               // 1 = deasserted, 0 = active/asserted
    input            send_data_i,
    input            lsbfe_i,            // 1 = LSB first, 0 = MSB first
    input            cpha_i,
    input            cpol_i,
    input            miso_receive_sclk_i,
    input            miso_receive_sclk0_i,
    input            mosi_send_sclk_i,
    input            mosi_send_sclk0_i,
    input  [7:0]     data_mosi_i,
    input            miso_i,
    input            receive_data_i,
 
    output reg       mosi_o,
    output     [7:0] data_miso_o
);
    reg [7:0] shift_register;   // transmit holding register
    reg [7:0] temp_reg;         // received-data latch (shown to APB)
    reg [7:0] temp;             // bit-by-bit MISO assembly register
    reg [2:0] count,  count1;   // MOSI bit indices  (LSB-first / MSB-first)
    reg [2:0] count2, count3;   // MISO bit indices  (LSB-first / MSB-first)
 
    // clk_wire selects which sclk edge the block responds to
    // Image diagrams: cpha ^ cpol selects the active clock path
    wire clk_wire;
    assign clk_wire = (cpha_i ^ cpol_i);   // 1 → use sclk, 0 → use sclk0
 
    // -----------------------------------------------------------------------
    // Transmit holding register (shift_register) - Image 2 left block
    //   Reset  → 8'b0
    //   send_data=1 → load data_mosi_i
    //   else → hold
    // -----------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESET_n) begin
        if (!PRESET_n)
            shift_register <= 8'd0;
        else if (send_data_i)
            shift_register <= data_mosi_i;
    end
 
    // -----------------------------------------------------------------------
    // Received-data latch (temp_reg) - Image 2 right mux/FF
    //   receive_data=1 → latch temp into temp_reg
    // -----------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESET_n) begin
        if (!PRESET_n)
            temp_reg <= 8'h00;
        else if (receive_data_i)
            temp_reg <= temp;
    end
 
    // data_miso_o: 0 when receive_data inactive, temp_reg otherwise
    assign data_miso_o = receive_data_i ? temp_reg : 8'h00;
 
    // -----------------------------------------------------------------------
    // MOSI bit counter - count (LSB-first) / count1 (MSB-first) 
    //   Reset / ss deasserted → count=0, count1=7
    //   clk_wire=1 & mosi_send_sclk_i  → increment/decrement
    //   clk_wire=0 & mosi_send_sclk0_i → increment/decrement
    // -----------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESET_n) begin
        if (!PRESET_n) begin
            count  <= 3'd0;
            count1 <= 3'd7;
        end
        else if (ss_i) begin          
            count  <= count;
            count1 <= count1;
        end
        else begin                    // ss active (!ss_i)
            if (clk_wire && mosi_send_sclk_i) begin
                if (lsbfe_i)
                    count  <= (count  == 3'd7) ? 3'd0 : count  + 1'b1;
                else
                    count1 <= (count1 == 3'd0) ? 3'd7 : count1 - 1'b1;
            end
            else if (!clk_wire && mosi_send_sclk0_i) begin
                if (lsbfe_i)
                    count  <= (count  == 3'd7) ? 3'd0 : count  + 1'b1;
                else
                    count1 <= (count1 == 3'd0) ? 3'd7 : count1 - 1'b1;
            end
        end
    end
 
    // -----------------------------------------------------------------------
    // MISO bit counter - count2 (LSB-first) / count3 (MSB-first) 
    //   Mirror of MOSI counter but driven by miso_receive_sclk edges
    //   clk_wire=1 → sample on sclk0 edge (miso_receive_sclk0_i)
    //   clk_wire=0 → sample on sclk  edge (miso_receive_sclk_i)
    // -----------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESET_n) begin
        if (!PRESET_n) begin
            count2 <= 3'd0;
            count3 <= 3'd7;
        end
        else if (ss_i) begin
            count2 <= 3'd0;
            count3 <= 3'd7;
        end
        else begin
            if ((clk_wire && miso_receive_sclk0_i) || (!clk_wire && miso_receive_sclk_i)) begin
                if (lsbfe_i)
                    count2 <= (count2 == 3'd7) ? 3'd0 : count2 + 1'b1;
                else
                    count3 <= (count3 == 3'd0) ? 3'd7 : count3 - 1'b1;
            end
        end
    end
 
    // -----------------------------------------------------------------------
    // MISO sample/assemble into temp 
    // -----------------------------------------------------------------------
    wire miso_sample_en;
    assign miso_sample_en = (clk_wire  && miso_receive_sclk0_i) ||
                            (!clk_wire && miso_receive_sclk_i);
 
    always @(posedge PCLK or negedge PRESET_n) begin
        if (!PRESET_n)
            temp <= 8'h00;
        else if (!ss_i && miso_sample_en) begin
            if (lsbfe_i)
                temp[count2] <= miso_i;
            else
                temp[count3] <= miso_i;
        end
    end
 
    // -----------------------------------------------------------------------
    //   Reset / ss deasserted → 1'b0
    //   Active: drive shift_register[count] (LSB-first) or [count1] (MSB-first)
    //   on the appropriate sclk edge
    // -----------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESET_n) begin
        if (!PRESET_n)
            mosi_o <= 1'b0;
        else if (ss_i)
            mosi_o <= 1'b0;      // ss deasserted → MOSI idle low
        else begin               // ss active
            if (clk_wire && mosi_send_sclk_i)
                mosi_o <= lsbfe_i ? shift_register[count] : shift_register[count1];
            else if (!clk_wire && mosi_send_sclk0_i)
                mosi_o <= lsbfe_i ? shift_register[count] : shift_register[count1];
            // else: hold MOSI between edges
        end
    end
 
endmodule
