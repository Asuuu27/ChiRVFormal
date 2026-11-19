# 从零接入 χRVFormal 到 Ibex

2026-11-19 · 目标为固定配置下可复现的 Ibex 整核有界验证基线。

## 五步接入与复核

| 步骤 | 工程实现 | 可观察的结果 |
| --- | --- | --- |
| 1　写出单条指令的预期 | 用 [config.json](config.json) 选择 RV32I、下一 PC 和访存检查。复用 χRVFormal 生成的 ActionChecker | 以 x0 为源的 ADDI 写入 x1，第二条 ADDI 立即使用 x1 |
| 2　确定在哪一拍采样 | [ibex.sources](ibex.sources) 和 [ibex_rvfi.sv](ibex_rvfi.sv) 展开原版核与寄存器文件，导出同次退休记录 | 退休指令、PC、操作数、目的寄存器可在 RVFI 有效拍一同读取 |
| 3　让程序运行到退休 | [ibex_formal.sv](ibex_formal.sv) 提供复位、指令 ROM、取指响应、数据内存与首条退休覆盖 | 可以从一条实际到达的退休轨迹开始排查接线 |
| 4　确认报告与硬件一致 | 在物理写端口采样，在数据总线授权时保存事务，分别与对应的退休记录比较 | 具体波形中 x1 写 5，下一条读 5 并向 x2 写 8。另外覆盖同地址写后读、分支两向和 JAL 链接值 |
| 5　检验接线能否暴露错误 | [run.py](run.py) 分别运行 BMC、cover 和写回注错，负例仅翻转实际写入 x1 的最低位 | 回归要求负例命中 `rf_write_matches_rvfi` |

在仓库根目录按第 2、3 节准备工具和固定版本的 Ibex，执行以下命令即可重新生成检查器并运行三项任务。

```bash
python3 sv-core/ibex/run.py --ibex-dir ../ibex
```

