{
  lib,
  python3,
  fetchFromGitHub,
  writeShellScriptBin,
  writeTextFile,
  runCommand,
}:
let
  src = fetchFromGitHub {
    owner = "zamnzim";
    repo = "Libreseerr";
    rev = "ddec271f1fd445d3bb01ee4408de095b7f2e2516";
    hash = "sha256-H95OQGsTt2IihOrQbp6Z6lgSJuMCj53fVvmWJdYzHgg=";
  };
  patchScript = writeTextFile {
    name = "libreseerr-patch-data-dir.py";
    text = ''
      #!/usr/bin/env python3
      from pathlib import Path
      import sys

      p = Path(sys.argv[1])
      text = p.read_text()
      needle = "import os\n"
      insert = (
          "import os\n\n"
          "def _libreseerr_data_root():\n"
          "    base = os.path.dirname(__file__)\n"
          '    return os.environ.get("DATA_DIR", os.path.join(base, "data"))\n\n'
      )
      if needle not in text:
          raise SystemExit("import os not found")
      text = text.replace(needle, insert, 1)
      text = text.replace(
          'os.path.join(os.path.dirname(__file__), "data",',
          'os.path.join(_libreseerr_data_root(),',
      )
      text = text.replace(
          'os.path.join(os.path.dirname(__file__), "data")',
          "_libreseerr_data_root()",
      )
      p.write_text(text)
    '';
  };
  patchedSrc =
    runCommand "libreseerr-patched"
      {
        inherit src;
        nativeBuildInputs = [ python3 ];
      }
      ''
        cp -r $src $out
        chmod -R u+w $out
        python3 ${patchScript} $out/app.py
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
