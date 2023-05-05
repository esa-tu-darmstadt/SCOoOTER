/*
 * Class for generating riscv-dv programs without use of *any* CSRs. Test is finished by writing
 * to tapasco-riscv interrupt register. 
 */

class riscv_no_csr_asm_program_gen extends riscv_asm_program_gen;
    `uvm_object_utils(riscv_no_csr_asm_program_gen)
    
    function new (string name = "");
        super.new(name);
    endfunction

    /*function void gen_program_header();
        string str[$];
        instr_stream.push_back(".include \"user_define.h\"");
        instr_stream.push_back(".globl _start");
        instr_stream.push_back(".section .text");
        if (cfg.disable_compressed_instr) begin
          instr_stream.push_back(".option norvc;");
        end
        str.push_back(".include \"user_init.s\"");
        str.push_back("j h0_init");
        gen_section("_start", str);
    endfunction*/
    
    
    
    virtual function void gen_program_header();
    string str[$];
    instr_stream.push_back(".include \"user_define.h\"");
    instr_stream.push_back(".globl _start");
    instr_stream.push_back(".section .text");
    if (cfg.disable_compressed_instr) begin
      instr_stream.push_back(".option norvc;");
    end
    str.push_back(".include \"user_init.s\"");
    
    str.push_back($sformatf("csrr x5, 0x%0x", MHARTID));
    for (int hart = 0; hart < cfg.num_of_harts; hart++) begin
      str = {str, $sformatf("li x6, %0d", hart),
                  $sformatf("beq x5, x6, h%0d_trap_vec_init", hart)};
    end
    gen_section("_start", str);
  endfunction
  
  
      // Setup trap vector - MTVEC, STVEC, UTVEC
  virtual function void trap_vector_init(int hart);
    string instr[];
    privileged_reg_t trap_vec_reg;
    string tvec_name;
    foreach(riscv_instr_pkg::supported_privileged_mode[i]) begin
      case(riscv_instr_pkg::supported_privileged_mode[i])
        MACHINE_MODE:    trap_vec_reg = MTVEC;
        SUPERVISOR_MODE: trap_vec_reg = STVEC;
        USER_MODE:       trap_vec_reg = UTVEC;
        default: `uvm_info(`gfn, $sformatf("Unsupported privileged_mode %0s",
                           riscv_instr_pkg::supported_privileged_mode[i]), UVM_LOW)
      endcase
      // Skip utvec init if trap delegation to u_mode is not supported
      if ((riscv_instr_pkg::supported_privileged_mode[i] == USER_MODE) &&
          !riscv_instr_pkg::support_umode_trap) continue;
      if (riscv_instr_pkg::supported_privileged_mode[i] < cfg.init_privileged_mode) continue;
      tvec_name = trap_vec_reg.name();
      instr = {instr, $sformatf("la x%0d, %0s%0s_handler",
                                cfg.gpr[0], hart_prefix(hart), tvec_name.tolower())};
      if (SATP_MODE != BARE && riscv_instr_pkg::supported_privileged_mode[i] != MACHINE_MODE) begin
        // For supervisor and user mode, use virtual address instead of physical address.
        // Virtual address starts from address 0x0, here only the lower 20 bits are kept
        // as virtual address offset.
        instr = {instr,
                 $sformatf("slli x%0d, x%0d, %0d", cfg.gpr[0], cfg.gpr[0], XLEN - 20),
                 $sformatf("srli x%0d, x%0d, %0d", cfg.gpr[0], cfg.gpr[0], XLEN - 20)};
      end
      instr = {instr, $sformatf("ori x%0d, x%0d, %0d", cfg.gpr[0], cfg.gpr[0], cfg.mtvec_mode)};
      instr = {instr, $sformatf("csrw 0x%0x, x%0d # %0s",
                                 trap_vec_reg, cfg.gpr[0], trap_vec_reg.name())};
      instr = {instr, "li x9, 0x11000010", "li x23, 0x304", "slli x23, x23, 8", "addi x23, x23, 0x3", "sw x23, 0(x9)"};
      instr = {instr, $sformatf("j h%0d_init", hart)};
    end
    gen_section(get_label("trap_vec_init", hart), instr);
  endfunction
  

    virtual function void gen_program_end(int hart);
        if (hart == 0) begin
          string str[$];
          str.push_back("lui t5, 0x11000");
          str.push_back("lui t6, 0x4");
          str.push_back("add t5, t5, t6");
          str.push_back("sw gp, 0(t5)");
          gen_section("write_tohost", str);
          gen_section("_exit", {"j _exit"});
        end
    endfunction

endclass
