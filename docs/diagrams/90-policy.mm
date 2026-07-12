flowchart TD
    n3a2vdn5i7vd2wl654xs8nb52jf1v6cbh_flake_nix["`**flake.nix**

_3a2vdn5i7vd2wl654xs8nb52jf1v6cbh_`"]
    nakgzg1754267l9kxqjl52wpc2dnh6pr8_machines_q958_default_nix["`**machines/q958/default.nix**

_akgzg1754267l9kxqjl52wpc2dnh6pr8_`"]
    nakgzg1754267l9kxqjl52wpc2dnh6pr8_machines_q958_hardware_nix["`**machines/q958/hardware.nix**

_akgzg1754267l9kxqjl52wpc2dnh6pr8_`"]
    nakgzg1754267l9kxqjl52wpc2dnh6pr8_modules_90_policy["`**modules/90-policy**

_akgzg1754267l9kxqjl52wpc2dnh6pr8_`"]
    nakgzg1754267l9kxqjl52wpc2dnh6pr8_modules_90_policy_05_forbidden_tech_nix["`**modules/90-policy/05-forbidden-tech.nix**

_akgzg1754267l9kxqjl52wpc2dnh6pr8_`"]
    nakgzg1754267l9kxqjl52wpc2dnh6pr8_modules_90_policy_90_policy_nix["`**modules/90-policy/90-policy.nix**

_akgzg1754267l9kxqjl52wpc2dnh6pr8_`"]
    nakgzg1754267l9kxqjl52wpc2dnh6pr8_modules_90_policy_91_security_assertions_nix["`**modules/90-policy/91-security-assertions.nix**

_akgzg1754267l9kxqjl52wpc2dnh6pr8_`"]
    nakgzg1754267l9kxqjl52wpc2dnh6pr8_modules_90_policy_92_on_demand_nix["`**modules/90-policy/92-on-demand.nix**

_akgzg1754267l9kxqjl52wpc2dnh6pr8_`"]
    nakgzg1754267l9kxqjl52wpc2dnh6pr8_modules_90_policy_93_memory_pressure_nix["`**modules/90-policy/93-memory-pressure.nix**

_akgzg1754267l9kxqjl52wpc2dnh6pr8_`"]
    n3a2vdn5i7vd2wl654xs8nb52jf1v6cbh_flake_nix --> nakgzg1754267l9kxqjl52wpc2dnh6pr8_machines_q958_default_nix
    nakgzg1754267l9kxqjl52wpc2dnh6pr8_machines_q958_default_nix --> nakgzg1754267l9kxqjl52wpc2dnh6pr8_machines_q958_hardware_nix
    nakgzg1754267l9kxqjl52wpc2dnh6pr8_machines_q958_default_nix --> nakgzg1754267l9kxqjl52wpc2dnh6pr8_modules_90_policy
    nakgzg1754267l9kxqjl52wpc2dnh6pr8_modules_90_policy --> nakgzg1754267l9kxqjl52wpc2dnh6pr8_modules_90_policy_05_forbidden_tech_nix
    nakgzg1754267l9kxqjl52wpc2dnh6pr8_modules_90_policy --> nakgzg1754267l9kxqjl52wpc2dnh6pr8_modules_90_policy_90_policy_nix
    nakgzg1754267l9kxqjl52wpc2dnh6pr8_modules_90_policy --> nakgzg1754267l9kxqjl52wpc2dnh6pr8_modules_90_policy_91_security_assertions_nix
    nakgzg1754267l9kxqjl52wpc2dnh6pr8_modules_90_policy --> nakgzg1754267l9kxqjl52wpc2dnh6pr8_modules_90_policy_92_on_demand_nix
    nakgzg1754267l9kxqjl52wpc2dnh6pr8_modules_90_policy --> nakgzg1754267l9kxqjl52wpc2dnh6pr8_modules_90_policy_93_memory_pressure_nix
    style n3a2vdn5i7vd2wl654xs8nb52jf1v6cbh_flake_nix fill:#e5b2d8,color:#000000
    style nakgzg1754267l9kxqjl52wpc2dnh6pr8_machines_q958_default_nix fill:#e5b2b7,color:#000000
    style nakgzg1754267l9kxqjl52wpc2dnh6pr8_machines_q958_hardware_nix fill:#e5b2b7,color:#000000
    style nakgzg1754267l9kxqjl52wpc2dnh6pr8_modules_90_policy fill:#e5b2b7,color:#000000
    style nakgzg1754267l9kxqjl52wpc2dnh6pr8_modules_90_policy_05_forbidden_tech_nix fill:#e5b2b7,color:#000000
    style nakgzg1754267l9kxqjl52wpc2dnh6pr8_modules_90_policy_90_policy_nix fill:#e5b2b7,color:#000000
    style nakgzg1754267l9kxqjl52wpc2dnh6pr8_modules_90_policy_91_security_assertions_nix fill:#e5b2b7,color:#000000
    style nakgzg1754267l9kxqjl52wpc2dnh6pr8_modules_90_policy_92_on_demand_nix fill:#e5b2b7,color:#000000
    style nakgzg1754267l9kxqjl52wpc2dnh6pr8_modules_90_policy_93_memory_pressure_nix fill:#e5b2b7,color:#000000
