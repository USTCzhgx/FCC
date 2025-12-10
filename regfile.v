`timescale 1ns/1ps
////////////////////////////////////////////////////////////////////////////////
// File Name: regfile.v
// Description: Register file module
// Date: 2025.12.7
// Author: SCMI ZGX
//description:a simple register file module
////////////////////////////////////////////////////////////////////////////////
// o_status [1:0]
//    2'b00 : IDLE
//    2'b01 : BUSY (DQ bus busy)
//    2'b10 : WAIT (wait RB_n ready)
//    2'b11 : READY (RB_n ready)
/*
2025.12.7 SCMI ZGX
update the code
delete sync module
*/

module regfile #(
    parameter integer AXI_DATA_WIDTH = 32,
    parameter integer AXI_ADDR_WIDTH = 5     // enough for 6 regs
)(
    input                           S_AXI_ACLK,
    input                           S_AXI_ARESETN,

    // AXI4-Lite Write Address
    input  [AXI_ADDR_WIDTH-1:0]     S_AXI_AWADDR,
    input                           S_AXI_AWVALID,
    output                          S_AXI_AWREADY,

    // AXI4-Lite Write Data
    input  [AXI_DATA_WIDTH-1:0]     S_AXI_WDATA,
    input  [(AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input                           S_AXI_WVALID,
    output                          S_AXI_WREADY,

    // AXI4-Lite Write Response
    output [1:0]                    S_AXI_BRESP,
    output                          S_AXI_BVALID,
    input                           S_AXI_BREADY,

    // AXI4-Lite Read Address
    input  [AXI_ADDR_WIDTH-1:0]     S_AXI_ARADDR,
    input                           S_AXI_ARVALID,
    output                          S_AXI_ARREADY,

    // AXI4-Lite Read Data
    output [AXI_DATA_WIDTH-1:0]     S_AXI_RDATA,
    output [1:0]                    S_AXI_RRESP,
    output                          S_AXI_RVALID,
    input                           S_AXI_RREADY,

    // NFC control signals output
(* MARK_DEBUG="true" *)     output [47:0]                   nfc_lba,
(* MARK_DEBUG="true" *)     output [23:0]                   nfc_len,
(* MARK_DEBUG="true" *)     output [15:0]                   nfc_opcode,
(* MARK_DEBUG="true" *)     output                          nfc_valid,

    input                         req_fifo_almost_full,
    input [7:0]                   o_sr_0,
    input [1:0]                   o_status_0
);

////////////////////////////////////////////////////////////////////////////////
// AXI-lite basic signals
////////////////////////////////////////////////////////////////////////////////

wire [31:0] reg_status;

reg axi_awready, axi_wready;
reg axi_bvalid;
reg axi_arready, axi_rvalid;
reg [1:0] axi_rresp, axi_bresp;
reg [AXI_ADDR_WIDTH-1:0] axi_awaddr, axi_araddr;
reg [AXI_DATA_WIDTH-1:0] axi_rdata;

reg req_fifo_almost_full_r;
reg [1:0] top_status;
reg [7:0] top_sr_r;

assign S_AXI_AWREADY = axi_awready;
assign S_AXI_WREADY  = axi_wready;
assign S_AXI_BRESP   = axi_bresp;
assign S_AXI_BVALID  = axi_bvalid;

assign S_AXI_ARREADY = axi_arready;
assign S_AXI_RDATA   = axi_rdata;
assign S_AXI_RRESP   = axi_rresp;
assign S_AXI_RVALID  = axi_rvalid;

////////////////////////////////////////////////////////////////////////////////
// Slave Registers (6 registers)
////////////////////////////////////////////////////////////////////////////////

reg [31:0] slv_reg [0:5];

wire slv_reg_wren = S_AXI_WVALID && axi_wready && S_AXI_AWVALID && axi_awready;
wire slv_reg_rden = S_AXI_ARVALID && axi_arready;

integer i;

// Write Address Ready
always @(posedge S_AXI_ACLK) begin
    if (~S_AXI_ARESETN) begin
        axi_awready <= 0;
        axi_awaddr  <= 0;
    end else begin
        if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID)
            axi_awready <= 1;
        else
            axi_awready <= 0;

        if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID)
            axi_awaddr <= S_AXI_AWADDR;
    end
end

// Write Data Ready
always @(posedge S_AXI_ACLK) begin
    if (~S_AXI_ARESETN)
        axi_wready <= 0;
    else begin
        if (~axi_wready && S_AXI_WVALID && S_AXI_AWVALID)
            axi_wready <= 1;
        else
            axi_wready <= 0;
    end
end

// Write response
always @(posedge S_AXI_ACLK) begin
    if (~S_AXI_ARESETN) begin
        axi_bvalid <= 0;
        axi_bresp  <= 2'b00;
    end else begin
        if (axi_awready && S_AXI_AWVALID && axi_wready && S_AXI_WVALID && ~axi_bvalid)
            axi_bvalid <= 1;
        else if (S_AXI_BREADY && axi_bvalid)
            axi_bvalid <= 0;
    end
end

// Read Address
always @(posedge S_AXI_ACLK) begin
    if (~S_AXI_ARESETN) begin
        axi_arready <= 0;
        axi_araddr  <= 0;
    end else begin
        if (~axi_arready && S_AXI_ARVALID) begin
            axi_arready <= 1;
            axi_araddr <= S_AXI_ARADDR;
        end else
            axi_arready <= 0;
    end
end

// Read Data
always @(posedge S_AXI_ACLK) begin
    if (~S_AXI_ARESETN) begin
        axi_rvalid <= 0;
        axi_rresp <= 2'b00;
    end else begin
        if (axi_arready && S_AXI_ARVALID && ~axi_rvalid) begin
            axi_rvalid <= 1;
            axi_rresp <= 2'b00;
        end else if (axi_rvalid && S_AXI_RREADY)
            axi_rvalid <= 0;
    end
end

// Register write
always @(posedge S_AXI_ACLK) begin
    if (~S_AXI_ARESETN) begin
        for (i=0; i<6; i=i+1)
            slv_reg[i] <= 32'd0;
    end else if (slv_reg_wren) begin
        case (axi_awaddr[4:2])   // Each 4 bytes is one register
            3'h0: begin
                for (i=0;i<4;i=i+1)
                    if (S_AXI_WSTRB[i]) slv_reg[0][8*i +: 8] <= S_AXI_WDATA[8*i +: 8];
            end
            3'h1: begin
                for (i=0;i<4;i=i+1)
                    if (S_AXI_WSTRB[i]) slv_reg[1][8*i +: 8] <= S_AXI_WDATA[8*i +: 8];
            end
            3'h2: begin
                for (i=0;i<4;i=i+1)
                    if (S_AXI_WSTRB[i]) slv_reg[2][8*i +: 8] <= S_AXI_WDATA[8*i +: 8];
            end
            3'h3: begin
                for (i=0;i<4;i=i+1)
                    if (S_AXI_WSTRB[i]) slv_reg[3][8*i +: 8] <= S_AXI_WDATA[8*i +: 8];
            end
            3'h4: begin
                for (i=0;i<4;i=i+1)
                    if (S_AXI_WSTRB[i]) slv_reg[4][8*i +: 8] <= S_AXI_WDATA[8*i +: 8];
            end
            3'h5: begin
                for (i=0;i<4;i=i+1)
                    if (S_AXI_WSTRB[i]) slv_reg[5][8*i +: 8] <= S_AXI_WDATA[8*i +: 8];
            end
        endcase
    end
end

always @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
    if (!S_AXI_ARESETN) begin
        top_status <= 0;
        top_sr_r   <= 0;
        req_fifo_almost_full_r <=0;
    end else begin
        top_status <= o_status_0;
        top_sr_r   <= o_sr_0;
        req_fifo_almost_full_r <= req_fifo_almost_full;
    end
end


assign reg_status = {21'd0, top_status, top_sr_r, req_fifo_almost_full_r}; // [31:11]=0, [10:9]=top_status, [8:1]=top_sr_r, [0]=req_fifo_almost_full_r




// Register read
always @(*) begin
    case (axi_araddr[4:2])
        3'h0: axi_rdata = slv_reg[0];
        3'h1: axi_rdata = slv_reg[1];
        3'h2: axi_rdata = slv_reg[2];
        3'h3: axi_rdata = slv_reg[3];
        3'h4: axi_rdata = slv_reg[4];
        3'h5: axi_rdata = reg_status;
        default: axi_rdata = 32'hDEAD_BEEF;
    endcase
end




////////////////////////////////////////////////////////////////////////////////
// NFC output register explanation (recommended register definition)
//
// reg0 = LBA[31:0]
// reg1 = {LBA[47:32], LEN[15:0]}
// reg2 = {LEN[23:16], opcode[15:0]}
// reg3 = valid write 1 trigger once
////////////////////////////////////////////////////////////////////////////////


assign nfc_opcode = slv_reg[0][15:0]; 
assign nfc_len = slv_reg[1][23:0]; 
assign nfc_lba = {slv_reg[3][15:0], slv_reg[2][31:0]};



// nfc_valid pulse: write reg3 bit0 = 1 raise 1 cycle
reg valid_pulse;

always @(posedge S_AXI_ACLK) begin
    if (~S_AXI_ARESETN)
        valid_pulse <= 0;
    else begin
        if (slv_reg_wren && axi_awaddr[4:2] == 3'h4)
            valid_pulse <= S_AXI_WDATA[0];   // bit0 is trigger bit
        else
            valid_pulse <= 0;
    end
end

assign nfc_valid = valid_pulse;

endmodule
