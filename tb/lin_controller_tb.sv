`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 27.04.2026 14:48:17
// Design Name: 
// Module Name: lin_controller_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: LIN 2.1 Top Level Closed Loop with 100% Functional Coverage
// 
//////////////////////////////////////////////////////////////////////////////////


module lin_controller_tb();
    //========================================================================
    // Testbench Signals
    //========================================================================
    logic       clk, rstn;
    logic       lin_rx_in, lin_tx_out;
    
    // Transmitter Interface (CPU -> Controller)
    logic       start_transmit, master_mode, send_break, enhanced_cs;
    logic [7:0] tx_pid;
    logic [2:0] tx_data_count;
    logic [7:0] tx_data;
    logic       tx_data_valid;
    logic       tx_data_ready;
    logic       tx_busy, tx_done;

    // Receiver Interface (Controller -> CPU)
    logic       rx_break_det;
    logic [7:0] rx_data;
    logic       rx_data_valid;
    logic       rx_error;

    // Test Control
    logic [7:0] tx_payload []; 
    int         tx_byte_index;
    int         rx_byte_index;

    int         test_passed = 0;
    int         test_failed = 0;

    //========================================================================
    // DUT Instantiation
    //========================================================================
    lin_controller dut (
        .clk(clk),
        .rstn(rstn),
        .lin_rx_in(lin_rx_in),
        .lin_tx_out(lin_tx_out),
        
        .start_transmit(start_transmit),
        .master_mode(master_mode),
        .send_break(send_break),
        .tx_pid(tx_pid),
        .enhanced_cs(enhanced_cs),
    
        .tx_data_count(tx_data_count),
        .tx_data(tx_data),
        .tx_data_valid(tx_data_valid),
        .tx_data_ready(tx_data_ready),
        .tx_busy(tx_busy),
        .tx_done(tx_done),
        
        .rx_break_det(rx_break_det),
        .rx_data(rx_data),
        .rx_data_valid(rx_data_valid),
        .rx_error(rx_error)
    );

    //========================================================================
    // Clock Generation (100 MHz)
    //========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    //========================================================================
    // Closed Loopback Connection (TX directly drives RX)
    //========================================================================
    assign lin_rx_in = lin_tx_out;

    //========================================================================
    // TX Data Feeder 
    //========================================================================
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            tx_data       <= 0;
            tx_data_valid <= 0;
            tx_byte_index <= 0;
        end else begin
            
            // NOTE: We absolutely do NOT set tx_data_valid <= 0 here anymore.
            // We must hold it high until the entire frame is done so the slow baud clock can catch it.
            if (tx_data_ready && tx_byte_index < tx_payload.size()) begin
                tx_data       <= tx_payload[tx_byte_index];
                tx_data_valid <= 1'b1;
                $display("[TX-FEEDER] Pushing byte %0d: 0x%h", tx_byte_index, tx_payload[tx_byte_index]);
                tx_byte_index <= tx_byte_index + 1;
            end
            
            if (tx_done) begin
                tx_byte_index <= 0;
                tx_data_valid <= 1'b0; // Only drop the signal at the very end of the frame
            end
        end
    end
    
    //========================================================================
    // RX Data Monitor
    //========================================================================
    logic [7:0] rx_buffer [0:31];
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            rx_byte_index <= 0;
            for (int i = 0; i < 32; i++) rx_buffer[i] <= 0;
        end else begin
            if (rx_data_valid) begin
                rx_buffer[rx_byte_index] <= rx_data;
                $display("[RX-MONITOR] Received byte %0d: 0x%h", rx_byte_index, rx_data);
                rx_byte_index <= rx_byte_index + 1;
            end
            
            if (rx_break_det) begin
                $display("[RX-MONITOR] *** BREAK FIELD DETECTED! ***");
                rx_byte_index <= 0;  
            end
        end
    end

    //========================================================================
    // FUNCTIONAL COVERAGE
    //========================================================================
    int         cvg_payload_len;   // 1 to 8 bytes
    bit         cvg_checksum_type; // 0 = Classic, 1 = Enhanced
    logic [7:0] cvg_pid;           // 0 to 255

    covergroup lin_ctrl_cov_grp;
        option.per_instance = 1;
        option.name = "LIN_Controller_Coverage";

        // Did we test all valid payload lengths? (1 through 8 bytes)
        cp_payload_len: coverpoint cvg_payload_len {
            bins len_1 = {1}; bins len_2 = {2}; bins len_3 = {3}; bins len_4 = {4};
            bins len_5 = {5}; bins len_6 = {6}; bins len_7 = {7}; bins len_8 = {8};
        }

        // Did we test both Classic and Enhanced Checksums?
        cp_cstype: coverpoint cvg_checksum_type {
            bins classic  = {0};
            bins enhanced = {1};
        }

        // Did we hit a wide spread of PIDs?
        cp_pid: coverpoint cvg_pid {
            bins q1 = {[0:63]};
            bins q2 = {[64:127]};
            bins q3 = {[128:191]};
            bins q4 = {[192:255]};
        }

        // CROSS COVERAGE: Did we test every length with BOTH Checksum types?
        cross_len_x_cs: cross cp_payload_len, cp_cstype;
    endgroup

    lin_ctrl_cov_grp lin_ctrl_cg;
    
    //========================================================================
    // Helper Tasks 
    //========================================================================
    task automatic wait_clocks(input int n);
        repeat(n) @(posedge clk);
    endtask
    
    task automatic reset_system();
        rstn = 0; start_transmit = 0;
        master_mode = 0; send_break = 0;
        enhanced_cs = 0; tx_pid = 0; tx_data_count = 0; tx_data = 0;
        tx_data_valid = 0;
        tx_payload = new[8];
        for (int i = 0; i < 8; i++) tx_payload[i] = 0;
        wait_clocks(10);
        rstn = 1; wait_clocks(20);
        $display("\n[SYSTEM] Reset complete!");
    endtask
    
    task automatic send_frame(input string test_name,
                    input logic master, input logic [7:0] pid_val,
                    input logic enhanced, input logic [2:0] num_bytes,
                    input logic [7:0] payload[]);
        $display("\n================================================================");
        $display("  TEST: %s", test_name);
        $display("================================================================");
        $display("  Mode: %s", master ? "MASTER" : "SLAVE");
        $display("  PID: 0x%h", pid_val);
        $display("  Checksum: %s", enhanced ? "Enhanced" : "Classic");
        $display("  Data Bytes: %0d", num_bytes + 1);
        $display("================================================================");
        
        tx_payload = new[num_bytes + 1];
        for (int i = 0; i <= num_bytes; i++) begin
            tx_payload[i] = payload[i];
            $display("  Payload[%0d] = 0x%h", i, payload[i]);
        end
        
        @(posedge clk);
        master_mode    <= master;
        enhanced_cs    <= enhanced;
        tx_pid         <= pid_val;
        tx_data_count  <= num_bytes;
        send_break     <= master; 
        start_transmit <= 1;
        @(posedge clk);
        start_transmit <= 0;
        send_break     <= 0;
        
        $display("\n[TX] Frame transmission started...");
        // Wait for the exact posedge of tx_done (Vivado safe!)
        @(posedge tx_done);
        wait_clocks(50);
        $display("\n[TX] Frame transmission complete!");
    endtask
    
    task automatic verify_received_bytes(input string test_name, input logic [7:0] expected[], input int expected_len);
        int match_count = 0; 
        
        $display("\n[VERIFY] Checking received bytes for '%s'...", test_name);
        if (rx_byte_index != expected_len) begin
            $display("  [FAIL] Expected %0d bytes, got %0d bytes", expected_len, rx_byte_index);
            test_failed++;
            return;
        end
        
        for (int i = 0; i < expected_len; i++) begin
            if (rx_buffer[i] == expected[i]) begin
                match_count++;
            end else begin
                $display("  [MISMATCH] Byte %0d: Expected 0x%h, Got 0x%h", i, expected[i], rx_buffer[i]);
            end
        end
        
        if (match_count == expected_len) begin
            $display("  [PASS] All %0d bytes received correctly!", expected_len);
            test_passed++;
        end else begin
            $display("  [FAIL] Only %0d/%0d bytes matched", match_count, expected_len);
            test_failed++;
        end
    endtask
    
    function automatic [7:0] calc_checksum(input logic enhanced, input [7:0] pid_val, input [7:0] data_bytes[]);
        logic [8:0] sum;
        sum = enhanced ? {1'b0, pid_val} : 9'b0;
        for (int i = 0; i < data_bytes.size(); i++) begin
            sum = sum + data_bytes[i];
            if (sum[8]) sum = (sum & 9'b011111111) + 1;
        end
        return ~sum[7:0];
    endfunction
    
    //========================================================================
    // Main Test Sequence
    //========================================================================
    initial begin
        $display("================================================================");
        $display("     LIN CONTROLLER TOP LEVEL - CLOSED LOOP VERIFICATION");
        $display("================================================================");
        
        lin_ctrl_cg = new();
        reset_system();

        //--------------------------------------------------------------------
        // STANDARD TESTS
        //--------------------------------------------------------------------
        send_frame("Master Frame (2 bytes)", 1, 8'h21, 1, 1, '{8'h0F, 8'h42});
        
        // Sample Coverage for Test 1
        cvg_payload_len = 2; cvg_checksum_type = 1; cvg_pid = 8'h21; lin_ctrl_cg.sample();
        wait_clocks(200);
        verify_received_bytes("Master Frame Test", '{8'h55, 8'h21, 8'h0F, 8'h42, calc_checksum(1, 8'h21, '{8'h0F, 8'h42})}, 5);

        send_frame("Master Frame - MAX (8 Bytes)", 1, 8'h63, 1, 7, '{8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08});
        
        // Sample Coverage for Test 2
        cvg_payload_len = 8; cvg_checksum_type = 1; cvg_pid = 8'h63; lin_ctrl_cg.sample();
        wait_clocks(200);
        verify_received_bytes("MAX 8 Bytes Test", '{8'h55, 8'h63, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, calc_checksum(1, 8'h63, '{8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08})}, 11);

        // --- DIRECTED TEST: Force the missing 6-byte Enhanced Checksum cross-coverage bin ---
        send_frame("Directed Test (6 Bytes, Enhanced)", 1, 8'h45, 1, 5, '{8'h11, 8'h22, 8'h33, 8'h44, 8'h55, 8'h66});
        
        cvg_payload_len = 6; cvg_checksum_type = 1; cvg_pid = 8'h45; lin_ctrl_cg.sample();
        wait_clocks(200);
        verify_received_bytes("Directed 6-Byte Test", '{8'h55, 8'h45, 8'h11, 8'h22, 8'h33, 8'h44, 8'h55, 8'h66, calc_checksum(1, 8'h45, '{8'h11, 8'h22, 8'h33, 8'h44, 8'h55, 8'h66})}, 9);


        //--------------------------------------------------------------------
        // RANDOMIZED STRESS TEST
        //--------------------------------------------------------------------
        $display("\n================================================================");
        $display("   RANDOM PAYLOAD STRESS TESTS (CLOSED LOOP)");
        $display("================================================================");
        
        for (int test_idx = 1; test_idx <= 50; test_idx++) begin
            automatic int rand_len = $urandom_range(1, 8); // Random length 1 to 8 bytes
            automatic logic [7:0] r_pid = $urandom_range(0, 255);
            automatic logic r_enh = $urandom_range(0, 1);
            
            logic [7:0] rand_payload [];
            logic [7:0] expected_rx [];
            
            rand_payload = new[rand_len];
            expected_rx = new[rand_len + 3]; // Sync + PID + Data + CS
            
            expected_rx[0] = 8'h55; // Sync
            expected_rx[1] = r_pid; // PID
            
            for (int i = 0; i < rand_len; i++) begin
                rand_payload[i] = $urandom(); // Generate random byte
                expected_rx[i+2] = rand_payload[i];
            end
            
            // Auto-calculate the expected random checksum
            expected_rx[rand_len+2] = calc_checksum(r_enh, r_pid, rand_payload);

            $display("\n--- Random Frame %0d (Length: %0d bytes) ---", test_idx, rand_len);
            send_frame($sformatf("Random Frame %0d", test_idx), 1, r_pid, r_enh, (rand_len - 1), rand_payload);
            
            // Sample Coverage for Random Test Loop
            cvg_payload_len = rand_len; cvg_checksum_type = r_enh; cvg_pid = r_pid; lin_ctrl_cg.sample();

            wait_clocks(200);
            
            verify_received_bytes($sformatf("Random Frame %0d Test", test_idx), expected_rx, expected_rx.size());
        end
        
        //--------------------------------------------------------------------
        // FINAL RESULTS
        //--------------------------------------------------------------------
        $display("\n================================================================");
        $display("     TEST RESULTS SUMMARY");
        $display("================================================================");
        $display("  Total Tests:  %0d", test_passed + test_failed);
        $display("  Passed:       %0d", test_passed);
        $display("  Failed:       %0d", test_failed);
        $display("  Success Rate: %0.1f%%", (test_passed * 100.0 / (test_passed + test_failed)));
        
        $display("\n  FUNCTIONAL COVERAGE:");
        $display("  Total Score:  %0.2f%%", lin_ctrl_cg.get_inst_coverage());

        if (test_failed == 0) $display("\n  *** ALL TESTS PASSED! YOU HAVE A BULLETPROOF LIN CONTROLLER! ***");
        else                  $display("\n  !!! Some tests failed.");
        $display("================================================================");
        $finish;
    end
endmodule