脚本打印本次运行目录。原始覆盖摘要给出各目标对应的 VCD，生成的 SBY 文件保留求解参数。交付时的三项运行摘要见[验收证据](#5-回归验收与证据)。

## 1. 要验证什么

Ibex 是 32 位 RISC-V 处理器。退休指一条指令执行完毕并提交架构效果。Ibex 用 RVFI（RISC-V Formal Interface）在同一拍报告该指令的机器码、PC、寄存器操作数、写回和访存。χRVFormal 的 `ActionChecker` 用指令、当前 PC 和源操作数计算应产生的动作，再比较实际报告。Scala/Chisel 负责生成检查器，Ibex 和适配器均使用 SystemVerilog。适配器还采集实际寄存器文件写端口和数据总线，检查报告与这些硬件事件是否一致。

BMC（有界模型检查）在设定步数内搜索违反 `assert` 的轨迹。`cover` 则要求求解器给出一条能到达指定行为的轨迹。求解范围受环境约束，下面的测试顶层用程序 ROM 和内存模型限定 Ibex 收到的输入。基线用包含 5 种指令的混合程序建立，正常检查、覆盖和负例三项均达到预期时，回归才返回成功。

## 2. 固定配置与工具

| 项目 | 本次配置 |
| --- | --- |
| Ibex | `0d1b1723253cdf804aad263e805544d54aa5aa57`，原版 `ibex_core` 和 `ibex_register_file_ff` |
| χRVFormal | 基于 `92c1e238e445e9348168ec70d872706c9bbc2ebf`，接入代码在 `sv-core/ibex/` |
| 处理器配置 | 32 个整数寄存器，`RV32MNone`、`RV32BNone`，关闭 PMP、缓存、分支预测和独立写回级。IRQ、调试请求置零。复位向量输入为 0，首个指令地址为 `0x80` |
| 参考模型 | RV32I，开启 `CheckNPC`、`CheckMem`，关闭检查器寄存延迟。程序只提供 32 位编码，Ibex 的压缩指令硬件仍可用 |
| 实测环境 | Ubuntu 24.04 WSL2，Temurin 17.0.16，sbt 1.8.2，Scala 2.12.17，Chisel 3.6.0，OSS CAD Suite 2026-11-18，Yosys 0.71+50 `583f380c6`（Slang 前端），SBY v0.71-7-gb21f778，Boolector 3.2.4 |

在 Ubuntu 24.04 中可用 `sudo apt install git python3 openjdk-17-jdk` 准备基础工具，再按官方说明安装 sbt，下载并解压对应平台的 OSS CAD Suite，执行 `source <解压目录>/oss-cad-suite/environment`。本机的 JDK 和 sbt launcher 在 Windows 侧运行，形式化工具在 WSL 侧运行。本机用 JDK 21 启动旧版 Scala 编译过程时遇到 constant pool 错误，切到 JDK 17 后生成成功。[sbt 安装说明](https://www.scala-sbt.org/1.x/docs/Setup.html) · [OSS CAD Suite 2026-11-18](https://github.com/YosysHQ/oss-cad-suite-build/releases/tag/2026-11-18)

## 3. 获取源码并运行

在含本接入代码的 `ChiRVFormal` 根目录运行。以下命令把上游 Ibex 取到旁边的新目录。

```bash
git init ../ibex
git -C ../ibex remote add origin https://github.com/lowRISC/ibex.git
git -C ../ibex fetch --depth 1 origin 0d1b1723253cdf804aad263e805544d54aa5aa57
git -C ../ibex checkout --detach FETCH_HEAD

java -version
yosys -m slang -p 'help read_slang'
sby --version
boolector --version
python3 sv-core/ibex/run.py --ibex-dir ../ibex
```

脚本核对 Git 工作副本的提交和跟踪文件状态。若使用解压后的官方源码档案，请自行核对压缩包的 SHA-256，参考值为 `d3d6787279b871d34eab59460857006ee4c6b5060710ce09605130341028eb91`。默认展开 32 步，每项求解任务超时 300 秒。可用 `--task bmc|cover|negative` 只跑单项，或用 `--depth` 和 `--timeout` 调整边界。每次回归在 `build/ibex/run-*/` 创建独立运行目录。[Ibex 源码档案](https://codeload.github.com/lowRISC/ibex/tar.gz/0d1b1723253cdf804aad263e805544d54aa5aa57)

如果模型生成和形式化工具分布在两侧，可先在装有 JDK 17 / sbt 的环境运行第一条命令，再在装有 OSS CAD Suite 的环境运行第二条。两侧均从同一份 `ChiRVFormal` 根目录启动。修改 `config.json` 后重新生成模型。

```bash
sbt 'svcore/runMain svcore.Main -m action -c sv-core/ibex/config.json -t build/ibex/generated'
python3 sv-core/ibex/run.py --ibex-dir ../ibex --checker build/ibex/generated/ActionChecker.sv
```

## 4. 接线和环境

`ibex.sources` 列出固定配置的 RTL 和头文件目录。`ibex_rvfi.sv` 实例化核心与寄存器文件，导出 RVFI 和实际写端口。`ibex_formal.sv` 实现运行环境，通过生成的 `ActionChecker` 执行单条指令动作检查，并补充跨提交与副作用检查。

| 检查器信号 | Ibex 侧的来源 |
| --- | --- |
| `commit_valid` / `commit_excp` | 复位释放后的 `rvfi_valid` / `rvfi_trap`。合法程序意外产生 trap 时断言报错 |
| `commit_inst` / `commit_pc` / `commit_npc` | 同次 RVFI 记录的 `insn` / `pc_rdata` / `pc_wdata` |
| `writeback_rs*` / `writeback_rd*` | 同次 RVFI 的寄存器编号和数据。真实写端口及 RVFI 同一时钟边沿锁存，断言在下一边沿比较这两份锁存值。寄存器文件忽略对 x0 的写入 |
| `mem_read_*` / `mem_write_*` | 从实际请求捕获地址、字节使能、写数据和读响应数据，在退休时送入检查器。对齐字访问的字节使能 `4'hf` 映射为位宽 `32` |

访存类型用退休指令的 opcode 区分。此 Ibex 版本的 RVFI 读掩码也可能在 store 或其他指令上有值。对齐 LW/SW 可直接比较有效地址与总线地址、掩码和数据。扩展到 byte/halfword 时，需要另行对齐总线 word 地址、lane、掩码和数据，处理读值符号扩展。[固定版本 RVFI 实现](https://github.com/lowRISC/ibex/blob/0d1b1723253cdf804aad263e805544d54aa5aa57/rtl/ibex_core.sv)

复位只在初始步有效。取指和数据侧对请求立即授权，下一拍返回响应，始终无总线错误。指令 ROM 按地址返回固定程序，两条 ADDI 的 12 位立即数 A、B 在复位边沿由求解器自由选择并锁存。数据侧只有地址 `0x0` 的一个可读写字，按写字节使能更新并用于后续读响应。断言检查实际请求最多一次写、随后最多一次读，完整读写序列由 cover 提供可达性证据。提交顺序在此固定版本从 1 开始。

| PC | 程序 | 观察点 |
| --- | --- | --- |
| `0x80` / `0x84` | `addi x1,x0,A` / `addi x2,x1,B` | x0、符号扩展、x1 写回及下一条的 RAW 依赖 |
| `0x88` / `0x8c` | `sw x2,0(x0)` / `lw x3,0(x0)` | 实际存取请求、掩码、数据和同地址 store→load |
| `0x90` / `0x94` | `beq x3,x0,+8` / `addi x6,x0,1` | 和为零时跳转，非零时执行顺序路径 |
| `0x98` / `0x9c` / `0xa0` | `jal x4,+8` / 被跳过的指令 / `addi x5,x4,0` | 检查跳转目标、链接值 `0x9c` 与后续读取 |

### 跟一次 ADDI 退休

在本次运行目录的 `cover/PASS` 中找到 `five_plus_three` 并打开对应 VCD。在 `ibex_formal` 顶层选取复位释放、`rvfi_valid=1` 的采样点。第一条指令在 `0x80` 退休，机器码为 `0x00500093`，x1 的报告写回和实际写端口均为 5。第二条在 `0x84` 退休，机器码为 `0x00308113`，源值为 5，x2 的两份写数据均为 8，下一 PC 为 `0x88`。这个 cover 只指定一条希望看见的轨迹。其他目标和 BMC 仍能够选择不同立即数。

再打开 `negative/FAIL` 对应的 `negative/engine_0/trace.vcd`，在首条退休处比较同一顶层的 `rf_wdata` 和 `rvfi_rd_wdata`。两者最低位不同，正好解释 `rf_write_matches_rvfi` 的反例。前者来自实际送进寄存器文件的写数据，后者来自 Ibex 的退休报告。沿这两条路径回到 `ibex_rvfi.sv`，可以看到它们如何对齐到同一次写回。

## 5. 回归验收与证据

交付回归从 Scala 源码生成检查器，在固定配置下用 Boolector 展开 32 步。以下文件为 SymbiYosys 在本次验收运行中输出的原始摘要。

| 验收项 | 实测结果 | 求解器摘要 |
| --- | --- | --- |
| 正常 BMC | 32 步窗口内无断言反例 | [BMC PASS](evidence/bmc-PASS.txt) |
| 七项覆盖 | 首次退休、ADDI 依赖、指定的 5+3、写后读、分支跳转、分支顺序、JAL 链接值依赖均可达 | [Cover PASS](evidence/cover-PASS.txt) |
| 实际写回注错 | 第 6 步出现预期反例，目标断言为 `rf_write_matches_rvfi` | [Negative FAIL](evidence/negative-FAIL.txt) |

下面是从本次指定输入的波形裁出的顶层信号，可直接用波形查看器打开。完整层次的 VCD 由回归脚本生成。[两次 ADDI 的波形](evidence/five-plus-three.vcd)

## 6. 结论的适用范围

这项基线验证固定 Ibex 配置、固定指令布局和符号立即数在指定窗口中的行为。它覆盖 ADDI、SW、LW、BEQ、JAL 在该程序中的组合，以及真实写端口、数据请求和退休报告的对应关系。每条 cover 只给出一条能达到目标的轨迹，所有立即数组合的退休进展需要单独的性质。其余待验证项包括自由指令流、全部整数指令与不同寄存器组合、byte/halfword、等待与总线错误、中断及异常语义、更多配置和无界性质。
