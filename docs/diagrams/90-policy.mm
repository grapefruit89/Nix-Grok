flowchart TD
    n3a2vdn5i7vd2wl654xs8nb52jf1v6cbh_flake_nix["`**flake.nix**

_3a2vdn5i7vd2wl654xs8nb52jf1v6cbh_`"]
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_machines_q958_default_nix["`**machines/q958/default.nix**

_5g5h9x7p4g7fns71c0a5gv238ra1q202_`"]
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_machines_q958_hardware_nix["`**machines/q958/hardware.nix**

_5g5h9x7p4g7fns71c0a5gv238ra1q202_`"]
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_90_policy["`**modules/90-policy**

_5g5h9x7p4g7fns71c0a5gv238ra1q202_`"]
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_90_policy_05_forbidden_tech_nix["`**modules/90-policy/05-forbidden-tech.nix**

_5g5h9x7p4g7fns71c0a5gv238ra1q202_`"]
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_90_policy_90_policy_nix["`**modules/90-policy/90-policy.nix**

_5g5h9x7p4g7fns71c0a5gv238ra1q202_`"]
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_90_policy_91_security_assertions_nix["`**modules/90-policy/91-security-assertions.nix**

_5g5h9x7p4g7fns71c0a5gv238ra1q202_`"]
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_90_policy_92_on_demand_nix["`**modules/90-policy/92-on-demand.nix**

_5g5h9x7p4g7fns71c0a5gv238ra1q202_`"]
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_90_policy_93_memory_pressure_nix["`**modules/90-policy/93-memory-pressure.nix**

_5g5h9x7p4g7fns71c0a5gv238ra1q202_`"]
    n3a2vdn5i7vd2wl654xs8nb52jf1v6cbh_flake_nix --> n5g5h9x7p4g7fns71c0a5gv238ra1q202_machines_q958_default_nix
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_machines_q958_default_nix --> n5g5h9x7p4g7fns71c0a5gv238ra1q202_machines_q958_hardware_nix
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_machines_q958_default_nix --> n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_90_policy
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_90_policy --> n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_90_policy_05_forbidden_tech_nix
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_90_policy --> n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_90_policy_90_policy_nix
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_90_policy --> n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_90_policy_91_security_assertions_nix
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_90_policy --> n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_90_policy_92_on_demand_nix
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_90_policy --> n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_90_policy_93_memory_pressure_nix
    style n3a2vdn5i7vd2wl654xs8nb52jf1v6cbh_flake_nix fill:#b8e5b2,color:#000000
    style n5g5h9x7p4g7fns71c0a5gv238ra1q202_machines_q958_default_nix fill:#e5b2e1,color:#000000
    style n5g5h9x7p4g7fns71c0a5gv238ra1q202_machines_q958_hardware_nix fill:#e5b2e1,color:#000000
    style n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_90_policy fill:#e5b2e1,color:#000000
    style n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_90_policy_05_forbidden_tech_nix fill:#e5b2e1,color:#000000
    style n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_90_policy_90_policy_nix fill:#e5b2e1,color:#000000
    style n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_90_policy_91_security_assertions_nix fill:#e5b2e1,color:#000000
    style n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_90_policy_92_on_demand_nix fill:#e5b2e1,color:#000000
    style n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_90_policy_93_memory_pressure_nix fill:#e5b2e1,color:#000000
