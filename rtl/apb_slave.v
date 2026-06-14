`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 23.01.2026 09:26:06
// Design Name: 
// Module Name: apb_slave
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


module apb_slave(
    input        PCLK,
    input        PRESET_n,
    input [2:0]  PADDR_i,
    input        PWRITE_i,
    input        PSEL_i,
    input        PENABLE_i,
    input [7:0]  PWDATA_i,
    input        ss_i,
    input [7:0]  miso_data_i,
    input        receive_data_i,
    input        tip_i,
 
    output reg [7:0] PRDATA_o,
    output           mstr_o,
    output           cpol_o,
    output           cpha_o,
    output           lsbfe_o,
    output           spiswai_o,
    output [2:0]     sppr_o,
    output [2:0]     spr_o,
    output reg       spi_interrupt_request_o,
    output           PREADY_o,
    output           PSLVERR_o,
    output reg       send_data_o,
    output reg [7:0] mosi_data_o,
    output [1:0]     spi_mode_o
    );
    reg [7:0] spi_cr1, spi_cr2, spi_br, spi_dr, spi_sr;
    // -----------------------------------------------------------------------
    // APB FSM  (Image 2)
    // -----------------------------------------------------------------------
    localparam IDLE   = 2'b00,
               SETUP  = 2'b01,
               ENABLE = 2'b10;
 
    wire spe     = spi_cr1[6];
    reg [1:0] state, next_state;
 
    always @(posedge PCLK or negedge PRESET_n) begin
        if (!PRESET_n) state <= IDLE;
        else           state <= next_state;
    end
 
    always @(*) begin
        case (state)
            IDLE   : next_state = (PSEL_i && !PENABLE_i) ? SETUP  : IDLE;
            SETUP  : next_state = (!PSEL_i)              ? IDLE   :
                                  (PSEL_i && PENABLE_i)  ? ENABLE : SETUP;
            ENABLE : next_state = (PSEL_i && !PENABLE_i) ? SETUP  :
                                   PSEL_i                ? SETUP  : IDLE;
            default: next_state = IDLE;
        endcase
    end
 
    // -----------------------------------------------------------------------
    // APB control outputs (Image 4)
    // PREADY / PSLVERR are combinational from state
    // wr_enb / rd_enb are REGISTERED one-cycle strobes
    //   FIX: combinational wr_enb = (state==ENABLE && PWRITE) fires for only
    //        a fraction of a clock when state transitions in. A registered
    //        strobe captures the full posedge reliably.
    // -----------------------------------------------------------------------
    assign PREADY_o  = (state == ENABLE);
    assign PSLVERR_o = (state == ENABLE) && ~tip_i;
 
    reg wr_enb, rd_enb;
 
    always @(posedge PCLK or negedge PRESET_n) begin
        if (!PRESET_n) begin
            wr_enb <= 1'b0;
            rd_enb <= 1'b0;
        end else begin
            wr_enb <= (next_state == ENABLE) &&  PWRITE_i;
            rd_enb <= (next_state == ENABLE) && !PWRITE_i;
        end
    end
 
    // -----------------------------------------------------------------------
    // Register address and data: latch PADDR/PWDATA when entering ENABLE
    // so they are stable when wr_enb fires one cycle later
    // -----------------------------------------------------------------------
    reg [2:0] addr_lat;
    reg [7:0] wdata_lat;
 
    always @(posedge PCLK or negedge PRESET_n) begin
        if (!PRESET_n) begin
            addr_lat  <= 3'b000;
            wdata_lat <= 8'h00;
        end else if (next_state == ENABLE) begin
            addr_lat  <= PADDR_i;
            wdata_lat <= PWDATA_i;
        end
    end
 
    // -----------------------------------------------------------------------
    // SPI Mode FSM  (Image 3)
    // Reset -> SPI_RUN. spe=CR1[6] (0 after reset -> immediately to SPI_WAIT)
    // Transitions:
    //   SPI_RUN  -(!spe)-> SPI_WAIT
    //   SPI_WAIT -(spe)->  SPI_RUN
    //   SPI_WAIT -(spiswai)-> SPI_STOP
    //   SPI_STOP -(!spiswai)-> SPI_WAIT
    //   SPI_STOP -(spe)-> SPI_RUN
    // -----------------------------------------------------------------------
    localparam SPI_RUN  = 2'b10,
               SPI_WAIT = 2'b01,
               SPI_STOP = 2'b00;
 
    reg [1:0] spi_state, spi_next;
 
    always @(posedge PCLK or negedge PRESET_n) begin
        if (!PRESET_n) spi_state <= SPI_RUN;
        else           spi_state <= spi_next;
    end
 
    // spe and spiswai_o are from registers - declared below but used here
    // (Verilog allows forward reference for wires)
    always @(*) begin
        spi_next = spi_state;
        case (spi_state)
            SPI_RUN  : if (!spe)              spi_next = SPI_WAIT;
            SPI_WAIT : if (spe)               spi_next = SPI_RUN;
                  else if (spiswai_o)          spi_next = SPI_STOP;
            SPI_STOP : if (spe)               spi_next = SPI_RUN;
                  else if (!spiswai_o)         spi_next = SPI_WAIT;
            default  :                         spi_next = SPI_RUN;
        endcase
    end
 
    assign spi_mode_o = spi_state;
    wire   mode_ok    = (spi_state != SPI_STOP);
 
    // -----------------------------------------------------------------------
    // Register bank - uses latched addr/wdata for reliable write capture
    // Masks (Image 5):
    //   SPI_CR2 mask = 8'h1B  (bits [4,3,1,0] valid)
    //   SPI_BR  mask = 8'h77  (bits [6:4] and [2:0] valid)
    // -----------------------------------------------------------------------
 
    localparam CR2_MASK = 8'h1B;
    localparam BR_MASK  = 8'h77;
 
    // SPI_CR1 (addr 0, reset 8'h04)
    always @(posedge PCLK or negedge PRESET_n) begin
        if (!PRESET_n)                          spi_cr1 <= 8'h04;
        else if (wr_enb && addr_lat == 3'd0)    spi_cr1 <= wdata_lat;
    end
 
    // SPI_CR2 (addr 1, reset 8'h00, masked)
    always @(posedge PCLK or negedge PRESET_n) begin
        if (!PRESET_n)                          spi_cr2 <= 8'h00;
        else if (wr_enb && addr_lat == 3'd1)    spi_cr2 <= wdata_lat & CR2_MASK;
    end
 
    // SPI_BR  (addr 2, reset 8'h00, masked)
    always @(posedge PCLK or negedge PRESET_n) begin
        if (!PRESET_n)                          spi_br <= 8'h00;
        else if (wr_enb && addr_lat == 3'd2)    spi_br <= wdata_lat & BR_MASK;
    end
 
    // -----------------------------------------------------------------------
    // Control register bit extractions (Image 9)
    // -----------------------------------------------------------------------
    wire spie    = spi_cr1[7];
    wire sptie   = spi_cr1[5];
    wire ssoe    = spi_cr1[1];
    wire modfen  = spi_cr2[4];
 
    assign mstr_o    = spi_cr1[4];
    assign cpol_o    = spi_cr1[3];
    assign cpha_o    = spi_cr1[2];
    assign lsbfe_o   = spi_cr1[0];
    assign spiswai_o = spi_cr2[1];
    assign sppr_o    = spi_br[6:4];
    assign spr_o     = spi_br[2:0];
 
    // -----------------------------------------------------------------------
    // Status flags (Image 9)
    // -----------------------------------------------------------------------
    wire modf  = (~ss_i) & mstr_o & modfen & (~ssoe);
    wire sptef = (spi_dr == 8'h00);
    wire spif  = (spi_dr != 8'h00);
 
    // SPI_SR (addr 3, reset 8'b0010_0000) (Image 4)
    always @(posedge PCLK or negedge PRESET_n) begin
        if (!PRESET_n) spi_sr <= 8'b0010_0000;
        else           spi_sr <= {spif, 1'b0, sptef, modf, 4'b0000};
    end
 
    // -----------------------------------------------------------------------
    // SPI_DR (addr 5) (Image 6)
    // Write path : wr_enb && addr==5 -> latch wdata_lat
    // Receive path: mode_ok && receive_data_i -> latch miso_data_i
    // -----------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESET_n) begin
        if (!PRESET_n)                          spi_dr <= 8'h00;
        else if (wr_enb && addr_lat == 3'd5)    spi_dr <= wdata_lat;
        else if (mode_ok && receive_data_i)     spi_dr <= miso_data_i;
    end
 
    // -----------------------------------------------------------------------
    // send_data_o (Image 7)
    // Set  : wr_enb to DR, mode active, new data != miso (not echo)
    // Clear: else (1-cycle pulse)
    // -----------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESET_n) begin
        if (!PRESET_n)
            send_data_o <= 1'b0;
        else if (wr_enb && (addr_lat == 3'd5) && mode_ok
                         && (wdata_lat != miso_data_i))
            send_data_o <= 1'b1;
        else
            send_data_o <= 1'b0;
    end
 
    // -----------------------------------------------------------------------
    // mosi_data_o (Image 8)
    // Same condition as send_data - output PWDATA, else 0
    // -----------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESET_n) begin
        if (!PRESET_n)
            mosi_data_o <= 8'h00;
        else if (wr_enb && (addr_lat == 3'd5) && mode_ok
                         && (wdata_lat != miso_data_i))
            mosi_data_o <= wdata_lat;
        else
            mosi_data_o <= 8'h00;
    end
 
    // -----------------------------------------------------------------------
    // PRDATA_o read mux (Image 10)
    // Combinational; valid while rd_enb=1
    // -----------------------------------------------------------------------
    always @(*) begin
        if (rd_enb) begin
            case (addr_lat)
                3'd0 : PRDATA_o = spi_cr1;
                3'd1 : PRDATA_o = spi_cr2;
                3'd2 : PRDATA_o = spi_br;
                3'd3 : PRDATA_o = spi_sr;
                3'd5 : PRDATA_o = spi_dr;
                default: PRDATA_o = 8'h00;
            endcase
        end else
            PRDATA_o = 8'h00;
    end
 
    // -----------------------------------------------------------------------
    // SPI Interrupt Request (Image 11)
    // -----------------------------------------------------------------------
    always @(*) begin
        case ({spie, sptie})
            2'b00 : spi_interrupt_request_o = 1'b0;
            2'b10 : spi_interrupt_request_o = spif | modf;
            2'b01 : spi_interrupt_request_o = sptef;
            2'b11 : spi_interrupt_request_o = spif | modf | sptef;
        endcase
    end
 
endmodule