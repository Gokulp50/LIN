`timescale 1ns / 1ps

module lin_rx_tb();

    //==================================================================
    // 1. Signals & DUT Instantiation
    //==================================================================
    logic       clk, rstn, rx_tick, lin_rx;
    logic       break_flag, rx_done, framing_error;
    logic [7:0] rx_byte;

    lin_rx dut (
        .clk(clk),
        .rstn(rstn),
        .rx_tick(rx_tick),
        .lin_rx(lin_rx),
        .break_flag(break_flag),
        .rx_byte(rx_byte),
        .rx_done(rx_done),
        .framing_error(framing_error)
    );

    //==================================================================
    // 2. Clock Generation (100 MHz → 10ns period)
    //==================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    //==================================================================
    // 3. Continuous 16x rx_tick Generator (ALWAYS running!)
    //==================================================================
    logic [3:0] tick_div = 0;
    always @(posedge clk) begin
        tick_div <= tick_div + 1;
        rx_tick <= (tick_div == 4'd0);
    end

    //==================================================================
    // VIVADO-SAFE HELPER TASKS
    //==================================================================
    
    task wait_bits(input real bits);
        int ticks_to_wait;
        ticks_to_wait = int'(bits * 16.0);
        
        for (int i = 0; i < ticks_to_wait; i++) begin
            @(posedge clk);
            while (rx_tick == 1'b0) begin
                @(posedge clk);
            end
        end
    endtask
    
    task set_lin_rx(input logic value, input real bits);
        lin_rx <= value; 
        if (bits > 0.0) begin
            wait_bits(bits);
        end
    endtask

    task send_byte(input logic [7:0] data);
        $display("[%0t ns]      -> Sending Byte: 0x%h", $time, data);
        set_lin_rx(1'b0, 1.0);  // Start bit
        for (int i = 0; i < 8; i++) begin
            set_lin_rx(data[i], 1.0);
        end
        set_lin_rx(1'b1, 1.0);  // Stop bit
    endtask

    task send_break(input real low_bits, input real high_bits);
        $display("\n[%0t ns] ---> Sending Break: %0.1f LOW, %0.1f HIGH bits", $time, low_bits, high_bits);
        set_lin_rx(1'b0, low_bits);
        set_lin_rx(1'b1, high_bits);
    endtask

    task send_lin_frame(input logic [7:0] sync_byte, input logic [7:0] payload[]);
        send_break(13.0, 1.0);
        send_byte(sync_byte);
        for (int i = 0; i < payload.size(); i++) begin
            send_byte(payload[i]);
        end
    endtask

    task send_only_break(input real low_bits, input real high_bits);
        send_break(low_bits, high_bits);
        wait_bits(2);
    endtask

    //==================================================================
    // STATISTICS COUNTERS
    //==================================================================
    int break_cnt = 0;
    int byte_cnt = 0;
    int err_cnt = 0;
    
    always @(posedge clk) begin
        if (break_flag) begin
            $display("  >>> [%0t ns] *** BREAK DETECTED! ***", $time);
            break_cnt++;
        end
        if (rx_done) begin
            $display("  >>> [%0t ns] --> BYTE RECEIVED: 0x%h", $time, rx_byte);
            byte_cnt++;
        end
        if (framing_error) begin
            $display("  >>> [%0t ns] !!! FRAMING ERROR! !!!", $time);
            err_cnt++;
        end
    end

    //==================================================================
    // MAIN TEST SEQUENCE
    //==================================================================
    initial begin
        $display("================================================================");
        $display("   LIN Receiver: Automotive Compliance Testbench");
        $display("================================================================");
        
        rstn = 0; lin_rx = 1; 
        wait_bits(10);
        rstn = 1; 
        wait_bits(20);
        
        $display("\n========== TEST 1: Valid Break + Valid Sync ==========");
        send_break(13.0, 1.0);
        send_byte(8'h55);
        wait_bits(10);
        
        $display("\n========== TEST 2: Full Frame Reception ==========");
        send_break(14.0, 1.5);
        send_byte(8'h55);
        send_byte(8'h83);
        send_byte(8'h01);
        send_byte(8'h02);
        send_byte(8'h03);
        wait_bits(20);
        
        $display("\n========== TEST 3: Long Break (20 bits) ==========");
        send_break(20.0, 1.0);
        send_byte(8'h55);
        send_byte(8'hAA);
        wait_bits(10);
        
        $display("\n========== TEST 4: Short Break - 10 bits (Should Fail) ==========");
        send_break(10.0, 1.0);
        send_byte(8'h55);
        wait_bits(10);
        
        $display("\n========== TEST 5: Very Short Break - 8 bits (Should Fail) ==========");
        send_break(8.0, 1.0);
        send_byte(8'h55);
        wait_bits(10);
        
        $display("\n========== TEST 6: Short Delimiter (0.5 bits - Should Error) ==========");
        send_break(13.0, 0.5);
        send_byte(8'h55);
        wait_bits(10);
        
        $display("\n========== TEST 7: Missing Delimiter (0 bits - Should Error) ==========");
        set_lin_rx(1'b0, 13.0);   
        set_lin_rx(1'b1, 0.0);    
        send_byte(8'h55);
        wait_bits(10);
        
        $display("\n========== TEST 8: Missing Stop Bit (Should Error) ==========");
        send_break(13.0, 1.0);
        set_lin_rx(1'b0, 1.0);   
        for (int i = 0; i < 8; i++) begin
            set_lin_rx(1'b0, 1.0);   
        end
        set_lin_rx(1'b0, 1.0); 
        set_lin_rx(1'b1, 2.0); 
        wait_bits(10);
        
        $display("\n========== TEST 9: Back-to-Back Frames ==========");
        send_lin_frame(8'h55, '{8'hAA, 8'hBB});
        wait_bits(5);
        send_lin_frame(8'h55, '{8'hCC, 8'hDD});
        wait_bits(20);
        
        $display("\n========== TEST 10: Different Data Patterns ==========");
        send_lin_frame(8'h55, '{8'h00});   
        wait_bits(5);
        send_lin_frame(8'h55, '{8'hFF});   
        wait_bits(5);
        send_lin_frame(8'h55, '{8'hA5});   
        wait_bits(5);
        send_lin_frame(8'h55, '{8'h5A});   
        wait_bits(10);
        
        $display("\n========== TEST 11: Bus Stuck Low (Timeout Recovery) ==========");
        $display("[%0t ns] Simulating short to ground...", $time);
        set_lin_rx(1'b0, 35.0);  
        $display("[%0t ns] Bus recovered", $time);
        set_lin_rx(1'b1, 5.0);
        send_lin_frame(8'h55, '{8'h42});  
        wait_bits(10);
        
        $display("\n========== TEST 12: Maximum Frame (8 Data Bytes) ==========");
        send_lin_frame(8'h55, '{8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08});
        wait_bits(20);
        
        $display("\n========== TEST 13: Bus Noise Rejection ==========");
        set_lin_rx(1'b1, 10.0);
        set_lin_rx(1'b0, 0.3);
        set_lin_rx(1'b1, 10.0);
        set_lin_rx(1'b0, 0.2); 
        set_lin_rx(1'b1, 10.0);
        send_lin_frame(8'h55, '{8'hAA}); 
        wait_bits(10);
        
        $display("\n========== TEST 14: Multiple Break Detection ==========");
        send_only_break(13.0, 1.0);
        wait_bits(2);
        send_only_break(14.0, 1.5);
        wait_bits(2);
        send_only_break(15.0, 2.0);
        wait_bits(10);

        // Print final stats directly inside the sequence
        $display("\n================================================================");
        $display("   FINAL STATISTICS");
        $display("================================================================");
        $display(" Total Breaks Detected:  %0d", break_cnt);
        $display(" Total Bytes Received:   %0d", byte_cnt);
        $display(" Total Errors Caught:    %0d", err_cnt);
        $display("================================================================");
        
        if (break_cnt >= 8) $display("[PASS] Break detection working!");
        else $display("[FAIL] Break detection issues detected!");
        
        if (byte_cnt >= 30) $display("[PASS] Byte reception working!");
        else $display("[FAIL] Byte reception issues detected!");
        
        $finish;
    end

endmodule