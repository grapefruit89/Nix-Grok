flowchart TD
    n3a2vdn5i7vd2wl654xs8nb52jf1v6cbh_flake_nix["`**flake.nix**

_3a2vdn5i7vd2wl654xs8nb52jf1v6cbh_`"]
    nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_machines_q958_default_nix["`**machines/q958/default.nix**

_azmn0gjl1bi0r9m7llpwk3d2mdppnj4w_`"]
    nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_machines_q958_hardware_nix["`**machines/q958/hardware.nix**

_azmn0gjl1bi0r9m7llpwk3d2mdppnj4w_`"]
    nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_modules_90_policy["`**modules/90-policy**

_azmn0gjl1bi0r9m7llpwk3d2mdppnj4w_`"]
    nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_modules_90_policy_05_forbidden_tech_nix["`**modules/90-policy/05-forbidden-tech.nix**

_azmn0gjl1bi0r9m7llpwk3d2mdppnj4w_`"]
    nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_modules_90_policy_90_policy_nix["`**modules/90-policy/90-policy.nix**

_azmn0gjl1bi0r9m7llpwk3d2mdppnj4w_`"]
    nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_modules_90_policy_91_security_assertions_nix["`**modules/90-policy/91-security-assertions.nix**

_azmn0gjl1bi0r9m7llpwk3d2mdppnj4w_`"]
    nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_modules_90_policy_92_on_demand_nix["`**modules/90-policy/92-on-demand.nix**

_azmn0gjl1bi0r9m7llpwk3d2mdppnj4w_`"]
    nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_modules_90_policy_93_memory_pressure_nix["`**modules/90-policy/93-memory-pressure.nix**

_azmn0gjl1bi0r9m7llpwk3d2mdppnj4w_`"]
    n3a2vdn5i7vd2wl654xs8nb52jf1v6cbh_flake_nix --> nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_machines_q958_default_nix
    nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_machines_q958_default_nix --> nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_machines_q958_hardware_nix
    nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_machines_q958_default_nix --> nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_modules_90_policy
    nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_modules_90_policy --> nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_modules_90_policy_05_forbidden_tech_nix
    nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_modules_90_policy --> nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_modules_90_policy_90_policy_nix
    nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_modules_90_policy --> nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_modules_90_policy_91_security_assertions_nix
    nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_modules_90_policy --> nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_modules_90_policy_92_on_demand_nix
    nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_modules_90_policy --> nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_modules_90_policy_93_memory_pressure_nix
    style n3a2vdn5i7vd2wl654xs8nb52jf1v6cbh_flake_nix fill:#e5b2b9,color:#000000
    style nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_machines_q958_default_nix fill:#e5e5b2,color:#000000
    style nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_machines_q958_hardware_nix fill:#e5e5b2,color:#000000
    style nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_modules_90_policy fill:#e5e5b2,color:#000000
    style nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_modules_90_policy_05_forbidden_tech_nix fill:#e5e5b2,color:#000000
    style nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_modules_90_policy_90_policy_nix fill:#e5e5b2,color:#000000
    style nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_modules_90_policy_91_security_assertions_nix fill:#e5e5b2,color:#000000
    style nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_modules_90_policy_92_on_demand_nix fill:#e5e5b2,color:#000000
    style nazmn0gjl1bi0r9m7llpwk3d2mdppnj4w_modules_90_policy_93_memory_pressure_nix fill:#e5e5b2,color:#000000
