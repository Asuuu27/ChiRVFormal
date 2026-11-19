module ibex_rvfi (
  input  logic        clk_i,
  input  logic        rst_ni,

  output logic        instr_req_o,
  input  logic        instr_gnt_i,
  input  logic        instr_rvalid_i,
  output logic [31:0] instr_addr_o,
  input  logic [31:0] instr_rdata_i,
  input  logic        instr_err_i,

  output logic        data_req_o,
  input  logic        data_gnt_i,
  input  logic        data_rvalid_i,
  output logic        data_we_o,
  output logic [ 3:0] data_be_o,
  output logic [31:0] data_addr_o,
  output logic [31:0] data_wdata_o,
  input  logic [31:0] data_rdata_i,
  input  logic        data_err_i,

  output logic        rvfi_valid,
  output logic [63:0] rvfi_order,
  output logic [31:0] rvfi_insn,
  output logic        rvfi_trap,
  output logic        rvfi_halt,
  output logic        rvfi_intr,
  output logic [ 1:0] rvfi_mode,
  output logic [ 1:0] rvfi_ixl,
  output logic [ 4:0] rvfi_rs1_addr,
  output logic [ 4:0] rvfi_rs2_addr,
  output logic [31:0] rvfi_rs1_rdata,
  output logic [31:0] rvfi_rs2_rdata,
  output logic [ 4:0] rvfi_rd_addr,
  output logic [31:0] rvfi_rd_wdata,
  output logic [31:0] rvfi_pc_rdata,
  output logic [31:0] rvfi_pc_wdata,
  output logic [31:0] rvfi_mem_addr,
  output logic [ 3:0] rvfi_mem_rmask,
  output logic [ 3:0] rvfi_mem_wmask,
  output logic [31:0] rvfi_mem_rdata,
  output logic [31:0] rvfi_mem_wdata,

  output logic        rf_we,
  output logic [ 4:0] rf_waddr,
  output logic [31:0] rf_wdata
);
  import ibex_pkg::*;

  logic [4:0] rf_raddr_a, rf_raddr_b;
  logic [31:0] rf_rdata_a, rf_rdata_b;
  logic core_rf_we;
  logic [4:0] core_rf_waddr;
  logic [31:0] core_rf_wdata, rf_write_data;
  logic [IC_TAG_SIZE-1:0] unused_tag_data [IC_NUM_WAYS];
  logic [IC_LINE_SIZE-1:0] unused_line_data [IC_NUM_WAYS];
  assign unused_tag_data = '{default: '0};
  assign unused_line_data = '{default: '0};

  ibex_core #(
    .PMPEnable(1'b0),
    .MHPMCounterNum(0),
    .RV32E(1'b0),
    .RV32M(RV32MNone),
    .RV32B(RV32BNone),
    .BranchTargetALU(1'b0),
    .WritebackStage(1'b0),
    .ICache(1'b0),
    .ICacheECC(1'b0),
    .BranchPredictor(1'b0),
    .DbgTriggerEn(1'b0),
    .ResetAll(1'b1),
    .SecureIbex(1'b0),
    .DummyInstructions(1'b0),
    .RegFileECC(1'b0),
    .MemECC(1'b0)
  ) u_core (
    .clk_i,
    .rst_ni,
    .hart_id_i(32'b0),
    .boot_addr_i(32'b0),
    .instr_req_o,
    .instr_gnt_i,
    .instr_rvalid_i,
    .instr_addr_o,
    .instr_rdata_i,
    .instr_err_i,
    .data_req_o,
    .data_gnt_i,
    .data_rvalid_i,
    .data_we_o,
    .data_be_o,
    .data_addr_o,
    .data_wdata_o,
    .data_rdata_i,
    .data_err_i,
    .dummy_instr_id_o(),
    .dummy_instr_wb_o(),
    .rf_raddr_a_o(rf_raddr_a),
    .rf_raddr_b_o(rf_raddr_b),
    .rf_waddr_wb_o(core_rf_waddr),
    .rf_we_wb_o(core_rf_we),
    .rf_wdata_wb_ecc_o(core_rf_wdata),
    .rf_rdata_a_ecc_i(rf_rdata_a),
    .rf_rdata_b_ecc_i(rf_rdata_b),
    .ic_tag_req_o(),
    .ic_tag_write_o(),
    .ic_tag_addr_o(),
    .ic_tag_wdata_o(),
    .ic_tag_rdata_i(unused_tag_data),
    .ic_data_req_o(),
    .ic_data_write_o(),
    .ic_data_addr_o(),
    .ic_data_wdata_o(),
    .ic_data_rdata_i(unused_line_data),
    .ic_scr_key_valid_i(1'b1),
    .ic_scr_key_req_o(),
    .irq_software_i(1'b0),
    .irq_timer_i(1'b0),
    .irq_external_i(1'b0),
    .irq_fast_i(15'b0),
    .irq_nm_i(1'b0),
    .irq_pending_o(),
    .debug_req_i(1'b0),
    .crash_dump_o(),
    .double_fault_seen_o(),
    .rvfi_valid,
    .rvfi_order,
    .rvfi_insn,
    .rvfi_trap,
    .rvfi_halt,
    .rvfi_intr,
    .rvfi_mode,
    .rvfi_ixl,
    .rvfi_rs1_addr,
    .rvfi_rs2_addr,
    .rvfi_rs3_addr(),
    .rvfi_rs1_rdata,
    .rvfi_rs2_rdata,
    .rvfi_rs3_rdata(),
    .rvfi_rd_addr,
    .rvfi_rd_wdata,
    .rvfi_pc_rdata,
    .rvfi_pc_wdata,
    .rvfi_mem_addr,
    .rvfi_mem_rmask,
    .rvfi_mem_wmask,
    .rvfi_mem_rdata,
    .rvfi_mem_wdata,
    .rvfi_ext_pre_mip(),
    .rvfi_ext_post_mip(),
    .rvfi_ext_nmi(),
    .rvfi_ext_nmi_int(),
    .rvfi_ext_debug_req(),
    .rvfi_ext_debug_mode(),
    .rvfi_ext_rf_wr_suppress(),
    .rvfi_ext_mcycle(),
    .rvfi_ext_mhpmcounters(),
    .rvfi_ext_mhpmcountersh(),
    .rvfi_ext_ic_scr_key_valid(),
    .rvfi_ext_irq_valid(),
    .fetch_enable_i(IbexMuBiOn),
    .alert_minor_o(),
    .alert_major_internal_o(),
    .alert_major_bus_o(),
    .core_busy_o()
  );

`ifdef IBEX_MUTATE_RF_WRITE
  // The negative task corrupts x1 at the actual register-file write input.
  assign rf_write_data = core_rf_we && core_rf_waddr == 5'd1
                        ? core_rf_wdata ^ 32'h1 : core_rf_wdata;
`else
  assign rf_write_data = core_rf_wdata;
`endif

  ibex_register_file_ff #(
    .RV32E(1'b0),
    .DataWidth(32),
    .DummyInstructions(1'b0),
    .WrenCheck(1'b0),
    .RdataMuxCheck(1'b0)
  ) u_regfile (
    .clk_i,
    .rst_ni,
    .test_en_i(1'b0),
    .dummy_instr_id_i(1'b0),
    .dummy_instr_wb_i(1'b0),
    .raddr_a_i(rf_raddr_a),
    .rdata_a_o(rf_rdata_a),
    .raddr_b_i(rf_raddr_b),
    .rdata_b_o(rf_rdata_b),
    .waddr_a_i(core_rf_waddr),
    .wdata_a_i(rf_write_data),
    .we_a_i(core_rf_we),
    .err_o()
  );

  // With no writeback stage, RVFI and the register file update at the same edge.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rf_we    <= 1'b0;
      rf_waddr <= '0;
      rf_wdata <= '0;
    end else begin
      rf_we    <= core_rf_we && core_rf_waddr != 5'd0;
      rf_waddr <= core_rf_waddr;
      rf_wdata <= rf_write_data;
    end
  end
endmodule
