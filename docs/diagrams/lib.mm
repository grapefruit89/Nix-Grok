flowchart TD
    n3a2vdn5i7vd2wl654xs8nb52jf1v6cbh_flake_nix["`**flake.nix**

_3a2vdn5i7vd2wl654xs8nb52jf1v6cbh_`"]
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_machines_q958_default_nix["`**machines/q958/default.nix**

_5g5h9x7p4g7fns71c0a5gv238ra1q202_`"]
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_machines_q958_hardware_nix["`**machines/q958/hardware.nix**

_5g5h9x7p4g7fns71c0a5gv238ra1q202_`"]
    n3a2vdn5i7vd2wl654xs8nb52jf1v6cbh_flake_nix --> n5g5h9x7p4g7fns71c0a5gv238ra1q202_machines_q958_default_nix
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_machines_q958_default_nix --> n5g5h9x7p4g7fns71c0a5gv238ra1q202_machines_q958_hardware_nix
    style n3a2vdn5i7vd2wl654xs8nb52jf1v6cbh_flake_nix fill:#e5b2ba,color:#000000
    style n5g5h9x7p4g7fns71c0a5gv238ra1q202_machines_q958_default_nix fill:#b2dae5,color:#000000
    style n5g5h9x7p4g7fns71c0a5gv238ra1q202_machines_q958_hardware_nix fill:#b2dae5,color:#000000
