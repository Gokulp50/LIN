`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 27.04.2026 12:40:07
// Design Name: 
// Module Name: lin_tx_tb
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

module lin_tx_tb();

    //========================================================================
    // Signals
    //========================================================================
    logic       clk, rstn, tx_tick;
    
    // Control Interface
    logic       start_transmit, master_mode, send_break, enhanced_cs;
    logic [7:0] pid;
    logic [2:0] data_count;
    
    // Data Interface
    logic [7:0] tx_data;
    logic       tx_data_valid;
    logic       tx_data_ready;
    
    // Outputs
    logic       tx_busy, tx_done, lin_tx;

    //========================================================================
    // Instantiate the DUT
    //========================================================================
    lin_tx dut (.*);

    //========================================================================
    // Clock & Tick Generation
    //========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz clock
    end

    // 1x Baud Rate Tick (Pulsing every 16 clocks just for fast simulation)
    logic [3:0] tick_div = 0;
    always @(posedge clk) begin
        tick_div <= tick_div + 1;
        tx_tick  <= (tick_div == 4'd0);
    end

    //========================================================================
    // Automated Data Feeder (Simulates the CPU's memory buffer)
    //========================================================================
    logic [7:0] payload [0:7];
    int byte_index = 0;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            tx_data       <= 0;
            tx_data_valid <= 0;
            byte_index    <= 0;
        end else begin
            // We REMOVED the "default pulse" to 0. 
            // We must KEEP tx_data_valid high so the slower TX FSM can catch it!
            
            // If the transmitter asks for data, give it the next byte!
            if (tx_data_ready) begin
                tx_data       <= payload[byte_index];
                tx_data_valid <= 1'b1;
                $display("  [TB-FEEDER] Pushing TX Data Byte %0d: 0x%h", byte_index, payload[byte_index]);
                byte_index    <= byte_index + 1;
            end
            
            // Reset index and turn off the valid signal when the whole frame is done
            if (tx_done) begin
                byte_index    <= 0;
                tx_data_valid <= 1'b0;
            end
        end
    end

    //========================================================================
    // Main Test Sequence
    //========================================================================
    initial begin
        $display("================================================================");
        $display("   LIN PROTOCOL TRANSMITTER: Full Frame Simulation");
        $display("================================================================");
        
        // Initialize
        rstn           = 0;
        start_transmit = 0;
        master_mode    = 0;
        send_break     = 0;
        enhanced_cs    = 0;
        pid            = 0;
        data_count     = 0;
        
        // Clear Payload Buffer
        for (int i=0; i<8; i++) payload[i] = 8'h00;
        
        #100; rstn = 1; #100;

        //--------------------------------------------------------------------
        // TEST 1: Master Mode Full Frame
        // Setup: PID = 0x21, 2 Data Bytes (0x0F, 0x42), Enhanced Checksum
        // Expected Checksum result (from prior testing) should be 0x8D
        //--------------------------------------------------------------------
        $display("\n--- Starting Test 1: Sensor Frame ---");
        
        // Load the payload array
        payload[0] = 8'h0F;
        payload[1] = 8'h42;
        
        @(posedge clk);
        master_mode    <= 1'b1;    // We are the master
        send_break     <= 1'b1;    // Send the 13-bit wake-up break field
        enhanced_cs    <= 1'b1;    // Use LIN 2.1 Enhanced Checksum
        pid            <= 8'h21;   // Frame ID
        data_count     <= 3'd1;    // 0 = 1 byte, 1 = 2 bytes. So 1 means 2 total bytes.
        start_transmit <= 1'b1;    // FIRE!
        
        @(posedge clk);
        start_transmit <= 1'b0;

        // Wait for the transmitter to finish the entire frame
        wait(tx_done == 1'b1);
        
        $display("\n================================================================");
        $display("   TRANSMISSION COMPLETE! Open your Waveform Viewer!");
        $display("   You should see: Break -> 0x55 -> 0x21 -> 0x0F -> 0x42 -> 0x8D");
        $display("================================================================");
        
        #500;
        $finish;
    end

    //========================================================================
    // Serial Wire & State Monitor
    //========================================================================
    string state_name;
    always @(posedge clk) begin
        if (rstn && dut.state != $past(dut.state)) begin
            case (dut.state)
                dut.TX_IDLE:       state_name = "TX_IDLE";
                dut.TX_BREAK:      state_name = "TX_BREAK";
                dut.TX_BREAK_DEL:  state_name = "TX_BREAK_DELIM";
                dut.TX_SYNC:       state_name = "TX_SYNC (0x55)";
                dut.TX_PID:        state_name = "TX_PID";
                dut.TX_DATA:       state_name = "TX_DATA";
                dut.TX_INTER_BYTE: state_name = "TX_INTER_BYTE";
                dut.TX_CHECKSUM:   state_name = "TX_CHECKSUM";
                dut.TX_DONE:       state_name = "TX_DONE";
                default:           state_name = "UNKNOWN";
            endcase
            $display("[%0t ns] FSM -> %s", $time, state_name);
        end
    end

endmodule