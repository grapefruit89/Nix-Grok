{
  lib,
  python3,
  fetchFromGitHub,
  writeShellScriptBin,
  runCommand,
}:
let
  src = fetchFromGitHub {
    owner = "zamnzim";
    repo = "Libreseerr";
    rev = "ddec271f1fd445d3bb01ee4408de095b7f2e2516";
    hash = "sha256-H95OQGsTt2IihOrQbp6Z6lgSJuMCj53fVvmWJdYzHgg=";
  };
  patchedSrc =
    runCommand "libreseerr-patched"
      {
        inherit src;
      }
      ''
            cp -r $src $out
            chmod -R u+w $out
            substituteInPlace $out/app.py \
              --replace-fail 'import os' 'import os

        DATA_ROOT = os.environ.get("DATA_DIR", os.path.join(os.path.dirname(__file__), "data"))'
            substituteInPlace $out/app.py \
              --replace 'os.path.join(os.path.dirname(__file__), "data"' 'DATA_ROOT'
      '';
  pythonEnv = python3.withPackages (
    ps: with ps; [
      flask
      flask-login
      ldap3
      requests
      gunicorn
      authlib
    ]
  );
in
writeShellScriptBin "libreseerr" ''
  exec ${pythonEnv}/bin/python -m gunicorn \
    --bind "''${LIBRESEERR_BIND:-127.0.0.1:6010}" \
    --workers 2 \
    --chdir ${patchedSrc} \
    app:app
''
