# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: Access-Policy-Helfer — ed25519-Keys, Passwort-Sperre
#   tags:
#     - access
#     - ssh
# ---
{ lib }:
let
  forbiddenUserNames = [
    "nixos"
    "moritz"
    "admin"
  ];
in
{
  inherit forbiddenUserNames;

  isEd25519Key = key: lib.hasPrefix "ssh-ed25519 " key;

  isPasswordLocked =
    user:
    let
      hp = user.hashedPassword or null;
    in
    hp == null || hp == "!" || hp == "";

  sshUsers =
    users:
    lib.filterAttrs (
      _name: u: (u.isNormalUser or false) && ((u.openssh.authorizedKeys.keys or [ ]) != [ ])
    ) users;

  assertAllKeysEd25519 = keys: label: lib.all (lib.hasPrefix "ssh-ed25519 ") keys;

  policyHelp =
    topic:
    {
      "no-password" =
        "POLICY: Kein Passwort-Login im System. Nur SSH-Keys (ed25519) + root-tty-Autologin. Siehe modules/20-security/2030-access-policy.nix und docs/SECURITY.md.";
      "single-ssh-user" =
        "POLICY: Genau ein SSH-User (my.configs.identity.user). Kein nixos/moritz/admin Schatten-Account. Break-Glass = root an physischer tty1.";
      "root-no-ssh" =
        "POLICY: root darf NIEMALS per SSH — nur tty1-Autologin am Gerät. Entferne root.openssh.authorizedKeys und stelle PermitRootLogin=no sicher.";
      "ed25519-only" =
        "POLICY: Nur ssh-ed25519 in authorizedKeys. RSA/ECDSA/ecdsa-sk sind verboten (schwach oder unsicher).";
      "sshd-alive" = "POLICY: sshd.service Restart=always — SSH darf nicht dauerhaft tot bleiben.";
    }
    .${topic} or "";
}
