`timescale 1ns / 1ps

module lin_baud_gen_tb();

    // TB Signals
    logic clk;
    logic rstn;
    logic [15:0] bdiv;
    logic rx_tick;
    logic tx_tick;

    // DUT
    lin_baud_gen #(
        .SYS_CLK_FREQ(50_000_000)
    ) dut (
        .clk(clk),
        .rstn(rstn),
        .bdiv(bdiv),
        .rx_tick(rx_tick),
        .tx_tick(tx_tick)
    );

    //---------------------------------------------------------
    // Clock Generation (50 MHz)
    //---------------------------------------------------------
    initial begin
        clk = 0;
        forever #10 clk = ~clk; // 20ns period
    end

    //---------------------------------------------------------
    // Time Measurement Variables
    //---------------------------------------------------------
    realtime last_tx_time = 0;
    realtime current_tx_time = 0;
    realtime time_diff = 0;

    //---------------------------------------------------------
    // Monitor TX Tick Timing
    //---------------------------------------------------------
    always @(posedge tx_tick) begin
        current_tx_time = $realtime;

        if (last_tx_time > 0) begin
            time_diff = current_tx_time - last_tx_time;
            $display("[%0t ns] TX Tick → Bit Time = %0t ns", $time, time_diff);
        end

        last_tx_time = current_tx_time;
    end

    //---------------------------------------------------------
    // CSV Logging
    //---------------------------------------------------------
    integer file_handle;

    initial begin
        file_handle = $fopen("baud_simulation_data.csv", "w");
        $fdisplay(file_handle, "Time(ns), bdiv, rx_tick, tx_tick");
    end

    always @(posedge clk) begin
        $fdisplay(file_handle, "%0t, %0d, %b, %b", $time, bdiv, rx_tick, tx_tick);
    end

    //---------------------------------------------------------
    // Main Test Sequence
    //---------------------------------------------------------
    initial begin
        $display("===== LIN Baud Generator Test =====");

        // Reset
        rstn = 0;
        bdiv = 16'd156; // safe initial value
        #100;
        rstn = 1;

        //-----------------------------------------
        // 1 kHz Test
        //-----------------------------------------
        $display("\n--- Testing 1 kHz ---");
        last_tx_time = 0;
        bdiv = 16'd3125;
        repeat(3) @(posedge tx_tick);

        //-----------------------------------------
        // 5 kHz Test
        //-----------------------------------------
        $display("\n--- Testing 5 kHz ---");
        last_tx_time = 0;
        bdiv = 16'd625;
        repeat(3) @(posedge tx_tick);

        //-----------------------------------------
        // 15 kHz Test
        //-----------------------------------------
        $display("\n--- Testing 15 kHz ---");
        last_tx_time = 0;
        bdiv = 16'd208; // approx
        repeat(3) @(posedge tx_tick);

        //-----------------------------------------
        // 20 kHz Test
        //-----------------------------------------
        $display("\n--- Testing 20 kHz ---");
        last_tx_time = 0;
        bdiv = 16'd156;
        repeat(3) @(posedge tx_tick);

        //-----------------------------------------
        // Finish
        //-----------------------------------------
        #1000;
        $fclose(file_handle);
        $display("\n===== Simulation Finished =====");
        $finish;
    end

endmodule