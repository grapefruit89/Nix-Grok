flowchart TD
    n3a2vdn5i7vd2wl654xs8nb52jf1v6cbh_flake_nix["`**flake.nix**

_3a2vdn5i7vd2wl654xs8nb52jf1v6cbh_`"]
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_machines_q958_default_nix["`**machines/q958/default.nix**

_5g5h9x7p4g7fns71c0a5gv238ra1q202_`"]
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_machines_q958_hardware_nix["`**machines/q958/hardware.nix**

_5g5h9x7p4g7fns71c0a5gv238ra1q202_`"]
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps["`**modules/60-apps**

_5g5h9x7p4g7fns71c0a5gv238ra1q202_`"]
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps_grok_nix["`**modules/60-apps/grok.nix**

_5g5h9x7p4g7fns71c0a5gv238ra1q202_`"]
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps_61_core_nix["`**modules/60-apps/61-core.nix**

_5g5h9x7p4g7fns71c0a5gv238ra1q202_`"]
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps_61_homepage_nix["`**modules/60-apps/61-homepage.nix**

_5g5h9x7p4g7fns71c0a5gv238ra1q202_`"]
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps_62_libreseerr_nix["`**modules/60-apps/62-libreseerr.nix**

_5g5h9x7p4g7fns71c0a5gv238ra1q202_`"]
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps_63_on_demand_apps_nix["`**modules/60-apps/63-on-demand-apps.nix**

_5g5h9x7p4g7fns71c0a5gv238ra1q202_`"]
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps_automation_nix["`**modules/60-apps/automation.nix**

_5g5h9x7p4g7fns71c0a5gv238ra1q202_`"]
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps_hermes_nix["`**modules/60-apps/hermes.nix**

_5g5h9x7p4g7fns71c0a5gv238ra1q202_`"]
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps_gaming_nix["`**modules/60-apps/gaming.nix**

_5g5h9x7p4g7fns71c0a5gv238ra1q202_`"]
    n3a2vdn5i7vd2wl654xs8nb52jf1v6cbh_flake_nix --> n5g5h9x7p4g7fns71c0a5gv238ra1q202_machines_q958_default_nix
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_machines_q958_default_nix --> n5g5h9x7p4g7fns71c0a5gv238ra1q202_machines_q958_hardware_nix
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_machines_q958_default_nix --> n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps --> n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps_grok_nix
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps --> n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps_61_core_nix
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps --> n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps_61_homepage_nix
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps --> n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps_62_libreseerr_nix
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps --> n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps_63_on_demand_apps_nix
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps --> n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps_automation_nix
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps --> n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps_hermes_nix
    n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps --> n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps_gaming_nix
    style n3a2vdn5i7vd2wl654xs8nb52jf1v6cbh_flake_nix fill:#e2b2e5,color:#000000
    style n5g5h9x7p4g7fns71c0a5gv238ra1q202_machines_q958_default_nix fill:#d3e5b2,color:#000000
    style n5g5h9x7p4g7fns71c0a5gv238ra1q202_machines_q958_hardware_nix fill:#d3e5b2,color:#000000
    style n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps fill:#d3e5b2,color:#000000
    style n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps_grok_nix fill:#d3e5b2,color:#000000
    style n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps_61_core_nix fill:#d3e5b2,color:#000000
    style n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps_61_homepage_nix fill:#d3e5b2,color:#000000
    style n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps_62_libreseerr_nix fill:#d3e5b2,color:#000000
    style n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps_63_on_demand_apps_nix fill:#d3e5b2,color:#000000
    style n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps_automation_nix fill:#d3e5b2,color:#000000
    style n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps_hermes_nix fill:#d3e5b2,color:#000000
    style n5g5h9x7p4g7fns71c0a5gv238ra1q202_modules_60_apps_gaming_nix fill:#d3e5b2,color:#000000
