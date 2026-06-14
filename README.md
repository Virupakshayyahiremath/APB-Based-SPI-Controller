# APB-Based SPI Controller

A complete APB-based SPI Master Controller implemented in Verilog, covering the full front-end ASIC design flow — RTL coding, functional simulation in Xilinx Vivado, logic synthesis using Synopsys Design Compiler, and RTL linting using Synopsys VC Static.

---

## Table of Contents

- [Overview](#overview)
- [Block Diagram](#block-diagram)
- [Features](#features)
- [Directory Structure](#directory-structure)
- [Sub-Block Descriptions](#sub-block-descriptions)
- [APB Protocol Interface](#apb-protocol-interface)
- [SPI Protocol Modes](#spi-protocol-modes)
- [Register Map](#register-map)
- [Simulation](#simulation)
- [Synthesis](#synthesis)
- [Linting](#linting)
- [Lint Results](#lint-results)
- [Tools Used](#tools-used)

---

## Overview

This project implements a fully functional **SPI Master Controller** with an **APB (Advanced Peripheral Bus) Slave Interface**, designed as part of an AMBA-compliant SoC peripheral. The controller supports all 4 SPI modes (CPOL/CPHA), configurable baud rate, MSB/LSB-first data transfer, and generates an interrupt on transaction completion.

---

## Block Diagram

```
                        ┌─────────────────────────────────────────────┐
                        │                  spi_top                    │
                        │                                             │
  PCLK   ──────────────►│  ┌─────────────┐     ┌──────────────────┐  │
  PRESET_n ────────────►│  │  u_apb_     │     │   u_baud_gen     │  │──► sclk_o
  PSEL_i  ────────────►│  │  slave      │────►│ (Baud Rate Gen)  │  │
  PENABLE_i ──────────►│  │             │     └──────────────────┘  │
  PWRITE_i ───────────►│  │  (APB FSM)  │     ┌──────────────────┐  │──► mosi_o
  PADDR_i[2:0] ───────►│  │             │────►│   u_shift_reg    │  │◄── miso_i
  PWDATA_i[7:0] ──────►│  └─────────────┘     │ (Shift Register) │  │
                        │                      └──────────────────┘  │──► ss_o
  PRDATA_o[7:0] ◄──────│  ┌─────────────┐                           │
  PREADY_o ◄───────────│  │ u_slave_    │                           │──► spi_interrupt_req_o
  PSLVERR_o ◄──────────│  │ select      │                           │
                        │  │ (SS + TIP)  │                           │
                        │  └─────────────┘                           │
                        └─────────────────────────────────────────────┘
```

---

## Features

- APB-compliant slave interface (AMBA 2.0)
- SPI Master with all 4 modes: Mode 0 (CPOL=0, CPHA=0), Mode 1 (CPOL=0, CPHA=1), Mode 2 (CPOL=1, CPHA=0), Mode 3 (CPOL=1, CPHA=1)
- Configurable baud rate via SPR[2:0] register
- MSB-first and LSB-first data transfer selection
- Automatic Slave Select (SS) assertion and de-assertion
- Transaction-in-progress (TIP) flag
- SPI Write Acknowledge (SPISWAI) low-power mode
- Interrupt generation on transfer completion
- Fully synthesizable RTL in Verilog
- Lint-clean: 0 Fatals, 0 Errors in Synopsys VC Static

---

## Directory Structure

```
APB-Based SPI Controller/
│
├── rtl/                             # RTL source files
│   ├── spi_top.v                    # Top-level integration module
│   ├── apb_slave.v                  # APB slave FSM + register decode
│   ├── spi_baud_generator.v         # SCLK baud rate generator
│   ├── shift_reg.v                  # SPI TX/RX shift register
│   └── spi_slave_select.v           # Slave select + TIP controller
│
├── tb/                              # Testbench files
│   ├── spi_top_tb.v                 # Top-level testbench
│   ├── apb_slave_tb.v               # APB slave testbench
│   ├── shift_reg_tb.v               # Shift register testbench
│   ├── spi_baud_generator_tb.v      # Baud generator testbench
│   └── spi_slave_select_tb.v        # Slave select testbench
│
├── sim/                             # Vivado simulation projects
│   ├── apb_slave/                   # Vivado project — apb_slave
│   ├── shift_reg/                   # Vivado project — shift_reg
│   ├── spi_top/                     # Vivado project — spi_top
│   ├── apb_slave.xpr                # Vivado project file
│   ├── shift_reg.xpr                # Vivado project file
│   ├── spi_top.xpr                  # Vivado project file
│   └── vivado.jou                   # Vivado journal log
│
├── waveforms/                       # Simulation waveform screenshots
│   ├── apb_slave_waveform.png
│   ├── shift_reg_waveform.png
│   ├── spi_baud_generator_waveform.png
│   ├── spi_slave_select_waveform.png
│   └── spi_top_waveform.png
│
├── linting_report.png               # VC Static lint summary screenshot
├── synthesis_schematic_1.png        # Synopsys DC synthesis schematic
├── synthesis_schematic_2.png        # Synopsys DC synthesis schematic (detailed)
├── .gitattributes
└── README.md
```

---

## Sub-Block Descriptions

### 1. `apb_slave.v` — APB Slave Interface
Implements the APB protocol state machine with two states: **SETUP** and **ENABLE**.
- Decodes `PADDR_i` to read/write internal SPI control registers
- Drives `PREADY_o`, `PSLVERR_o`, and `PRDATA_o`
- Issues `rd_enb` and `wr_enb` strobes to downstream blocks

### 2. `spi_baud_generator.v` — Baud Rate Generator
Generates the SPI clock (`sclk_o`) and phase-shifted clocks for MOSI and MISO sampling.
- SPR[2:0] configures the clock divider ratio
- Produces `miso_receive_sclk`, `mosi_send_sclk` and their inverted variants for CPOL/CPHA support
- Outputs `BaudRateDivisor[15:0]` for reference

### 3. `shift_reg.v` — SPI Shift Register
Handles the actual serial data transmission and reception.
- TX: shifts out `data_mosi_i[7:0]` bit by bit on MOSI, MSB-first or LSB-first based on `lsbfe_i`
- RX: captures MISO bit by bit into `data_miso_o[7:0]`
- Bit counters `count`, `count1`, `count2`, `count3` track TX and RX progress

### 4. `spi_slave_select.v` — Slave Select Controller
Controls the `ss_o` (active-low) signal and the TIP (Transaction In Progress) flag.
- Asserts `ss_o` low when a transfer begins
- De-asserts after 8 bits are transferred
- `tip_o` indicates an active transfer to prevent APB write collisions

---

## APB Protocol Interface

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| PCLK | Input | 1 | APB clock |
| PRESET_n | Input | 1 | Active-low reset |
| PSEL_i | Input | 1 | Peripheral select |
| PENABLE_i | Input | 1 | Enable phase |
| PWRITE_i | Input | 1 | Write enable |
| PADDR_i | Input | 3 | Register address |
| PWDATA_i | Input | 8 | Write data |
| PRDATA_o | Output | 8 | Read data |
| PREADY_o | Output | 1 | Transfer ready |
| PSLVERR_o | Output | 1 | Slave error |

---

## SPI Protocol Modes

| Mode | CPOL | CPHA | Clock Idle | Sample Edge |
|------|------|------|------------|-------------|
| 0 | 0 | 0 | Low | Rising |
| 1 | 0 | 1 | Low | Falling |
| 2 | 1 | 0 | High | Falling |
| 3 | 1 | 1 | High | Rising |

---

## Register Map

| Address (PADDR) | Register | Description |
|-----------------|----------|-------------|
| 3'h0 | SPCR | SPI Control Register (SPE, MSTR, CPOL, CPHA, SPR[2:0]) |
| 3'h1 | SPSR | SPI Status Register (SPIF, WCOL, SPI2X) |
| 3'h2 | SPDR | SPI Data Register (TX write / RX read) |
| 3'h4 | SPER | SPI Extension Register (ICNT, ESPR[1:0]) |
| 3'h5 | SPMODE | Mode override register |

---

## Simulation

RTL simulation was performed in **Xilinx Vivado** using Verilog testbenches for each sub-block and the integrated top level.

Each testbench covers:
- Reset behaviour
- APB write and read transactions
- SPI transfer across all 4 CPOL/CPHA modes
- MSB-first and LSB-first transfers
- Baud rate configurations via SPR[2:0]
- Interrupt assertion on transfer completion

**To run simulation in Vivado:**
1. Create a new Vivado project
2. Add all files from `rtl/` and `tb/` as sources
3. Set the desired `*_tb.v` as the top simulation module
4. Run Behavioral Simulation
5. View waveforms in the Vivado waveform viewer

---

## Synthesis

Logic synthesis was performed using **Synopsys Design Compiler** targeting the `lsi_10k` library.

**Key synthesis results:**
- Top module: `spi_top`
- Technology library: `lsi_10k.db`
- All sub-blocks synthesized and elaborated cleanly
- No unresolved references or missing ports

---

## Linting

RTL linting was performed using **Synopsys VC Static** with the `lint_rtl` goal.

**Lint run script:** `lint/apb_spi_lint.tcl`

```tcl
set_app_var enable_lint true
set_app_var enable_lint_save true
configure_lint_setup -goal lint_rtl
set search_path { ../rtl ../lib }
set_app_var link_library "../lib/lsi_10k.db"
set top spi_top
analyze -format verilog ../rtl/apb_slave.v
analyze -format verilog ../rtl/shift_reg.v
analyze -format verilog ../rtl/spi_baud_generator.v
analyze -format verilog ../rtl/spi_slave_select.v
analyze -format verilog ../rtl/spi_top.v
elaborate $top
check_lint
redirect APB_SPI_lint_report.txt { report_violations -verbose }
report_violations -verbose
checkpoint_session -session APB_SPI_session -full
```

---

## Lint Results

| Stage | Fatals | Errors | Warnings | Infos |
|-------|--------|--------|----------|-------|
| LANGUAGE_CHECK | 0 | 0 | 6 | 1 |
| STRUCTURAL_CHECK | 0 | 0 | 0 | 8 |
| **Total** | **0** | **0** | **6** | **9** |

| Tag | Severity | Count | Note |
|-----|----------|-------|------|
| STARC05-2.11.3.1 | Warning | 6 | Counters in shift_reg.v — combinational and sequential in same always block. Style violation only, functionally correct. |
| RegInputOutput-ML | Info | 8 | APB ports (PREADY_o, PRDATA_o, PSEL_i etc.) driven combinationally — correct per APB spec. |
| ReportPortInfo-ML | Info | 1 | Auto-generated port info report. |

---

## Tools Used

| Tool | Version | Purpose |
|------|---------|---------|
| Xilinx Vivado | 2023.x | RTL simulation and waveform verification |
| Synopsys Design Compiler | O-2018.06 | Logic synthesis |
| Synopsys VC Static | Latest | RTL linting |
| Verilog | IEEE 1364-2001 | RTL coding language |

---

## Author

**Virupakshayya**