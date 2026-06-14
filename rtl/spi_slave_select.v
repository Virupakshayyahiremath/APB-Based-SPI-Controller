`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 20.01.2026 20:48:20
// Design Name: 
// Module Name: spi_slave_select
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


module spi_slave_select (
    input            PCLK,
    input            PRESET_n,
    input            mstr_i,
    input            spiswai_i,
    input  [1:0]     spi_mode_i,      
    input            send_data_i,
    input  [15:0]    BaudRateDivisor_i,
 
    output reg       receive_data_o,
    output reg       ss_o,
    output           tip_o
);
 
    reg  [15:0] count_s;
    reg         rcv_s;
 
    wire [15:0] target_s;
    wire        hit;          // count_s <= target_s - 1  (frame running)
    wire        hit1;         // count_s == target_s - 1  (last frame cycle)
    wire        spi_run;
    wire        spi_wait;
    wire        mode_ok;
    wire        enable;       

    assign target_s = BaudRateDivisor_i * 8;
 
    assign spi_run  = (spi_mode_i == 2'b10);          
    assign spi_wait = (spi_mode_i == 2'b01);
    assign mode_ok  = spi_run | spi_wait;
 
    assign enable   = (~spiswai_i) & mode_ok & mstr_i; 
 
    // hit  : frame is actively counting  (count_s <= target_s - 1)
    // hit1 : very last count value        (count_s == target_s - 1)
    assign hit  = (count_s <= (target_s - 1'b1));
    assign hit1 = (count_s == (target_s - 1'b1));
 
    // tip_o: complement of ss_o  
    assign tip_o = ~ss_o;
 
    always @(posedge PCLK or negedge PRESET_n) begin
        if (!PRESET_n)
            count_s <= 16'hFFFF;
        else if (!enable)
            count_s <= 16'hFFFF;
        else begin                          // enable = 1
            if (send_data_i)
                count_s <= 16'd0;           // load 16'b0  
            else if (hit)
                count_s <= count_s + 1'b1;  // increment  
            else
                count_s <= 16'hFFFF;        // frame done → idle
        end
    end
 
    always @(posedge PCLK or negedge PRESET_n) begin
        if (!PRESET_n)
            rcv_s <= 1'b0;
        else if (!enable)
            rcv_s <= 1'b0;
        else begin                          // enable = 1
            if (send_data_i)
                rcv_s <= 1'b0;
            else if (!hit)
                rcv_s <= 1'b0;
            else
                rcv_s <= hit1;              // 1 only on last count 
        end
    end
 
    always @(posedge PCLK or negedge PRESET_n) begin
        if (!PRESET_n)
            receive_data_o <= 1'b0;
        else
            receive_data_o <= rcv_s;
    end
 
    always @(posedge PCLK or negedge PRESET_n) begin
        if (!PRESET_n)
            ss_o <= 1'b1;
        else if (!enable)
            ss_o <= 1'b1;
        else begin                          // enable = 1
            if (send_data_i)
                ss_o <= 1'b0;               // assert SS  
            else if (hit)
                ss_o <= 1'b0;               // hold SS    
            else
                ss_o <= 1'b1;               // deassert   
        end
    end
 
endmodule