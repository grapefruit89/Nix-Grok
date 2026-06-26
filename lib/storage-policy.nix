# ---
# meta:
#   id: NIXH-05-LIB-007
#   layer: 5
#   role: lib
#   purpose: Tier-C-Exclusion — Build-time Scan systemd.services gegen HDD-Pfade
#   docs:
#     - docs/SPEC_REGISTRY.md
#     - AGENTS.md
#   tags:
#     - storage
#     - tier-c
#     - policy
# ---
{ lib }:

let
  pathStringsFromService =
    svc:
    lib.flatten [
      (svc.serviceConfig.ReadWritePaths or [ ])
      (svc.serviceConfig.BindPaths or [ ])
      (svc.serviceConfig.BindReadOnlyPaths or [ ])
      (lib.optional (svc.serviceConfig.ExecStart or null != null) (toString svc.serviceConfig.ExecStart))
      (map toString (svc.serviceConfig.ExecStartPre or [ ]))
      (map toString (svc.serviceConfig.ExecStartPost or [ ]))
      (map toString (svc.serviceConfig.EnvironmentFile or [ ]))
    ];

  usesTierC =
    markers: pathList:
    lib.any (
      path:
      let
        s = toString path;
      in
      lib.any (m: lib.strings.hasInfix m s) markers
    ) pathList;

  unauthorizedTierCServices =
    {
      exemptions,
      markers,
      systemdServices,
    }:
    lib.filterAttrs (
      name: svc:
      let
        paths = pathStringsFromService svc;
      in
      !(lib.elem name exemptions) && usesTierC markers paths
    ) systemdServices;

  mkTierCAssertion =
    {
      exemptions,
      markers,
      systemdServices,
    }:
    let
      offenders = unauthorizedTierCServices {
        inherit exemptions markers systemdServices;
      };
      names = lib.attrNames offenders;
    in
    {
      assertion = offenders == { };
      message =
        "[TIER-C] Unautorisierte HDD-Zugriffe (Tier C): ${lib.concatStringsSep ", " names}. "
        + "Nur Exemptions dürfen ${lib.concatStringsSep ", " markers} berühren — App-State gehört auf Tier A/B.";
    };

  defaultTierCMarkers =
    {
      mountPoint,
      automountParent ? "/mnt/tier-c",
      labels ? [ ],
      legacyPrefixes ? [ ],
    }:
    [
      mountPoint
      automountParent
    ]
    ++ (map (l: "/mnt/tier-c/${l}") labels)
    ++ (map (l: "by-label/${l}") labels)
    ++ legacyPrefixes;

in
{
  inherit
    usesTierC
    unauthorizedTierCServices
    mkTierCAssertion
    defaultTierCMarkers
    pathStringsFromService
    ;
}
