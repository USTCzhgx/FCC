`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// File Name: nfc_test_top.v
// Description: NFC test top module
// Date: 2025.12.7
// Author: SCMI ZGX
////////////////////////////////////////////////////////////////////////////////

/*
2025.12.7 SCMI ZGX
optimize the code
*/

module nfc_test_top #(
    parameter CHAN_NUM   = 1,    // Number of CHANNELs
    parameter WAY_NUM    = 1,    // Number of WAYs
    parameter DATA_WIDTH = 32
    // parameter ADATA_W = 32    // AXI_LITE address and data width
)(
    // Clock & Reset Inputs
    input                         sys_clk_50M,
    input                         sys_rst_n,     
    input                         s_axil_aclk,
    input                         s_axil_aresetn,
    
    // UART interface (commented out)
    // input                         uart_rxd,     // [15:0] addr [31:0] data
    // output                        uart_txd,

    // AXI LITE Slave Interface
    input  [4:0]                  axil_awaddr,
    input  [2:0]                  axil_awprot,
    input                         axil_awvalid,
    output                        axil_awready,
    
    input  [31:0]                 axil_wdata,
    input  [3:0]                  axil_wstrb,
    input                         axil_wvalid,
    output                        axil_wready,
    
    output [1:0]                  axil_bresp,
    output                        axil_bvalid,
    input                         axil_bready,
    
    input  [4:0]                  axil_araddr,
    input  [2:0]                  axil_arprot,
    input                         axil_arvalid,
    output                        axil_arready,
    
    output [31:0]                 axil_rdata,
    output [1:0]                  axil_rresp,
    output                        axil_rvalid,
    input                         axil_rready,

    // AXI Stream interface
    input  wire                        s_axis_tvalid,
    output wire                        s_axis_tready,
    input  wire [DATA_WIDTH-1:0]       s_axis_tdata,
    input  wire [DATA_WIDTH/8-1:0]     s_axis_tkeep,
    input  wire                        s_axis_tlast,

    output wire                        m_axis_tvalid,
    input  wire                        m_axis_tready,
    output wire [DATA_WIDTH-1:0]       m_axis_tdata,
    output wire [DATA_WIDTH/8-1:0]     m_axis_tkeep,
    output wire [15:0]                 m_axis_tid,
    output wire [3:0]                  m_axis_tuser,
    output wire                        m_axis_tlast,

    // NAND Flash Physical Interfaces
    output [CHAN_NUM*WAY_NUM-1:0]      O_NAND_CE_N,
    input  [CHAN_NUM*WAY_NUM-1:0]      I_NAND_RB_N,
    output [CHAN_NUM-1:0]              O_NAND_WE_N,
    output [CHAN_NUM-1:0]              O_NAND_CLE,
    output [CHAN_NUM-1:0]              O_NAND_ALE,
    output [CHAN_NUM-1:0]              O_NAND_WP_N,
    output [CHAN_NUM-1:0]              O_NAND_RE_P,
    output [CHAN_NUM-1:0]              O_NAND_RE_N,
    inout  [CHAN_NUM-1:0]              IO_NAND_DQS_P,
    inout  [CHAN_NUM-1:0]              IO_NAND_DQS_N,
    inout  [CHAN_NUM*8-1:0]            IO_NAND_DQ
);

// ============================================================================
// Internal Signals
// ============================================================================

    // NFC control signals and parameters
    wire [CHAN_NUM-1:0]    gen_ready;
    wire [CHAN_NUM-1:0]    gen_valid;
    wire [15:0]            gen_opc;
    wire [47:0]            gen_lba;
    wire [23:0]            gen_len;
    wire [15:0]            packet_err;
    wire [23:0]            wrfifo_rest_0;

    // Clock and reset signals
    wire                   sys_clk_c;      // System clock (buffered)
    wire                   sys_rst_n_c;    // System reset (buffered)
    wire                   user_clk;       // User clock
    wire                   user_resetn;    // User reset
    wire                   nand_clk_fast;  // NAND fast clock (400MHz)
    wire                   nand_clk_slow;  // NAND slow clock (100MHz), 1/4 of fast clock
    wire                   nand_clk_rst;   // NAND clock reset
    wire                   nand_usr_rstn;  // NAND user reset
    wire                   nand_usr_clk;   // NAND user clock (50MHz)
    wire                   refclk;         // Reference clock (200MHz)

// ============================================================================
// Clock and Reset Buffers
// ============================================================================

    IBUF sys_clk_buf (
        .O  (sys_clk_c),      // Single-ended output clock
        .I  (sys_clk_50M)     // Single-ended input clock
    );

    IBUF sys_rst_n_buf (
        .O  (sys_rst_n_c),    // Reset signal after buffering
        .I  (sys_rst_n)       // Original reset input (active low)
    );

// ============================================================================
// Clock Management Module
// ============================================================================

    nand_mmcm nand_mmcm (
        .clk_in       (sys_clk_c),      // Input clock 50MHz
        .reset        (~sys_rst_n_c),   // Reset signal
        .clk_out_fast (nand_clk_fast),  // Output 400MHz clock
        .clk_out_slow (nand_clk_slow),  // Output 100MHz clock
        .clk_reset    (nand_clk_rst),   // Clock reset signal
        .usr_resetn   (nand_usr_rstn),  // User reset signal (active low)
        .clk_out_usr  (user_clk),       // Output 50MHz user clock
        .refclk       (refclk)          // Output 200MHz reference clock
    );

// ============================================================================
// AXI Lite Slave Register File
// ============================================================================

    regfile regfile (
        .S_AXI_ACLK      (s_axil_aclk),
        .S_AXI_ARESETN   (s_axil_aresetn),
        
        .S_AXI_AWADDR    (axil_awaddr),
//        .S_AXI_AWPROT    (axil_awprot),
        .S_AXI_AWVALID   (axil_awvalid),
        .S_AXI_AWREADY   (axil_awready),
        
        .S_AXI_WDATA     (axil_wdata),
        .S_AXI_WSTRB     (axil_wstrb),
        .S_AXI_WVALID    (axil_wvalid),
        .S_AXI_WREADY    (axil_wready),
        
        .S_AXI_BRESP     (axil_bresp),
        .S_AXI_BVALID    (axil_bvalid),
        .S_AXI_BREADY    (axil_bready),
        
        .S_AXI_ARADDR    (axil_araddr),
//        .S_AXI_ARPROT    (axil_arprot),
        .S_AXI_ARVALID   (axil_arvalid),
        .S_AXI_ARREADY   (axil_arready),
        
        .S_AXI_RDATA     (axil_rdata),
        .S_AXI_RRESP     (axil_rresp),
        .S_AXI_RVALID    (axil_rvalid),
        .S_AXI_RREADY    (axil_rready),
        
        .nfc_opcode      (gen_opc),
        .nfc_lba         (gen_lba),
        .nfc_len         (gen_len),
        .nfc_valid       (gen_valid)
    );

// ============================================================================
// NFC Channel Test Module
// ============================================================================

    nfc_channel_test #(
        .DATA_WIDTH (32),      // Data width is 32 bits
        .WAY_NUM    (1),       // Number of NAND channels is 1
        .PATCH      ("FALSE")  // Do not use FMC pin mapping patch
    ) nfc_channel_test_0 (
        // Clock and Reset
        .xdma_clk      (user_clk),
        .xdma_resetn   (nand_usr_rstn),
        .nand_clk_fast (nand_clk_fast),
        .nand_clk_slow (nand_clk_slow),
        .nand_clk_rst  (nand_clk_rst),
        .nand_usr_rstn (nand_usr_rstn),
        .nand_usr_clk  (user_clk),
        .ref_clk       (refclk),

        // Control Interface
        .o_ready        (gen_ready[0]),
        .i_valid        (gen_valid[0]),
        .i_opc          (gen_opc),
        .i_lba          (gen_lba),
        .i_len          (gen_len),

        // AXI Stream Write Interface
        .axis_wvalid_0  (s_axis_tvalid),
        .axis_wready_0  (s_axis_tready),
        .axis_wdata_0   (s_axis_tdata),
        .axis_wkeep_0   (s_axis_tkeep),
        .axis_wlast_0   (s_axis_tlast),

        // AXI Stream Read Interface
        .axis_rvalid_0  (m_axis_tvalid),
        .axis_rready_0  (m_axis_tready),
        .axis_rdata_0   (m_axis_tdata),
        .axis_rkeep_0   (m_axis_tkeep),
        .axis_rid_0     (m_axis_tid),
        .axis_ruser_0   (m_axis_tuser),
        .axis_rlast_0   (m_axis_tlast),

        // NAND Flash Interface
        .O_NAND_CE_N    (O_NAND_CE_N[0]),    // 1way
        .I_NAND_RB_N    (I_NAND_RB_N[0]),    // 1way
        .O_NAND_WE_N    (O_NAND_WE_N[0]),
        .O_NAND_CLE     (O_NAND_CLE[0]),
        .O_NAND_ALE     (O_NAND_ALE[0]),
        .O_NAND_WP_N    (O_NAND_WP_N[0]),
        .O_NAND_RE_P    (O_NAND_RE_P[0]),
        .O_NAND_RE_N    (O_NAND_RE_N[0]),
        .IO_NAND_DQS_P  (IO_NAND_DQS_P[0]),
        .IO_NAND_DQS_N  (IO_NAND_DQS_N[0]),
        .IO_NAND_DQ     (IO_NAND_DQ[7:0])    // 1way 8 bits
    );

endmodule
