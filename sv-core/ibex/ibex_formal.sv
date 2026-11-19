module ibex_formal (
  input logic        clk_i,
  input logic [11:0] imm_a_i,
  input logic [11:0] imm_b_i
);
  localparam logic [31:0] BootPc = 32'h80;
  localparam logic [31:0] BranchPc = 32'h90;
  localparam logic [31:0] FinishPc = 32'ha0;

  logic rst_ni = 1'b0;
  logic [11:0] imm_a, imm_b;
  always @(posedge clk_i) begin
    rst_ni <= 1'b1;
    if (!rst_ni) begin
      // The solver chooses the two immediates once, on the reset edge.
      imm_a <= imm_a_i;
      imm_b <= imm_b_i;
    end
  end

  function automatic logic [31:0] program_word(input logic [31:0] address);
    case (address)
      BootPc:   return {imm_a, 20'h00093}; // addi x1, x0, A
      32'h84:   return {imm_b, 20'h08113}; // addi x2, x1, B
      32'h88:   return 32'h00202023;       // sw x2, 0(x0)
      32'h8c:   return 32'h00002183;       // lw x3, 0(x0)
      BranchPc: return 32'h00018463;       // beq x3, x0, +8
      32'h94:   return 32'h00100313;       // addi x6, x0, 1 (fall-through)
      32'h98:   return 32'h0080026f;       // jal x4, +8
      32'h9c:   return 32'h00100393;       // addi x7, x0, 1 (skipped by JAL)
      FinishPc: return 32'h00020293;       // addi x5, x4, 0
      default:  return 32'h00000013;       // nop
    endcase
  endfunction

  logic instr_req_o, instr_gnt_i, instr_rvalid_i;
  logic [31:0] instr_addr_o, instr_rdata_i;
  logic data_req_o, data_gnt_i, data_rvalid_i, data_we_o;
  logic [3:0] data_be_o;
  logic [31:0] data_addr_o, data_wdata_o, data_rdata_i;

  logic rvfi_valid, rvfi_trap, rvfi_halt, rvfi_intr;
  logic [63:0] rvfi_order;
  logic [1:0] rvfi_mode, rvfi_ixl;
  logic [31:0] rvfi_insn, rvfi_pc_rdata, rvfi_pc_wdata;
  logic [4:0] rvfi_rs1_addr, rvfi_rs2_addr, rvfi_rd_addr;
  logic [31:0] rvfi_rs1_rdata, rvfi_rs2_rdata, rvfi_rd_wdata;
  logic [31:0] rvfi_mem_addr, rvfi_mem_rdata, rvfi_mem_wdata;
  logic [3:0] rvfi_mem_rmask, rvfi_mem_wmask;
  logic rf_we;
  logic [4:0] rf_waddr;
  logic [31:0] rf_wdata;

  ibex_rvfi dut (.instr_err_i(1'b0), .data_err_i(1'b0), .*);

  // Grant legal instruction word requests immediately. Return the sampled word
  // one cycle later, even if the fetch unit has since redirected.
  assign instr_gnt_i = rst_ni && instr_req_o;
  always @(posedge clk_i) begin
    instr_rvalid_i <= instr_gnt_i;
    if (instr_gnt_i) instr_rdata_i <= program_word(instr_addr_o);
  end

  // One shared word at address zero. The selected program only uses aligned
  // LW/SW. Byte enables still drive the actual state update.
  logic [31:0] data_word;
  logic pending_mem, pending_write, saw_store, saw_load;
  logic [31:0] pending_addr, pending_wdata, pending_rdata;
  logic [3:0] pending_mask;
  logic retire, retire_load, retire_store;
  assign data_gnt_i = rst_ni && data_req_o;
  assign retire = rst_ni && rvfi_valid;
  assign retire_load = retire && rvfi_insn[6:0] == 7'b0000011;
  assign retire_store = retire && rvfi_insn[6:0] == 7'b0100011;

  always @(posedge clk_i) begin
    data_rvalid_i <= data_gnt_i;
    if (!rst_ni) begin
      data_word <= '0;
      pending_mem <= 1'b0;
      saw_store <= 1'b0;
      saw_load <= 1'b0;
    end else begin
      if (retire_load || retire_store) pending_mem <= 1'b0;
      if (data_gnt_i) begin
        data_word_access: assert (data_addr_o == 0 && data_be_o == 4'hf);
        one_outstanding_data: assert (!pending_mem || retire_load || retire_store);
        data_request_sequence: assert (!saw_load && data_we_o == !saw_store);
        pending_mem <= 1'b1;
        pending_write <= data_we_o;
        pending_addr <= data_addr_o;
        pending_mask <= data_be_o;
        pending_wdata <= data_wdata_o;
        pending_rdata <= data_word;
        data_rdata_i <= data_word;
        if (data_we_o) begin
          saw_store <= 1'b1;
          for (integer byte_idx = 0; byte_idx < 4; byte_idx = byte_idx + 1) begin
            if (data_be_o[byte_idx])
              data_word[8*byte_idx +: 8] <= data_wdata_o[8*byte_idx +: 8];
          end
        end else begin
          saw_load <= 1'b1;
        end
      end
      if (retire_load || retire_store) begin
        mem_event_matches_rvfi: assert (
          pending_mem && pending_write == retire_store && pending_addr == rvfi_mem_addr
          && pending_mask == (retire_store ? rvfi_mem_wmask : rvfi_mem_rmask)
        );
      end
      if (retire_load) begin
        load_matches_response: assert (saw_store && pending_rdata == rvfi_mem_rdata);
      end
      if (retire_store) begin
        store_matches_request: assert (pending_wdata == rvfi_mem_wdata);
      end
    end
  end

  // Use the sampled bus response and actual store payload as the reference
  // model's memory inputs. RVFI masks are size masks at this Ibex revision.
  ActionChecker checker_i (
    .clock(clk_i),
    .reset(!rst_ni),
    .commit_valid(retire),
    .commit_excp(rvfi_trap),
    .commit_inst(rvfi_insn),
    .commit_pc(rvfi_pc_rdata),
    .commit_npc(rvfi_pc_wdata),
    .writeback_rs1Addr(rvfi_rs1_addr),
    .writeback_rs2Addr(rvfi_rs2_addr),
    .writeback_rs1Data(rvfi_rs1_rdata),
    .writeback_rs2Data(rvfi_rs2_rdata),
    .writeback_rdAddr(rvfi_rd_addr),
    .writeback_rdData(rvfi_rd_wdata),
    .writeback_csrWr(1'b0),
    .writeback_csrAddr(12'b0),
    .writeback_csrNdata(32'b0),
    .mem_read_valid(retire_load && pending_mem && !pending_write),
    .mem_read_addr(pending_addr),
    .mem_read_data(pending_rdata),
    .mem_read_memWidth(pending_mask == 4'hf ? 6'd32 : 6'd0),
    .mem_write_valid(retire_store && pending_mem && pending_write),
    .mem_write_addr(pending_addr),
    .mem_write_data(pending_wdata),
    .mem_write_memWidth(pending_mask == 4'hf ? 6'd32 : 6'd0)
  );

  logic [63:0] last_order;
  logic [31:0] next_pc;
  logic [31:0] expected_x1, expected_x2;
  assign expected_x1 = {{20{imm_a[11]}}, imm_a};
  assign expected_x2 = expected_x1 + {{20{imm_b[11]}}, imm_b};

  always @(posedge clk_i) begin
    if (rst_ni) rf_write_has_retirement: assert (!rf_we || retire);
  end

  always @(posedge clk_i) begin
    if (!rst_ni) begin
      last_order <= 64'd0; // This Ibex revision numbers the first record 1.
      next_pc <= BootPc;
    end else if (retire) begin
      normal_retire: assert (!rvfi_trap && !rvfi_intr && !rvfi_halt);
      mode_rv32_m: assert (rvfi_mode == 2'b11 && rvfi_ixl == 2'b01);
      ordered_retire: assert (rvfi_order == last_order + 64'd1);
      continuous_pc: assert (rvfi_pc_rdata == next_pc);
      fetched_instruction: assert (rvfi_insn == program_word(rvfi_pc_rdata));
      rf_write_matches_rvfi: assert (
        rf_we == (rvfi_rd_addr != 0)
        && (!rf_we || (rf_waddr == rvfi_rd_addr && rf_wdata == rvfi_rd_wdata))
      );
      last_order <= rvfi_order;
      next_pc <= rvfi_pc_wdata;

      if (rvfi_pc_rdata == 32'h84) begin
        raw_addi: assert (rvfi_rs1_rdata == expected_x1);
      end
      if (rvfi_pc_rdata == BranchPc) begin
        store_to_load: assert (rvfi_rs1_rdata == expected_x2);
      end
      if (rvfi_pc_rdata == FinishPc) begin
        jal_link_dependency: assert (rvfi_rs1_rdata == 32'h9c);
      end

      five_plus_three: cover (
        imm_a == 12'd5 && imm_b == 12'd3 &&
        rvfi_pc_rdata == 32'h84 && rvfi_insn == 32'h00308113 &&
        !rvfi_trap && rvfi_rs1_addr == 5'd1 && rvfi_rs1_rdata == 32'd5 &&
        rvfi_rd_addr == 5'd2 && rvfi_rd_wdata == 32'd8 &&
        rf_we && rf_waddr == 5'd2 && rf_wdata == 32'd8 &&
        rvfi_pc_wdata == 32'h88
      );
      first_retirement: cover (rvfi_pc_rdata == BootPc && rvfi_rd_addr == 5'd1 && !rvfi_trap);
      raw_retirement: cover (rvfi_pc_rdata == 32'h84 && !rvfi_trap);
      store_load_retirement: cover (retire_load && saw_store && !rvfi_trap);
      branch_taken: cover (rvfi_pc_rdata == BranchPc && rvfi_pc_wdata == 32'h98 && !rvfi_trap);
      branch_fallthrough: cover (rvfi_pc_rdata == BranchPc && rvfi_pc_wdata == 32'h94 && !rvfi_trap);
      end_to_end: cover (rvfi_pc_rdata == FinishPc && rvfi_rd_addr == 5'd5 && !rvfi_trap);
    end
  end
endmodule
