`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06.02.2026 09:54:43
// Design Name: 
// Module Name: apb_slave_tb
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


module apb_slave_tb();
 
    reg        PCLK;
    reg        PRESET_n;
    reg [2:0]  PADDR_i;
    reg        PWRITE_i;
    reg        PSEL_i;
    reg        PENABLE_i;
    reg [7:0]  PWDATA_i;
    reg        ss_i;
    reg [7:0]  miso_data_i;
    reg        receive_data_i;
    reg        tip_i;
 
    wire [7:0] PRDATA_o;
    wire       mstr_o;
    wire       cpol_o;
    wire       cpha_o;
    wire       lsbfe_o;
    wire       spiswai_o;
    wire [2:0] sppr_o;
    wire [2:0] spr_o;
    wire       spi_interrupt_request_o;
    wire       PREADY_o;
    wire       PSLVERR_o;
    wire       send_data_o;
    wire [7:0] mosi_data_o;
    wire [1:0] spi_mode_o;
 
    apb_slave dut (
        .PCLK                    (PCLK),
        .PRESET_n                (PRESET_n),
        .PADDR_i                 (PADDR_i),
        .PWRITE_i                (PWRITE_i),
        .PSEL_i                  (PSEL_i),
        .PENABLE_i               (PENABLE_i),
        .PWDATA_i                (PWDATA_i),
        .ss_i                    (ss_i),
        .miso_data_i             (miso_data_i),
        .receive_data_i          (receive_data_i),
        .tip_i                   (tip_i),
        .PRDATA_o                (PRDATA_o),
        .mstr_o                  (mstr_o),
        .cpol_o                  (cpol_o),
        .cpha_o                  (cpha_o),
        .lsbfe_o                 (lsbfe_o),
        .spiswai_o               (spiswai_o),
        .sppr_o                  (sppr_o),
        .spr_o                   (spr_o),
        .spi_interrupt_request_o (spi_interrupt_request_o),
        .PREADY_o                (PREADY_o),
        .PSLVERR_o               (PSLVERR_o),
        .send_data_o             (send_data_o),
        .mosi_data_o             (mosi_data_o),
        .spi_mode_o              (spi_mode_o)
    );
 
    initial PCLK = 0;
    always #5 PCLK = ~PCLK;
 
    // -----------------------------------------------------------------------
    // Task: initialize
    // -----------------------------------------------------------------------
    task initialize;
        begin
            PSEL_i         = 1'b0;
            PENABLE_i      = 1'b0;
            PWRITE_i       = 1'b0;
            PADDR_i        = 3'b000;
            PWDATA_i       = 8'h00;
            ss_i           = 1'b1;
            miso_data_i    = 8'h00;
            receive_data_i = 1'b0;
            tip_i          = 1'b1;
        end
    endtask
 
    // -----------------------------------------------------------------------
    // Task: apply_reset
    // -----------------------------------------------------------------------
    task apply_reset;
        begin
            PRESET_n = 1'b0;
            initialize;
            repeat(3) @(posedge PCLK);
            #1;
            PRESET_n = 1'b1;
            @(posedge PCLK); #1;
        end
    endtask
 
    // -----------------------------------------------------------------------
    // Task: apb_write  (4-cycle: SETUP, ENABLE, hold, deassert)
    //
    //   Cycle 0 posedge+#1 : drive PSEL=1, PENABLE=0, PWRITE=1, PADDR, PWDATA
    //   Cycle 1 posedge    : FSM IDLE->SETUP; addr_lat/wdata_lat captured
    //   Cycle 1 posedge+#1 : drive PENABLE=1
    //   Cycle 2 posedge    : FSM SETUP->ENABLE; wr_enb registers as 1
    //   Cycle 3 posedge    : wr_enb=1 fires, register latches data
    //   Cycle 3 posedge+#1 : deassert all
    // -----------------------------------------------------------------------
    task apb_write(input [2:0] addr, input [7:0] data);
        begin
            @(posedge PCLK); #1;
            PADDR_i   = addr;
            PWDATA_i  = data;
            PWRITE_i  = 1'b1;
            PSEL_i    = 1'b1;
            PENABLE_i = 1'b0;
 
            @(posedge PCLK); #1;
            PENABLE_i = 1'b1;
 
            @(posedge PCLK); #1;
            // wr_enb fires at this posedge - hold signals stable
 
            @(posedge PCLK); #1;
            PSEL_i    = 1'b0;
            PENABLE_i = 1'b0;
            PWRITE_i  = 1'b0;
        end
    endtask
 
    // -----------------------------------------------------------------------
    // Task: apb_read  (3-cycle: SETUP, ENABLE, sample+deassert)
    //
    //   Cycle 0 posedge+#1 : drive PSEL=1, PENABLE=0, PWRITE=0, PADDR
    //   Cycle 1 posedge    : FSM IDLE->SETUP; addr_lat captured
    //   Cycle 1 posedge+#1 : drive PENABLE=1
    //   Cycle 2 posedge    : FSM SETUP->ENABLE; rd_enb registers as 1
    //   Cycle 2 posedge+#2 : rd_enb=1, PRDATA valid - SAMPLE HERE
    //   Cycle 2 posedge+#3 : deassert
    // -----------------------------------------------------------------------
    task apb_read(input [2:0] addr, output [7:0] data);
        begin
            @(posedge PCLK); #1;
            PADDR_i   = addr;
            PWRITE_i  = 1'b0;
            PSEL_i    = 1'b1;
            PENABLE_i = 1'b0;
 
            @(posedge PCLK); #1;
            PENABLE_i = 1'b1;
 
            @(posedge PCLK); #2;    // rd_enb=1, PRDATA driven - sample now
            data = PRDATA_o;
 
            #1;
            PSEL_i    = 1'b0;
            PENABLE_i = 1'b0;
        end
    endtask
 
    // -----------------------------------------------------------------------
    // Task: simulate_receive
    // -----------------------------------------------------------------------
    task simulate_receive(input [7:0] miso_byte);
        begin
            @(posedge PCLK); #1;
            miso_data_i    = miso_byte;
            receive_data_i = 1'b1;
            @(posedge PCLK); #1;
            receive_data_i = 1'b0;
        end
    endtask
 
    reg [7:0] rd_data;
 
    // -----------------------------------------------------------------------
    // Main stimulus
    // -----------------------------------------------------------------------
    initial begin
        initialize;
        apply_reset;
 
        // ------------------------------------------------------------------
        // TEST 1: Reset values
        // CR1=0x04, CR2=0x00, BR=0x00
        // spi_mode=01 (SPI_WAIT) is CORRECT - CR1[6]=spe=0 at reset so
        // FSM immediately goes SPI_RUN->SPI_WAIT on first clock after reset.
        // ------------------------------------------------------------------
        $display("\n--- TEST 1: Reset values ---");
 
        apb_read(3'b000, rd_data);
        $display("SPI_CR1 after reset = 0x%02h  (expect 0x04)", rd_data);
 
        apb_read(3'b001, rd_data);
        $display("SPI_CR2 after reset = 0x%02h  (expect 0x00)", rd_data);
 
        apb_read(3'b010, rd_data);
        $display("SPI_BR  after reset = 0x%02h  (expect 0x00)", rd_data);
 
        $display("spi_mode_o = %02b  (01=SPI_WAIT is correct; spe=0 at reset)",
                  spi_mode_o);
 
        // ------------------------------------------------------------------
        // TEST 2: Write SPI_CR1 = 0x50  (SPE=bit6=1, MSTR=bit4=1)
        //         spe=1 -> FSM SPI_WAIT->SPI_RUN after 2 cycles
        // ------------------------------------------------------------------
        $display("\n--- TEST 2: Configure SPI_CR1 (SPE=1, MSTR=1) ---");
 
        apb_write(3'b000, 8'b0101_0000);
        repeat(2) @(posedge PCLK); #1;  // wait for SPI FSM to react
 
        apb_read(3'b000, rd_data);
        $display("SPI_CR1 readback = 0x%02h  (expect 0x50)", rd_data);
        $display("mstr_o=%b cpol_o=%b cpha_o=%b lsbfe_o=%b",
                  mstr_o, cpol_o, cpha_o, lsbfe_o);
        $display("spi_mode_o = %02b  (expect 10 = SPI_RUN)", spi_mode_o);
 
        // ------------------------------------------------------------------
        // TEST 3: Write SPI_BR = 0x23  (sppr[2:0]=001, spr[2:0]=011)
        //         masked with 0x77: 0x23 & 0x77 = 0x23
        //         FIX: display sppr/spr INSIDE apb_read (after rd_enb fires)
        //------------------------------------------------------------------
        $display("\n--- TEST 3: Configure SPI_BR ---");
 
        apb_write(3'b010, 8'b0010_0011);
        apb_read (3'b010, rd_data);
        // FIX: sppr_o/spr_o are driven from spi_br which is already latched.
        //      They are valid right after the read completes.
        $display("SPI_BR readback = 0x%02h  (expect 0x23)", rd_data);
        $display("sppr_o=%03b  spr_o=%03b  (expect 001, 011)", sppr_o, spr_o);
 
        // ------------------------------------------------------------------
        // TEST 4: Write SPI_DR = 0xA5
        //         mode_ok=1 (SPI_RUN), miso=0x00 != 0xA5 -> send_data=1
        //
        //         FIX: send_data_o fires at the posedge when wr_enb=1
        //         (cycle 3 of apb_write = posedge where data latches).
        //         After apb_write returns, that posedge has already passed.
        //         send_data_o is a 1-cycle pulse - it's 1 DURING the write
        //         cycle and 0 the next.
        //         Sample: check during the ENABLE hold cycle, not after.
        // ------------------------------------------------------------------
        $display("\n--- TEST 4: Write SPI_DR = 0xA5 ---");
 
        // Manual 4-cycle APB write so we can sample send_data mid-sequence
        @(posedge PCLK); #1;
        PADDR_i   = 3'b101;
        PWDATA_i  = 8'hA5;
        PWRITE_i  = 1'b1;
        PSEL_i    = 1'b1;
        PENABLE_i = 1'b0;
 
        @(posedge PCLK); #1;    // FSM -> SETUP
        PENABLE_i = 1'b1;
 
        @(posedge PCLK); #1;    // FSM -> ENABLE; wr_enb registered=1
        // wr_enb fires at next posedge - send_data_o will be set there
 
        @(posedge PCLK); #2;    // wr_enb=1 fires here -> send_data_o=1 NOW
        $display("send_data_o=%b  (expect 1)", send_data_o);
        $display("mosi_data_o=0x%02h  (expect 0xA5)", mosi_data_o);
 
        #1;
        PSEL_i    = 1'b0;
        PENABLE_i = 1'b0;
        PWRITE_i  = 1'b0;
 
        @(posedge PCLK); #2;    // next idle cycle - send_data should clear
        $display("send_data_o after idle=%b  (expect 0)", send_data_o);
 
        // ------------------------------------------------------------------
        // TEST 5: MISO receive -> SPI_DR = 0x3C
        // ------------------------------------------------------------------
        $display("\n--- TEST 5: Simulate MISO receive 0x3C ---");
 
        simulate_receive(8'h3C);
        repeat(2) @(posedge PCLK);
        apb_read(3'b101, rd_data);
        $display("SPI_DR after receive = 0x%02h  (expect 0x3C)", rd_data);
 
        // ------------------------------------------------------------------
        // TEST 6: Read SPI_SR
        //         spi_dr=0x3C!=0 -> spif=1, sptef=0
        //         SR = {1,0,0,0,0000} = 0x80
        // ------------------------------------------------------------------
        $display("\n--- TEST 6: Read SPI_SR ---");
 
        apb_read(3'b011, rd_data);
        $display("SPI_SR = 0x%02h  (expect 0x80: spif=1)", rd_data);
 
        // ------------------------------------------------------------------
        // TEST 7: SPI_CR2 mask - write 0xFF -> expect 0x1B
        //         NOTE: after this, spiswai_o=CR2[1]=1
        //         FIX for TEST 9: clear CR2 back to 0x00 before testing
        //         SPE=0 transition, so FSM stops at SPI_WAIT not SPI_STOP.
        // ------------------------------------------------------------------
        $display("\n--- TEST 7: SPI_CR2 mask test ---");
 
        apb_write(3'b001, 8'hFF);
        apb_read (3'b001, rd_data);
        $display("SPI_CR2 after write 0xFF = 0x%02h  (expect 0x1B)", rd_data);
 
        // ------------------------------------------------------------------
        // TEST 8: PSLVERR - state=ENABLE, tip_i=0 -> PSLVERR=1
        // ------------------------------------------------------------------
        $display("\n--- TEST 8: PSLVERR when tip_i=0 ---");
 
        tip_i = 1'b0;
 
        @(posedge PCLK); #1;
        PADDR_i   = 3'b000;
        PWRITE_i  = 1'b0;
        PSEL_i    = 1'b1;
        PENABLE_i = 1'b0;
 
        @(posedge PCLK); #1;    // FSM -> SETUP
        PENABLE_i = 1'b1;
 
        @(posedge PCLK); #2;    // FSM -> ENABLE; PREADY=1, PSLVERR=1
        $display("PREADY_o=%b PSLVERR_o=%b  (expect 1, 1)",
                  PREADY_o, PSLVERR_o);
        #1;
        PSEL_i    = 1'b0;
        PENABLE_i = 1'b0;
        tip_i     = 1'b1;
 
        // ------------------------------------------------------------------
        // TEST 9: SPE=0 -> spi_mode goes to SPI_WAIT
        //
        //         FIX: CR2 has spiswai=1 from TEST 7 (0x1B bit[1]=1).
        //         With spiswai=1, when SPE=0 the FSM goes:
        //           SPI_RUN->SPI_WAIT (1 cycle) then SPI_WAIT->SPI_STOP (next)
        //         So FIRST clear CR2 to 0x00 (spiswai=0), THEN write SPE=0.
        //         Now FSM stays at SPI_WAIT permanently.
        // ------------------------------------------------------------------
        $display("\n--- TEST 9: SPE=0 -> spi_mode should go to SPI_WAIT ---");
 
        // Clear CR2 to remove spiswai
        apb_write(3'b001, 8'h00);
 
        // Now disable SPE
        apb_write(3'b000, 8'b0001_0000);   // SPE=0, MSTR=1
 
        repeat(3) @(posedge PCLK); #2;
        $display("spi_mode_o = %02b  (expect 01 = SPI_WAIT)", spi_mode_o);
 
        // ------------------------------------------------------------------
        // TEST 10: SPE=1 -> spi_mode returns to SPI_RUN
        // ------------------------------------------------------------------
        $display("\n--- TEST 10: SPE=1 -> spi_mode returns to SPI_RUN ---");
 
        apb_write(3'b000, 8'b0101_0000);   // SPE=1, MSTR=1
        repeat(2) @(posedge PCLK); #2;
        $display("spi_mode_o = %02b  (expect 10 = SPI_RUN)", spi_mode_o);
 
        repeat(5) @(posedge PCLK);
        $display("\n--- Simulation complete ---");
        $finish;
    end
 
    // Continuous monitor
    initial begin
        $monitor("T=%0t | STATE=%02b SPI_MODE=%02b PREADY=%b PSLVERR=%b SEND=%b MOSI=%02h PRDATA=%02h IRQ=%b",
                  $time, dut.state, spi_mode_o, PREADY_o, PSLVERR_o,
                  send_data_o, mosi_data_o, PRDATA_o, spi_interrupt_request_o);
    end
 
endmodule
