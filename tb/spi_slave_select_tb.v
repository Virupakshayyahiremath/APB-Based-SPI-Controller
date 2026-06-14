`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 20.01.2026 23:29:11
// Design Name: 
// Module Name: spi_slave_select_tb
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


module spi_slave_select_tb ();
    reg         PCLK;
    reg         PRESET_n;
    reg         mstr_i;
    reg         spiswai_i;
    reg  [1:0]  spi_mode_i;
    reg         send_data_i;
    reg  [15:0] BaudRateDivisor_i;
 
    wire        receive_data_o;
    wire        ss_o;
    wire        tip_o;
 
    spi_slave_select DUT (
        .PCLK             (PCLK),
        .PRESET_n         (PRESET_n),
        .mstr_i           (mstr_i),
        .spiswai_i        (spiswai_i),
        .spi_mode_i       (spi_mode_i),       
        .send_data_i      (send_data_i),
        .BaudRateDivisor_i(BaudRateDivisor_i),
        .receive_data_o   (receive_data_o),
        .ss_o             (ss_o),
        .tip_o            (tip_o)
    );
 
    initial PCLK = 1'b0;
    always  #5 PCLK = ~PCLK;
 
    task initialize;
        begin
            PRESET_n          = 1'b1;
            mstr_i            = 1'b1;
            spiswai_i         = 1'b0;
            spi_mode_i        = 2'b00;    // STOP - no run/wait
            send_data_i       = 1'b0;
            BaudRateDivisor_i = 16'd4;    // target = 4×16 = 64 clocks per frame
        end
    endtask
 
    task apply_reset;
        begin
            PRESET_n = 1'b0;
            repeat (5) @(posedge PCLK);
            @(negedge PCLK);              
            PRESET_n = 1'b1;
            $display("[%0t] RESET released", $time);
        end
    endtask
 
    // start_spi: configure master, SPI_RUN mode, wait enabled
    task start_spi;
        begin
            mstr_i     = 1'b1;
            spiswai_i  = 1'b0;
            spi_mode_i = 2'b10;           // RUN
            $display("[%0t] SPI START (spi_mode=RUN)", $time);
        end
    endtask
 
    // stop_spi: put SPI back to STOP mode
    task stop_spi;
        begin
            spi_mode_i = 2'b00;           // STOP
            $display("[%0t] SPI STOP", $time);
        end
    endtask
 
    // send_frame: pulse send_data_i for exactly one PCLK cycle.
    //   Drive send_data_i HIGH before the rising edge so the DUT
    //   samples it on the next posedge PCLK. (Bug fix vs original TB.)
    task send_frame;
        begin
            @(negedge PCLK);              // drive on falling edge ...
            send_data_i = 1'b1;
            @(negedge PCLK);              // ... hold for one full cycle ...
            send_data_i = 1'b0;
            $display("[%0t] send_data asserted (1-cycle pulse)", $time);
        end
    endtask
 
    // wait_frame_done: block until ss_o deasserts (frame over).
    //   Timeout after 10000 ns to prevent infinite hang.
    task wait_frame_done;
        integer timeout;
        begin
            timeout = 0;
            while (ss_o === 1'b0 && timeout < 10000) begin
                @(posedge PCLK);
                timeout = timeout + 20;
            end
            if (ss_o !== 1'b1)
                $display("[%0t] WARNING: wait_frame_done timed out!", $time);
            else
                $display("[%0t] Frame done: ss_o deasserted", $time);
        end
    endtask
 
    // test_no_enable: verify ss_o stays 1 when enable conditions not met
    task test_no_enable;
        begin
            $display("[%0t] TEST: no-enable (slave mode)", $time);
            mstr_i = 1'b0;                // slave mode → enable=0
            send_frame;
            repeat (10) @(posedge PCLK);
            if (ss_o !== 1'b1)
                $display("[%0t] FAIL: ss_o should be 1 in slave mode", $time);
            else
                $display("[%0t] PASS: ss_o=1 when mstr_i=0", $time);
            mstr_i = 1'b1;                // restore master mode
        end
    endtask
 
    // test_reset_mid_frame: assert reset while frame is running
    task test_reset_mid_frame;
        begin
            $display("[%0t] TEST: reset mid-frame", $time);
            send_frame;
            repeat (10) @(posedge PCLK);  // wait a few cycles into the frame
            PRESET_n = 1'b0;
            repeat (3) @(posedge PCLK);
            @(negedge PCLK);
            PRESET_n = 1'b1;
            repeat (5) @(posedge PCLK);
            if (ss_o !== 1'b1)
                $display("[%0t] FAIL: ss_o should be 1 after mid-frame reset",
                         $time);
            else
                $display("[%0t] PASS: ss_o=1 after mid-frame reset", $time);
        end
    endtask
 
    initial begin
        $dumpfile("spi_slave_select_tb.vcd");
        $dumpvars(0, spi_slave_select_tb);
 
        initialize;
        apply_reset;
        start_spi;
 
        // ---- Test 1: no-enable check ----
        test_no_enable;
 
        // ---- Test 2: normal frame 1 ----
        $display("[%0t] ===== Frame 1 =====", $time);
        send_frame;
        wait_frame_done;
        repeat (5) @(posedge PCLK);
 
        // ---- Test 3: normal frame 2 ----
        $display("[%0t] ===== Frame 2 =====", $time);
        send_frame;
        wait_frame_done;
        repeat (5) @(posedge PCLK);
 
        // ---- Test 4: reset mid-frame ----
        $display("[%0t] ===== Mid-frame reset =====", $time);
        test_reset_mid_frame;
        repeat (5) @(posedge PCLK);
 
        // ---- Test 5: spi_wait mode ----
        $display("[%0t] ===== SPI WAIT mode =====", $time);
        spi_mode_i = 2'b01;              // spi_wait
        send_frame;
        wait_frame_done;
        repeat (5) @(posedge PCLK);
 
        // ---- Test 6: stop mode ----
        stop_spi;
        repeat (10) @(posedge PCLK);
        if (ss_o !== 1'b1)
            $display("[%0t] FAIL: ss_o should be 1 after stop", $time);
        else
            $display("[%0t] PASS: ss_o=1 after stop", $time);
 
        $display("[%0t] Simulation complete", $time);
        $finish;
    end
 
    initial begin
        $monitor("[%0t] SS=%b TIP=%b RCV=%b count=%0d",
                 $time, ss_o, tip_o, receive_data_o,
                 DUT.count_s);
    end
 
endmodule