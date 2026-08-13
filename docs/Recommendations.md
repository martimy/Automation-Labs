# Recommendations

## Proposed Directory Structure

As a network automation expert, I have refined the proposed folder structure to meet the specific lab requirements.

### Revised Course Folder Structure

This recommended structure maintains the `labs/labX` naming convention, uses a single virtual environment at the root, and establishes a tools directory for shared automation tools.

```text
~/labs/ (Git Repository Root)
├── .velab/                      # Unified virtual environment for the entire course
├── tools/                      # Centralized tools (provided to students)
│   ├── nc_wrapper.sh           # Shared NETCONF wrapper
│   ├── netconf_tool.py         # Shared discovery tool
│   ├── gnmi_tool.py            # Shared gNMI tool
│   ├── devicelib.py            # Common library functions
│   ├── devices.yaml            # Single source of truth for credentials
│   └── topology/               # NEW: Centralized topology for Labs 3, 4, and 5
│       └── lab-net.clab.yml    # The "persistent" three-node ring
├── lab1/                       # Linux & Git artifacts
├── lab2/
│   ├── topology/               # Lab 2 Sandbox (Retains all three initial files)
│   │   ├── throwaway1.yml      # Arista throwaway
│   │   ├── throwaway2.yml      # Nokia throwaway
│   │   └── lab-net.clab.yml    # Initial version of the real topology
│   └── scripts/                # Lab-specific Python scripts
├── lab3/                       # Data modeling and NETCONF artifacts
├── lab4/                       # gNMI and Ansible artifacts
├── lab5/                       # NetBox and CI/CD artifacts
├── .gitignore                  # Updated to ignore .velab/ and lab-specific clab directories
└── requirements.txt            # Cumulative course dependencies
```

### Strategic Implementation Details

1.  **Topology Evolution:**
    *   **Lab 2 Sandbox:** Students use `labs/lab2/topology/` to learn the basics of Containerlab, deploying the two throwaway nodes before building the initial three-node ring. 
    *   **The "Promotion":** At the start of Lab 3, students can be instructed to copy their finalized `lab2-ring.clab.yml` into the new `labs/topology/` directory. This signifies the transition from "learning the tool" to "using the infrastructure".
    *   **Lab 5 Integration:** In Lab 5, when students are required to add traffic-generating hosts, they will modify the version of the file located in `labs/topology/`. This ensures the root topology folder always contains the most current "Source of Truth" for the network.

2.  **Unified Environment Management:**
    *   By placing `.velab/` at the root, students only need to run `source ~/labs/.velab/bin/activate` regardless of which lab module they are working on.
    *   The `requirements.txt` file should be updated cumulatively. For instance, when Lab 4 introduces Ansible collections or Lab 5 introduces `pynetbox`, students simply run `pip install -r requirements.txt` again to update their existing environment.

3.  **Tools vs. Lab Deliverables:**
    *   **Tools:** Files like `nc_wrapper.sh` and `devices.yaml` are centralized in `tools/`. This prevents the "broken dependency" issue where a student fixes a bug in `devices.yaml` during Lab 3 but fails to copy the fix forward to Lab 4.
    *   **Lab Deliverables:** Scripts that are specific to an assignment's objectives (e.g., `lab3/scripts/edit_srl1.py` or `lab5/scripts/populate_netbox.py`) remain in their respective lab folders for clean grading and submission.

## Strategic Refinements

Based on the proposed unified structure, there are several strategic refinements you can implement to further professionalize the lab experience for your students and ensure the technical consistency of the course materials.

### 1. Centralize and Version the `requirements.txt`
In the current sources, students are asked to create a new `requirements.txt` for almost every lab. With a single virtual environment at the root, you should move this file to `~/labs/requirements.txt`.
*   **Expert Recommendation:** Instruct students to use `pip install -r requirements.txt` at the start of every lab. This ensures that as you introduce new libraries (e.g., adding `pygnmi` in Lab 4 or `pynetbox` in Lab 5), the students' single environment stays up to date without them needing to track which environment is active.

### 2. Refine the `devicelib.py` for Path Independence
Since scripts in `tools/` will be executed while the student's working directory is likely `~/labs/labs/labX`, pathing to configuration files like `devices.yaml` can become brittle.
*   **Expert Recommendation:** In the shared `devicelib.py` (originally introduced in Lab 3), add a helper function that uses Python’s `os` or `pathlib` modules to locate `devices.yaml` relative to the script's location, rather than the user's current directory. This prevents the "file not found" errors that often occur when students run automation from different nested folders.

### 3. Implement a Global `.gitignore` Early
The sources show that students are currently updating their `.gitignore` lab-by-lab to exclude local virtual environments like `.velab2` or `.velab3`. 
*   **Expert Recommendation:** In Lab 1, Task 8, have students create a comprehensive `.gitignore` at the root. It should proactively include:
    *   The single `.velab/` directory.
    *   Any `clab-*/` directories generated by Containerlab.
    *   Python bytecode (`__pycache__/`).
    *   The `.env` file used for NetBox tokens in Lab 5.
    This prevents the "dirty repository" issues where students accidentally commit thousands of library files or sensitive API tokens.

### 4. Transition `devices.yaml` into a "Local Source of Truth"
In Lab 5, you introduce NetBox as the formal Source of Truth. However, the students have been using `devices.yaml` since Lab 3 to manage credentials and connection parameters.
*   **Expert Recommendation:** Use the `tools/devices.yaml` as the "Bootstrap Source of Truth." You can teach students that while NetBox manages the *network* state (IPs, prefixes), the `devices.yaml` manages the *automation* state (how the scripts themselves connect). This creates a logical bridge to Lab 5's concepts.

### 5. Leverage the Centralized Topology for CI/CD
In Lab 5, Task 12, you introduce GitHub Actions to run Batfish checks. With the new structure placing the "persistent" topology in `labs/topology/lab2-ring.clab.yml`, your CI/CD pipeline becomes much simpler to write.
*   **Expert Recommendation:** The GitHub Actions workflow (`.github/workflows/config-check.yml`) can now be configured to always look at `labs/topology/` for the network definition. This allows you to run automated validation against the "production" topology every time a student pushes a change to any lab module, reinforcing the idea of continuous integration across the entire course.

### 6. Standardize Containerlab "Kind" Definitions
Lab 5 Task 3 adds Linux-kind hosts to the topology. 
*   **Expert Recommendation:** Since you are moving to a persistent topology in `labs/topology/`, ensure the `kind` definitions for `ceos` and `srl` are defined at the top level of the YAML file. This makes the file cleaner and easier for students to read when they reach the advanced tasks in Labs 4 and 5, where they must identify specific vendor capabilities (like gNMI ports).

### 7. Clarify the "Tools" vs. "Scripts" Distinction
To avoid confusion, clearly define what belongs in `tools/` versus individual `labX/scripts/` folders.
*   **Common Scripts:** Generic utilities (e.g., `nc_wrapper.sh`, `gnmi_tool.py`) and libraries (`devicelib.py`).
*   **Lab-Specific Scripts:** Code that fulfills a specific assignment requirement (e.g., the VLAN conversion script from Lab 3 Task 1 or the iperf3 telemetry script from Lab 5 Task 8).
This distinction helps students understand the difference between building *tools* and performing *operational tasks*.