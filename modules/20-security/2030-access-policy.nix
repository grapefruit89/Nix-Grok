# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Access-Policy — Assertions (Key-only, ein SSH-User, root-tty-only)
#   tags:
#     - access
#     - ssh
#     - policy
# ---
{
  config,
  lib,
  ...
}:
let
  policy = import ../../lib/access-policy.nix { inherit lib; };
  user = config.my.configs.identity.user;
  sshSettings = config.services.openssh.settings or { };
  permitRoot =
    if sshSettings.PermitRootLogin == false then
      "no"
    else
      toString (sshSettings.PermitRootLogin or "no");
  sshUserNames = builtins.attrNames (policy.sshUsers config.users.users);
  help = policy.policyHelp;
in
{
  assertions = [
    {
      assertion = !(config.users.users ? nixos);
      message = ''
        ACCESS-POLICY VERLETZT: User "nixos" existiert noch.
        ${help "single-ssh-user"}
        Fix: entferne users.users.nixos aus der Config (access.nix hatte den Break-Glass-User — root-tty reicht).
      '';
    }
    {
      assertion = !(config.users.users ? moritz);
      message = ''
        ACCESS-POLICY VERLETZT: User "moritz" existiert noch.
        ${help "single-ssh-user"}
        Fix: nur users/jarvis/ — nach Migration: sudo usermod -l jarvis -d /home/jarvis -m moritz (einmalig).
      '';
    }
    {
      assertion = !(config.users.users ? admin);
      message = ''
        ACCESS-POLICY VERLETZT: User "admin" existiert noch.
        ${help "single-ssh-user"}
        Fix: Personen-SSoT nur users/jarvis/profile.nix — users/admin/ entfernen.
      '';
    }
    {
      assertion = builtins.length sshUserNames == 1;
      message = ''
        ACCESS-POLICY VERLETZT: ${toString (builtins.length sshUserNames)} SSH-User mit authorized_keys (${lib.concatStringsSep ", " sshUserNames}), erwartet: genau 1.
        ${help "single-ssh-user"}
        Fix: alle authorizedKeys außer my.configs.identity.user entfernen.
      '';
    }
    {
      assertion = builtins.length sshUserNames == 0 || (builtins.elem user sshUserNames);
      message = ''
        ACCESS-POLICY VERLETZT: SSH-User "${lib.concatStringsSep ", " sshUserNames}" ≠ identity.user "${user}".
        ${help "single-ssh-user"}
        Fix: my.configs.identity.user und users/${user}/profile.nix synchron halten.
      '';
    }
    {
      assertion = (config.users.users.root.openssh.authorizedKeys.keys or [ ]) == [ ];
      message = ''
        ACCESS-POLICY VERLETZT: root hat SSH authorized_keys.
        ${help "root-no-ssh"}
        Fix: users.users.root.openssh.authorizedKeys.keys = []; entferne Key-Kopie in 2020-security.nix.
      '';
    }
    {
      assertion = permitRoot == "no";
      message = ''
        ACCESS-POLICY VERLETZT: PermitRootLogin="${permitRoot}" — muss "no" sein.
        ${help "root-no-ssh"}
        Fix: services.openssh.settings.PermitRootLogin = lib.mkForce "no";
      '';
    }
    {
      assertion = !(sshSettings.PasswordAuthentication or false);
      message = ''
        ACCESS-POLICY VERLETZT: PasswordAuthentication ist aktiv.
        ${help "no-password"}
        Fix: services.openssh.settings.PasswordAuthentication = lib.mkForce false;
      '';
    }
    {
      assertion = !(sshSettings.KbdInteractiveAuthentication or false);
      message = ''
        ACCESS-POLICY VERLETZT: KbdInteractiveAuthentication ist aktiv.
        ${help "no-password"}
        Fix: services.openssh.settings.KbdInteractiveAuthentication = lib.mkForce false;
      '';
    }
    {
      assertion = (config.users.users.${user}.openssh.authorizedKeys.keys or [ ]) != [ ];
      message = ''
        ACCESS-POLICY VERLETZT: identity.user "${user}" hat keine SSH authorized_keys.
        ${help "single-ssh-user"}
        Fix: mindestens ein ssh-ed25519 Key in users/${user}/profile.nix eintragen.
      '';
    }
    {
      assertion = policy.assertAllKeysEd25519 (config.users.users.${user}.openssh.authorizedKeys.keys
        or [ ]
      ) user;
      message = ''
        ACCESS-POLICY VERLETZT: authorized_keys für "${user}" enthalten Nicht-ed25519-Keys.
        ${help "ed25519-only"}
        Fix: nur "ssh-ed25519 AAAA..." in users/${user}/profile.nix — RSA/ECDSA entfernen.
      '';
    }
    {
      assertion = (config.services.getty.autologinUser or "") == "root";
      message = ''
        ACCESS-POLICY VERLETZT: getty.autologinUser="${
          config.services.getty.autologinUser or ""
        }" — muss "root" sein.
        ${help "root-no-ssh"}
        Fix: services.getty.autologinUser = lib.mkForce "root"; identity.user darf kein Autologin haben.
      '';
    }
    {
      assertion = (config.services.getty.autologinUser or "") != user;
      message = ''
        ACCESS-POLICY VERLETZT: identity.user "${user}" hat tty-Autologin — verboten.
        ${help "single-ssh-user"}
        Fix: nur root an tty1, "${user}" nur per SSH.
      '';
    }
    {
      assertion = !config.security.sudo.wheelNeedsPassword;
      message = ''
        ACCESS-POLICY VERLETZT: wheelNeedsPassword=true — sudo bräuchte Passwort, es gibt keins.
        ${help "no-password"}
        Fix: security.sudo.wheelNeedsPassword = lib.mkForce false;
      '';
    }
    {
      assertion = config.systemd.services.sshd.serviceConfig.Restart or "" == "always";
      message = ''
        ACCESS-POLICY VERLETZT: sshd.service hat kein Restart=always — SSH könnte dauerhaft ausbleiben.
        ${help "sshd-alive"}
        Fix: systemd.services.sshd.serviceConfig.Restart = "always";
      '';
    }
  ]
  ++ lib.mapAttrsToList (name: u: {
    assertion = policy.isPasswordLocked u;
    message = ''
      ACCESS-POLICY VERLETZT: User "${name}" hat ein gesetztes Passwort (hashedPassword nicht gesperrt).
      ${help "no-password"}
      Fix: users.users.${name}.hashedPassword = lib.mkForce "!"; Passwort-Auth ist systemweit verboten.
    '';
  }) config.users.users
  ++ lib.mapAttrsToList (
    name: u:
    let
      keys = u.openssh.authorizedKeys.keys or [ ];
    in
    {
      assertion = keys == [ ] || policy.assertAllKeysEd25519 keys name;
      message = ''
        ACCESS-POLICY VERLETZT: User "${name}" hat unsichere SSH-Keys (nicht ssh-ed25519).
        ${help "ed25519-only"}
        Fix: nur ed25519 in users/${name}/profile.nix oder Keys entfernen.
      '';
    }
  ) config.users.users;
}
