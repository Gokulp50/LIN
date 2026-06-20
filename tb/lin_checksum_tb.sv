`timescale 1ns / 1ps

module lin_checksum_tb();

    logic       clk, rstn;
    logic       start_frame;
    logic       enhanced;
    logic [7:0] pid;
    logic       data_valid;
    logic [7:0] data_byte;
    logic [7:0] checksum;

    // Test counters
    int test_passed = 0;
    int test_failed = 0;
    int test_count = 0;

    // Instantiate explicitly (Protects against Vivado .* segfaults)
    lin_checksum dut (
        .clk(clk),
        .rstn(rstn),
        .start_frame(start_frame),
        .enhanced(enhanced),
        .pid(pid),
        .data_valid(data_valid),
        .data_byte(data_byte),
        .checksum(checksum)
    );

    // 100 MHz Clock (10ns period)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    //========================================================================
    // REFERENCE MODEL: Pure software implementation for verification
    //========================================================================
    // FIX 1: Use Queues ([$]) instead of Dynamic Arrays. 
    function automatic [7:0] compute_lin_checksum(input logic enh, input [7:0] pid_val, input logic [7:0] bytes [$]);
        logic [8:0] sum;
        sum = 9'b0;
        
        if (enh) begin
            sum = {1'b0, pid_val};
        end
        
        for (int i = 0; i < bytes.size(); i++) begin
            sum = sum + bytes[i];
            if (sum[8]) begin
                sum = (sum & 9'b011111111) + 1;
            end
        end
        
        return ~sum[7:0];
    endfunction

    //========================================================================
    // HELPER TASKS
    //========================================================================
    task automatic wait_clocks(input int n);
        repeat(n) @(posedge clk);
    endtask

    task automatic push_byte(input logic [7:0] byte_val);
        @(posedge clk);
        data_byte  <= byte_val;
        data_valid <= 1'b1;     
        @(posedge clk);
        data_valid <= 1'b0;     
        wait_clocks(1); 
    endtask
    
    task automatic start_new_frame(input logic enh, input [7:0] pid_val);
        @(posedge clk);
        enhanced    <= enh;     
        pid         <= pid_val;
        start_frame <= 1'b1;    
        @(posedge clk);
        start_frame <= 1'b0;    
        wait_clocks(2);
    endtask
    
    // Base runner for hardcoded Expected values
    task automatic run_test(input string test_name, input logic enh, input [7:0] pid_val, 
                  input logic [7:0] data_bytes [$], input [7:0] expected);
        logic [7:0] actual;
        
        $display("\n  [TEST] %s", test_name);
        $display("    Mode: %s, PID: 0x%h", enh ? "Enhanced" : "Classic", pid_val);
        $write("    Data Bytes: ");
        for (int i = 0; i < data_bytes.size(); i++) begin
            $write("0x%h ", data_bytes[i]);
        end
        $write("\n");
        
        // Run DUT
        start_new_frame(enh, pid_val);
        for (int i = 0; i < data_bytes.size(); i++) begin
            push_byte(data_bytes[i]);
        end
        
        // Wait for checksum to stabilize
        wait_clocks(5);
        actual = checksum;
        
        // Verify
        if (actual == expected) begin
            $display("    [PASS] Checksum: 0x%h (Expected: 0x%h)", actual, expected);
            test_passed++;
        end else begin
            $display("    [FAIL] Got: 0x%h, Expected: 0x%h", actual, expected);
            test_failed++;
        end
        test_count++;
        
        wait_clocks(10);
    endtask

    // FIX 2: Wrapper Task to auto-compute expected values internally
    // This stops Vivado from crashing on nested function calls!
    task automatic run_test_auto(input string test_name, input logic enh, input [7:0] pid_val, 
                  input logic [7:0] data_bytes [$]);
        logic [7:0] expected_calc;
        expected_calc = compute_lin_checksum(enh, pid_val, data_bytes);
        run_test(test_name, enh, pid_val, data_bytes, expected_calc);
    endtask

    //========================================================================
    // MAIN TEST SEQUENCE
    //========================================================================
    initial begin
        $display("================================================================");
        $display("   LIN CHECKSUM ENGINE: COMPREHENSIVE VERIFICATION");
        $display("================================================================");
        
        rstn = 0; start_frame = 0; data_valid = 0;
        data_byte = 0; enhanced = 0; pid = 0;
        wait_clocks(10);
        rstn = 1; 
        wait_clocks(10);

        // SECTION 1: CLASSIC CHECKSUM TESTS
        run_test("Spec Page 52 Example", 0, 8'h00, '{8'h4A, 8'h55, 8'h93, 8'hE5}, 8'hE6);
        run_test("Single Byte 0x00", 0, 8'h00, '{8'h00}, 8'hFF);
        run_test("Single Byte 0x55", 0, 8'h00, '{8'h55}, 8'hAA);
        run_test("Single Byte 0xFF", 0, 8'h00, '{8'hFF}, 8'h00);
        run_test("Two Bytes 0x01,0x02", 0, 8'h00, '{8'h01, 8'h02}, 8'hFC);
        run_test("Two Bytes with Carry (0xFF,0x01)", 0, 8'h00, '{8'hFF, 8'h01}, 8'hFE);
        run_test("8 Bytes of 0x00", 0, 8'h00, '{8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00}, 8'hFF);
        run_test_auto("8 Bytes of 0xFF", 0, 8'h00, '{8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF});

        // SECTION 2: ENHANCED CHECKSUM TESTS
        run_test("Enhanced Spec Example (PID=0x83)", 1, 8'h83, '{8'h4A, 8'h55, 8'h93, 8'hE5}, 8'h63);
        run_test("Enhanced Single Byte", 1, 8'h01, '{8'h00}, ~8'h01);
        run_test_auto("Enhanced with Carry", 1, 8'hFF, '{8'h01});
        run_test_auto("Enhanced Multiple Carries", 1, 8'h80, '{8'h80, 8'h80, 8'h80, 8'h80});
        run_test_auto("Master Request Frame (PID=0x3C)", 1, 8'h3C, '{8'h01, 8'h02, 8'h03});
        run_test_auto("Slave Response Frame (PID=0x3D)", 1, 8'h3D, '{8'h04, 8'h05, 8'h06});

        // SECTION 3: BOUNDARY & EDGE CASES
        run_test("PID=0xFF, Data=0x00", 1, 8'hFF, '{8'h00}, ~8'hFF);
        run_test_auto("Maximum Sum Test", 0, 8'h00, '{8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFE});
        run_test_auto("Alternating Pattern 0x55,0xAA", 0, 8'h00, '{8'h55, 8'hAA, 8'h55, 8'hAA, 8'h55, 8'hAA});
        
        // SECTION 4: REAL-WORLD LIN FRAME SIMULATIONS
        run_test_auto("Sensor Reading: 0x0F, 0x42", 1, 8'h21, '{8'h0F, 8'h42});
        run_test_auto("Actuator Control: 0x80", 1, 8'h15, '{8'h80});
        run_test_auto("Diagnostic Request (Classic)", 0, 8'h00, '{8'hAA, 8'hBB, 8'hCC, 8'hDD});
        run_test_auto("Diagnostic Response (Classic)", 0, 8'h00, '{8'h11, 8'h22, 8'h33, 8'h44, 8'h55});
        
        $display("\n================================================================");
        $display("   TEST RESULTS SUMMARY");
        $display("================================================================");
        $display(" Total Tests:  %0d", test_count);
        $display(" Passed:       %0d", test_passed);
        $display(" Failed:       %0d", test_failed);
        $display(" Success Rate: %0.1f%%", (test_passed * 100.0 / test_count));
        
        if (test_failed == 0) begin
            $display("\n*** ALL TESTS PASSED! LIN CHECKSUM ENGINE IS READY! ***");
        end else begin
            $display("\n!!! Some tests failed. Please review the implementation.");
        end
        $finish;
    end

    //========================================================================
    // CONTINUOUS MONITOR 
    //========================================================================
    logic [7:0] last_checksum = 8'h00; 
    
    always @(posedge clk) begin
        if (checksum !== last_checksum) begin 
            last_checksum <= checksum;
            $display("  [MONITOR] checksum = 0x%h at %0t ns", checksum, $time);
        end
    end

endmodule