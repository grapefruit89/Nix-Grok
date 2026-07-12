flowchart TD
    n3a2vdn5i7vd2wl654xs8nb52jf1v6cbh_flake_nix["`**flake.nix**

_3a2vdn5i7vd2wl654xs8nb52jf1v6cbh_`"]
    nmwlc1l5s6fl46yblldfdm612dyl2frqa_machines_q958_default_nix["`**machines/q958/default.nix**

_mwlc1l5s6fl46yblldfdm612dyl2frqa_`"]
    nmwlc1l5s6fl46yblldfdm612dyl2frqa_machines_q958_hardware_nix["`**machines/q958/hardware.nix**

_mwlc1l5s6fl46yblldfdm612dyl2frqa_`"]
    n3a2vdn5i7vd2wl654xs8nb52jf1v6cbh_flake_nix --> nmwlc1l5s6fl46yblldfdm612dyl2frqa_machines_q958_default_nix
    nmwlc1l5s6fl46yblldfdm612dyl2frqa_machines_q958_default_nix --> nmwlc1l5s6fl46yblldfdm612dyl2frqa_machines_q958_hardware_nix
    style n3a2vdn5i7vd2wl654xs8nb52jf1v6cbh_flake_nix fill:#b2d9e5,color:#000000
    style nmwlc1l5s6fl46yblldfdm612dyl2frqa_machines_q958_default_nix fill:#e5b2e2,color:#000000
    style nmwlc1l5s6fl46yblldfdm612dyl2frqa_machines_q958_hardware_nix fill:#e5b2e2,color:#000000
