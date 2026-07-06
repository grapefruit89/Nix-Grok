# ---
# meta:
#   role: package
#   purpose: secrets-portal — Web-UI für systemd-creds Provisioning und Rotation
#   tags:
#     - secrets
#     - security
#     - admin
# ---
{
  lib,
  buildGoModule,
}:

buildGoModule {
  pname = "secrets-portal";
  version = "1.0.0";

  src = ./.;

  # stdlib only — kein vendor directory
  vendorHash = null;

  meta = with lib; {
    description = "Web-UI für systemd-creds Provisioning und Rotation (admin-hangar LAN-only)";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "secrets-portal";
  };
}
