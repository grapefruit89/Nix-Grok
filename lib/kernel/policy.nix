# Zwiebelschale: global → homelab → host
{ lib }:

let
  globalBlacklist = import ./blacklist-global.nix;
  exoticFilesystems = import ./blacklist-filesystems.nix;
  homelabHeadless = import ./blacklist-homelab-headless.nix;
  homelabWhitelist = import ./whitelist-homelab.nix;

  flatten = attrs: lib.unique (lib.concatLists (lib.attrValues attrs));
  flattenLists = lists: lib.unique (lib.concatLists lists);

  homelabProfileBlacklist = profile:
    if profile == "headless-server" then flatten homelabHeadless
    else if profile == "desktop" then [ ]
    else [ ];

  homelabWhitelistAll = flatten homelabWhitelist;

  modes = [
    "blank"
    "global-only"
    "homelab-strict"
    "homelab-relaxed"
  ];

  homelabProfiles = [
    "none"
    "headless-server"
    "desktop"
  ];
in
{
  inherit modes homelabProfiles homelabWhitelistAll;

  compute =
    { mode ? "homelab-strict"
    , homelabProfile ? "headless-server"
    , requiredModules ? [ ]
    , requiredInitrdModules ? [ ]
    , hostBlacklist ? [ ]
    , whitelistExtra ? [ ]
    , moduleRoles ? { }
    , hostLabel ? "host"
    ,
    }:
    let
      allowedModules = lib.unique (homelabWhitelistAll ++ whitelistExtra);

      globalLayer =
        flatten globalBlacklist
        ++ exoticFilesystems;

      homelabLayer =
        if mode == "homelab-strict" || mode == "homelab-relaxed" then
          homelabProfileBlacklist homelabProfile
        else
          [ ];

      hostLayer = hostBlacklist;

      rawBlacklist =
        if mode == "blank" then
          [ ]
        else if mode == "global-only" then
          globalLayer
        else
          lib.unique (globalLayer ++ homelabLayer ++ hostLayer);

      safeBlacklist = lib.filter (m: !(lib.elem m requiredModules)) rawBlacklist;

      whitelistAssertions =
        if mode == "blank" || mode == "global-only" || homelabProfile == "none" then
          [ ]
        else
          map
            (m: {
              assertion = lib.elem m allowedModules;
              message =
                "KERNEL-POLICY: Pflichtmodul '${m}' ist weder in der Homelab-Whitelist noch in kernel.whitelistExtra — Profil oder whitelistExtra anpassen.";
            })
            requiredModules;

      roleOf = m: moduleRoles.${m} or "Pflicht-Hardware (${hostLabel})";

      blacklistAssertions =
        map
          (m: {
            assertion = !(lib.elem m safeBlacklist);
            message =
              "${hostLabel} KERNEL: Modul '${m}' (${roleOf m}) darf nicht geblacklistet werden — effektive Blacklist enthält es.";
          })
          (requiredModules ++ requiredInitrdModules);

      hostBlacklistAssertions = map
        (m: {
          assertion = !(lib.elem m hostBlacklist);
          message =
            "${hostLabel} KERNEL: Modul '${m}' (${roleOf m}) steht in kernel.blacklist — für diese Hardware verboten.";
        })
        requiredModules;

      explicitFilesystemAssertions = [
        {
          assertion = !(lib.elem "vfat" safeBlacklist);
          message = "CRITICAL: 'vfat' (FAT32) darf niemals geblacklistet werden! Das Mainboard (UEFI) benötigt es zwingend für /boot.";
        }
        {
          assertion = !(lib.elem "ntfs3" safeBlacklist);
          message = "POLICY: 'ntfs3' (und exfat) auf Whitelist, damit Windows-USB-Sticks weiterhin erkannt werden.";
        }
        {
          assertion = lib.elem "btrfs" safeBlacklist;
          message = "POLICY-REJECTION: 'btrfs' ist strengstens verboten. Grund: Verursacht Fragmentierung bei Datenbanken und RAID5/6 ist instabil. Wir nutzen ext4 + MergerFS.";
        }
        {
          assertion = lib.elem "zfs" safeBlacklist;
          message = "POLICY-REJECTION: 'zfs' ist verboten. Grund: Overkill für Heimanwender, extrem RAM-hungrig, unflexibel beim Erweitern.";
        }
      ];
    in
    {
      inherit safeBlacklist allowedModules rawBlacklist;
      assertions = blacklistAssertions ++ whitelistAssertions ++ hostBlacklistAssertions ++ explicitFilesystemAssertions;
    };
}
