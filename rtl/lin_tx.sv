`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 27.04.2026 12:39:25
// Design Name: 
// Module Name: lin_tx
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
module lin_tx (
    input  logic       clk,
    input  logic       rstn,
    input  logic       tx_tick,        // 1x bit tick from baud generator
    
    // Control Interface (from Protocol FSM or CPU)
    input  logic       start_transmit, // Start a new frame transmission
    input  logic       master_mode,    // 1 = Master (can send Break), 0 = Slave
    input  logic       send_break,     // Send break field (master only)
    input  logic [7:0] pid,            // Protected ID to send
    input  logic       enhanced_cs,    // 1 = Enhanced checksum (include PID)
    input  logic [2:0] data_count,     // Number of data bytes to send (1-8, where 0 means 1 byte)
    
    // Data Interface
    input  logic [7:0] tx_data,        // Byte to transmit from CPU buffer
    input  logic       tx_data_valid,  // CPU says "New data byte is available"
    output logic       tx_data_ready,  // Transmitter says "Ready for next data byte"
    
    // Status Outputs
    output logic       tx_busy,        // High while transmitting
    output logic       tx_done,        // Pulses high when Frame is complete
    output logic       lin_tx          // Output to physical serial wire
);

    // FSM States
    typedef enum logic [3:0] {
        TX_IDLE,            
        TX_BREAK,           
        TX_BREAK_DEL,       
        TX_SYNC,            
        TX_PID,             
        TX_DATA,            
        TX_INTER_BYTE,
        TX_CHECKSUM,        
        TX_DONE             
    } tx_state_t;
    
    tx_state_t state;
    
    // Counters and Registers
    logic [4:0]  break_counter;      
    logic [3:0]  bit_counter;        
    logic [2:0]  byte_counter;       
    logic [7:0]  tx_shift_reg;       
    logic [7:0]  pid_reg;            
    logic [2:0]  total_bytes;        
    logic        use_enhanced;       
    
    // Math Engine Signals
    logic [7:0]  calc_checksum;
    logic        cs_start;
    logic        cs_data_valid;

    //-------------------------------------------------------------------------
    // Math Engine Instantiation (The one you just verified!)
    //-------------------------------------------------------------------------
    lin_checksum checksum_calc (
        .clk(clk),
        .rstn(rstn),
        .start_frame(cs_start),
        .enhanced(use_enhanced),
        .pid(pid_reg),
        .data_valid(cs_data_valid),
        .data_byte(tx_data),
        .checksum(calc_checksum)
    );
    
    //-------------------------------------------------------------------------
    // Single Synchronous FSM
    //-------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state          <= TX_IDLE;
            break_counter  <= 0;
            bit_counter    <= 0;
            byte_counter   <= 0;
            tx_shift_reg   <= 0;
            pid_reg        <= 0;
            use_enhanced   <= 0;
            total_bytes    <= 0;
            tx_busy        <= 0;
            tx_done        <= 0;
            tx_data_ready  <= 0;
            lin_tx         <= 1'b1;
            cs_start       <= 0;
            cs_data_valid  <= 0;
        end else begin
            // Default Pulses (Turn off after 1 clock)
            tx_done       <= 0;
            tx_data_ready <= 0;
            cs_start      <= 0;
            cs_data_valid <= 0;
            
            // Only process physical wire changes on the baud rate tick
            if (tx_tick) begin
                case (state)
                    TX_IDLE: begin
                        tx_busy <= 0;
                        lin_tx  <= 1'b1; 
                        
                        if (start_transmit) begin
                            tx_busy      <= 1;
                            use_enhanced <= enhanced_cs;
                            pid_reg      <= pid;
                            total_bytes  <= data_count;
                            bit_counter  <= 0;
                            cs_start     <= 1; // Tell Math Engine to reset
                            
                            if (master_mode && send_break) begin
                                state <= TX_BREAK;
                                break_counter <= 0;
                            end else begin
                                state <= TX_SYNC; // Slaves skip the break field
                            end
                        end
                    end
                    
                    TX_BREAK: begin
                        lin_tx <= 1'b0; 
                        break_counter <= break_counter + 1;
                        if (break_counter == 12) begin 
                            state <= TX_BREAK_DEL;
                        end
                    end
                    
                    TX_BREAK_DEL: begin
                        lin_tx <= 1'b1; 
                        state  <= TX_SYNC;
                        bit_counter <= 0;
                    end
                    
                    TX_SYNC: begin
                        if (bit_counter == 0) begin
                            lin_tx <= 1'b0; // Start bit
                            tx_shift_reg <= 8'h55;
                            bit_counter <= bit_counter + 1;
                        end else if (bit_counter <= 8) begin
                            lin_tx <= tx_shift_reg[0];
                            tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};
                            bit_counter <= bit_counter + 1;
                        end else begin
                            lin_tx <= 1'b1; // Stop bit
                            state <= TX_PID;
                            bit_counter <= 0;
                        end
                    end
                    
                    TX_PID: begin
                        if (bit_counter == 0) begin
                            lin_tx <= 1'b0; // Start bit
                            tx_shift_reg <= pid_reg;
                            bit_counter <= bit_counter + 1;
                        end else if (bit_counter <= 8) begin
                            lin_tx <= tx_shift_reg[0];
                            tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};
                            bit_counter <= bit_counter + 1;
                        end else begin
                            lin_tx <= 1'b1; // Stop bit
                            bit_counter <= 0;
                            byte_counter <= 0;
                            state <= TX_DATA;
                            tx_data_ready <= 1; // Ask CPU for the very first Data Byte
                        end
                    end
                    
                    TX_DATA: begin
                        if (bit_counter == 0) begin
                            // Wait here until the CPU provides valid data
                            if (tx_data_valid) begin
                                lin_tx <= 1'b0; // Start bit
                                tx_shift_reg <= tx_data;
                                cs_data_valid <= 1; // Send this exact byte to the Math Engine!
                                bit_counter <= bit_counter + 1;
                            end else begin
                                lin_tx <= 1'b1; // Hold bus idle while waiting
                            end
                        end else if (bit_counter <= 8) begin
                            lin_tx <= tx_shift_reg[0]; // LSB First
                            tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};
                            bit_counter <= bit_counter + 1;
                        end else begin
                            lin_tx <= 1'b1; // Stop bit
                            bit_counter <= 0;
                            
                            if (byte_counter == total_bytes) begin
                                state <= TX_CHECKSUM;
                            end else begin
                                byte_counter <= byte_counter + 1;
                                state <= TX_INTER_BYTE;
                            end
                        end
                    end
                    
                    TX_INTER_BYTE: begin
                        lin_tx <= 1'b1;
                        state <= TX_DATA;
                        tx_data_ready <= 1; // Ask CPU for the next Data Byte
                    end
                    
                    TX_CHECKSUM: begin
                        if (bit_counter == 0) begin
                            lin_tx <= 1'b0; // Start bit
                            tx_shift_reg <= calc_checksum; // Grab the result from the Math Engine!
                            bit_counter <= bit_counter + 1;
                        end else if (bit_counter <= 8) begin
                            lin_tx <= tx_shift_reg[0];
                            tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};
                            bit_counter <= bit_counter + 1;
                        end else begin
                            lin_tx <= 1'b1; // Stop bit
                            state <= TX_DONE;
                        end
                    end
                    
                    TX_DONE: begin
                        lin_tx <= 1'b1;
                        tx_busy <= 0;
                        tx_done <= 1;
                        state <= TX_IDLE;
                    end
                    
                    default: state <= TX_IDLE;
                endcase
            end
            
            //---------------------------------------------------------
            // Asynchronous Start Catch (Never miss a start command)
            //---------------------------------------------------------
            if (state == TX_IDLE && start_transmit && !tx_tick) begin
                tx_busy      <= 1;
                use_enhanced <= enhanced_cs;
                pid_reg      <= pid;
                total_bytes  <= data_count;
                bit_counter  <= 0;
                cs_start     <= 1; // Tell Math Engine to reset
                
                if (master_mode && send_break) begin
                    state <= TX_BREAK;
                    break_counter <= 0;
                end else begin
                    state <= TX_SYNC; 
                end
            end
        end
    end
endmodule
