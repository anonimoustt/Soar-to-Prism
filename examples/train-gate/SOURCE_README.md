# Railroad Level Crossing — Soar Multi-Agent Simulation

A multi-agent simulation of a railroad level crossing using the **Soar 9.6 cognitive architecture**. Three independent Soar agents (Train, Controller, Gate) coordinate a safe crossing sequence. Python acts as a **medium only** — it ticks the clock and mirrors controller state to the gate; all decisions live inside Soar production rules.

---

## Versions

| Component | Version |
|-----------|---------|
| Python | 3.12 |
| Soar | 9.6.4 |
| Python_sml_ClientInterface | Bundled with Soar 9.6.4 |
| OS | Windows 10/11 (tested) |

> **No pip installs required.** Only Python standard library + the Soar SML bindings that ship with the Soar distribution.

---

## Setup

1. **Install Python 3.12 (64-bit)** — [python.org/downloads](https://www.python.org/downloads/)
   > Must be **64-bit** — the Soar SML `.pyd` binding is 64-bit only. The installer defaults to 64-bit on modern Windows.

2. **Clone the repo**
   ```
   git clone https://github.com/rsen2025-star/Multi-agent-Train-gate.git
   cd "Multi-agent Train_gate"
   ```

3. **Download Soar 9.6.4**
   - Go to: https://github.com/SoarGroup/Soar/releases/tag/releases%2F9.6.4
   - Download: `SoarSuite_9.6.4-Multiplatform.zip`
   - Extract the zip — it will contain a top-level folder with `bin/`, `lib/`, `include/`, etc.

4. **Place only the `bin/` folder** from the extracted zip into `SOAR/bin/` inside the project root:
   ```
   Multi-agent Train_gate/
   └── SOAR/
       └── bin/
           ├── Python_sml_ClientInterface.py
           ├── _Python_sml_ClientInterface.pyd   (Windows 64-bit DLL)
           └── Soar.dll
   ```
   The environment sets the DLL search path automatically via `os.add_dll_directory` — no manual PATH changes needed.

5. **Verify tkinter is available** (it ships with the standard Python installer on Windows):
   ```
   python -m tkinter
   ```
   A small test window should appear. If it errors, reinstall Python using the official installer (not a stripped/minimal build).

6. **Run**
   ```
   python run/test_ticks.py
   ```

---

## Project Structure

```
Multi-agent Train_gate/
├── SOAR/                              # Soar local install — NOT in repo (see Setup)
│   └── bin/                           # SML binaries + Python_sml_ClientInterface
│
├── agents/
│   ├── train/
│   │   ├── train.soar                 # v1 (reference only)
│   │   └── train_v2.soar              # v2 — ACTIVE
│   ├── controller/
│   │   ├── controller.soar            # v1 (reference only)
│   │   └── controller_v2.soar         # v2 — ACTIVE
│   └── gate/
│       ├── gate.soar                  # approach-time variant (reference)
│       └── gate_v2.soar               # ctrl-state variant — ACTIVE
│
├── env/
│   ├── environment.py                 # v1 (reference only)
│   └── environment_v2.py             # v2 — ACTIVE
│
├── run/
│   ├── main.py                        # Entry point (UI mode)
│   └── test_ticks.py                  # Terminal verify — prints WME per tick
│
├── ui/
│   └── tick_viewer.py                 # Step-by-step WME viewer (tkinter)
│
└── Uppaal/
    └── Uppaal_version_of_Train_Gate.xml   # UPPAAL PTA model for formal verification
```

---

## Architecture (v2 — current)

### Design Principle

Python is a **medium, not an orchestrator**. It ticks a shared clock and mirrors the controller's state to the gate input-link. No routing logic, no decision-making, no imposed agent order.

All timing decisions are encoded directly in **Soar production rules** using absolute clock guards.

### Agents

| Agent | State Machine | Decision Basis |
|-------|--------------|----------------|
| Train | `far → near → in → far` | Absolute clock guards |
| Controller | `S0 → S1 → S2 → S3 → S0` | Absolute clock guards |
| Gate | `up ↔ down` | `ctrl-state` from input-link (mirrored from Controller by Python) |

### Soar Guards (v2)

**Train (`train_v2.soar`)**

| Transition | Guard |
|---|---|
| Far → Near | `1 < clock <= 2` |
| Near → In | `6 < clock <= 9` |
| In → Far | `9 < clock <= 12` |

**Controller (`controller_v2.soar`)**

| Transition | Guard |
|---|---|
| S0 → S1 | `1 < clock <= 2` |
| S1 → S2 | `2 < clock <= 6` |
| S2 → S3 | `12 < clock <= 14` |
| S3 → S0 | `14 < clock <= 17` |

**Gate (`gate_v2.soar`)**

| Transition | Guard |
|---|---|
| Up → Down | `ctrl-state == 2` |
| Down → Up | `ctrl-state == 0` |

### Inter-Agent Communication

Soar agents have fully **isolated working memory** — no cross-agent rule access.

```
Controller WM  ^ctrl-state N
      ↓  Python polls each tick and rebroadcasts
Gate input-link  ^ctrl-state N
```

### Python Tick Structure (`environment_v2.py`)

```python
clock += 1
_inject_clock()           # write ^clock N to all 3 agents' input-links
_broadcast_ctrl_state()   # write ^ctrl-state N to gate input-link
kernel.RunAllAgents(5, sml_PHASE)   # Soar kernel manages all agents
_refresh_states()         # read agent WM into Python cache
```

`kernel.RunAllAgents()` is the Soar-recommended pattern for multi-agent execution.

### 1-Tick Lag (by design)

The gate sees the controller's `ctrl-state` from the **previous tick** — Python broadcasts the cached value before agents run. Safety still holds: the gate lowers before the train enters the crossing.

---

## Timing (one full cycle = 17 ticks)

| Tick (clock) | Train | Controller | Gate |
|---|---|---|---|
| 1 | far | S0 | up |
| 2 | **near** | **S1** | up |
| 3–6 | near | **S2** | **down** (sees ctrl=2) |
| 7–9 | near → **in** | S2 | down |
| 10–12 | **far** | S2 | down |
| 13–14 | far | **S3** | down |
| 15–17 | far | **S0** | **up** (sees ctrl=0) |

---

## Running

### Terminal verify (one full cycle)
```
python run/test_ticks.py
```
Prints WME snapshots for all three agents at each tick (17 ticks).

### UI — step-by-step WME viewer
```
python ui/tick_viewer.py
```

---

## UPPAAL Formal Verification

A Timed Automata (PTA) model of all three agents is in `Uppaal/Uppaal_version_of_Train_Gate.xml`.

### Verified Queries

| Query | Result | Meaning |
|---|---|---|
| `A[] not deadlock` | ✅ Satisfied | No deadlock in any reachable state |
| `A[] (Train.In imply Gate.Down)` | ✅ Satisfied | Gate always down when train is in crossing |
| `A[] (Train.Near imply Gate.Down)` | ❌ Expected | Deliberate delay — gate closes after approach, not instantly |

