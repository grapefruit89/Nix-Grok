flowchart TD
    n3a2vdn5i7vd2wl654xs8nb52jf1v6cbh_flake_nix["`**flake.nix**

_3a2vdn5i7vd2wl654xs8nb52jf1v6cbh_`"]
    nmwlc1l5s6fl46yblldfdm612dyl2frqa_machines_q958_default_nix["`**machines/q958/default.nix**

_mwlc1l5s6fl46yblldfdm612dyl2frqa_`"]
    nmwlc1l5s6fl46yblldfdm612dyl2frqa_machines_q958_hardware_nix["`**machines/q958/hardware.nix**

_mwlc1l5s6fl46yblldfdm612dyl2frqa_`"]
    nmwlc1l5s6fl46yblldfdm612dyl2frqa_modules_90_policy["`**modules/90-policy**

_mwlc1l5s6fl46yblldfdm612dyl2frqa_`"]
    nmwlc1l5s6fl46yblldfdm612dyl2frqa_modules_90_policy_05_forbidden_tech_nix["`**modules/90-policy/05-forbidden-tech.nix**

_mwlc1l5s6fl46yblldfdm612dyl2frqa_`"]
    nmwlc1l5s6fl46yblldfdm612dyl2frqa_modules_90_policy_90_policy_nix["`**modules/90-policy/90-policy.nix**

_mwlc1l5s6fl46yblldfdm612dyl2frqa_`"]
    nmwlc1l5s6fl46yblldfdm612dyl2frqa_modules_90_policy_91_security_assertions_nix["`**modules/90-policy/91-security-assertions.nix**

_mwlc1l5s6fl46yblldfdm612dyl2frqa_`"]
    nmwlc1l5s6fl46yblldfdm612dyl2frqa_modules_90_policy_92_on_demand_nix["`**modules/90-policy/92-on-demand.nix**

_mwlc1l5s6fl46yblldfdm612dyl2frqa_`"]
    nmwlc1l5s6fl46yblldfdm612dyl2frqa_modules_90_policy_93_memory_pressure_nix["`**modules/90-policy/93-memory-pressure.nix**

_mwlc1l5s6fl46yblldfdm612dyl2frqa_`"]
    n3a2vdn5i7vd2wl654xs8nb52jf1v6cbh_flake_nix --> nmwlc1l5s6fl46yblldfdm612dyl2frqa_machines_q958_default_nix
    nmwlc1l5s6fl46yblldfdm612dyl2frqa_machines_q958_default_nix --> nmwlc1l5s6fl46yblldfdm612dyl2frqa_machines_q958_hardware_nix
    nmwlc1l5s6fl46yblldfdm612dyl2frqa_machines_q958_default_nix --> nmwlc1l5s6fl46yblldfdm612dyl2frqa_modules_90_policy
    nmwlc1l5s6fl46yblldfdm612dyl2frqa_modules_90_policy --> nmwlc1l5s6fl46yblldfdm612dyl2frqa_modules_90_policy_05_forbidden_tech_nix
    nmwlc1l5s6fl46yblldfdm612dyl2frqa_modules_90_policy --> nmwlc1l5s6fl46yblldfdm612dyl2frqa_modules_90_policy_90_policy_nix
    nmwlc1l5s6fl46yblldfdm612dyl2frqa_modules_90_policy --> nmwlc1l5s6fl46yblldfdm612dyl2frqa_modules_90_policy_91_security_assertions_nix
    nmwlc1l5s6fl46yblldfdm612dyl2frqa_modules_90_policy --> nmwlc1l5s6fl46yblldfdm612dyl2frqa_modules_90_policy_92_on_demand_nix
    nmwlc1l5s6fl46yblldfdm612dyl2frqa_modules_90_policy --> nmwlc1l5s6fl46yblldfdm612dyl2frqa_modules_90_policy_93_memory_pressure_nix
    style n3a2vdn5i7vd2wl654xs8nb52jf1v6cbh_flake_nix fill:#b2c0e5,color:#000000
    style nmwlc1l5s6fl46yblldfdm612dyl2frqa_machines_q958_default_nix fill:#d8e5b2,color:#000000
    style nmwlc1l5s6fl46yblldfdm612dyl2frqa_machines_q958_hardware_nix fill:#d8e5b2,color:#000000
    style nmwlc1l5s6fl46yblldfdm612dyl2frqa_modules_90_policy fill:#d8e5b2,color:#000000
    style nmwlc1l5s6fl46yblldfdm612dyl2frqa_modules_90_policy_05_forbidden_tech_nix fill:#d8e5b2,color:#000000
    style nmwlc1l5s6fl46yblldfdm612dyl2frqa_modules_90_policy_90_policy_nix fill:#d8e5b2,color:#000000
    style nmwlc1l5s6fl46yblldfdm612dyl2frqa_modules_90_policy_91_security_assertions_nix fill:#d8e5b2,color:#000000
    style nmwlc1l5s6fl46yblldfdm612dyl2frqa_modules_90_policy_92_on_demand_nix fill:#d8e5b2,color:#000000
    style nmwlc1l5s6fl46yblldfdm612dyl2frqa_modules_90_policy_93_memory_pressure_nix fill:#d8e5b2,color:#000000
