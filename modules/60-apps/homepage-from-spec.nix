# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Homepage-Dienste aus my.services.spec generieren
#   services:
#     - homepage-dashboard
#   tags:
#     - apps
#     - homepage
# ---
{
  config,
  lib,
  ...
}:
let
  cfgHomepage = config.my.services.homepage;
  domain = config.my.configs.identity.domain;
  spec = config.my.services.spec;

  withHomepage = lib.filterAttrs (_: e: e.homepage != null) spec;
  specByGroup = lib.groupBy (e: e.homepage.group) (lib.attrValues withHomepage);

  mkSpecEntry =
    entry:
    {
      ${entry.homepage.name} = {
        href = "https://${entry.subdomain}.${domain}";
        description = entry.homepage.description;
      } // lib.optionalAttrs (entry.homepage.icon != "") { icon = entry.homepage.icon; };
    };

  extraEntries = {
    "Medien & Player" = [
      {
        ReadMeABook = {
          href = "https://audiobooks.${domain}";
          description = "Hörbuch-Wünsche";
          icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/read-me-a-book.png";
        };
      }
    ];
    "Tools" = [
      {
        BentoPDF = {
          href = "https://bentopdf.${domain}";
          description = "PDF Tools";
          icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/stirling-pdf.svg";
        };
      }
    ];
    "System" = [
      {
        Unraid = {
          href = "https://unraid.${domain}";
          description = "Server-Verwaltung";
          icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/unraid.svg";
        };
      }
      {
        Traefik = {
          href = "https://traefik.${domain}";
          description = "Reverse Proxy";
          icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/traefik.svg";
        };
      }
      {
        Speedtest = {
          href = "https://speedtest.${domain}";
          description = "Netzwerk-Test";
          icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/speedtest-tracker.svg";
        };
      }
    ];
    "KI & Agenten" =
      lib.optional (cfgHomepage.agentZeroUrl != "") {
        "Agent Zero" = {
          href = cfgHomepage.agentZeroUrl;
          description = "KI-Agent";
          icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/agent-zero.svg";
        };
      }
      ++ [
        {
          OpenClaw = {
            href = "https://openclaw.${domain}";
            description = "Research Tool";
            icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/openai.svg";
          };
        }
      ];
  };

  groupOrder = [
    "Medien & Player"
    "Downloads & Arrs"
    "Tools"
    "System"
    "KI & Agenten"
  ];

  groups = map (
    group:
    {
      ${group} = (map mkSpecEntry (specByGroup.${group} or [])) ++ (extraEntries.${group} or []);
    }
  ) groupOrder;
in
{
  config = lib.mkIf cfgHomepage.enable {
    services.homepage-dashboard.services = lib.mkForce groups;
  };
}
