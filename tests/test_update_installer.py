"""Exercise the actual installer with OS/network boundaries stubbed in a temp copy."""
import hashlib
import os
from pathlib import Path
import plistlib
import shlex
import subprocess
import sys
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1] / "Hugging Face/Resources/install-update.sh"

STUB = r'''
import os, pathlib, shutil, subprocess, sys
command, *args = sys.argv[1:]
scenario = os.environ['SCENARIO']
fixture = pathlib.Path(os.environ['FIXTURE'])
if command == 'curl':
    if scenario == 'download': sys.exit(22)
    source = 'checksum' if args[-1].endswith('.sha256') else 'image'
    shutil.copyfile(fixture / source, args[args.index('--output') + 1])
elif command == 'hdiutil':
    if args[0] == 'attach':
        if scenario == 'mount': sys.exit(1)
        shutil.copytree(fixture / 'candidate.app', pathlib.Path(args[args.index('-mountpoint') + 1]) / 'Hugging Face.app')
elif command == 'codesign':
    if scenario == 'signature': sys.exit(1)
elif command == 'sw_vers':
    print('14.0.0')
elif command == 'open':
    with (fixture / 'opened').open('a') as output: output.write(args[0] + '\n')
    if scenario == 'launch' and (pathlib.Path(args[0]) / 'new').exists(): sys.exit(1)
elif command == 'mv':
    if scenario == 'replace' and '/.hugging-face-update.' in args[0]: sys.exit(1)
    sys.exit(subprocess.call(['/bin/mv', *args]))
elif command == 'kill':
    sys.exit(0 if scenario == 'timeout' else 1)
elif command in ('sleep', 'osascript'):
    pass
else:
    raise ValueError(command)
'''


class InstallerTests(unittest.TestCase):
    def run_installer(self, scenario):
        with tempfile.TemporaryDirectory(prefix="hf updater test ") as temporary:
            root = Path(temporary)
            fixture = root / "fixtures"
            fixture.mkdir()
            work = root / "work"
            work.mkdir()
            applications = root / "Applications with spaces"
            applications.mkdir()
            target = applications / "Hugging Face.app"
            target.mkdir()
            (target / "old").write_text("original app")
            candidate = fixture / "candidate.app"
            (candidate / "Contents").mkdir(parents=True)
            (candidate / "new").write_text("updated app")
            plist = {
                "CFBundleIdentifier": "wrong.app" if scenario == "identity" else "ehcalabres.HuggingFace",
                "CFBundleShortVersionString": "0.1.0" if scenario == "version" else "1.2.3",
                "LSMinimumSystemVersion": "99.0" if scenario == "os" else "14.0",
            }
            with (candidate / "Contents/Info.plist").open("wb") as output:
                plistlib.dump(plist, output)
            image = b"fixture disk image"
            (fixture / "image").write_bytes(image)
            digest = "0" * 64 if scenario == "checksum" else hashlib.sha256(image).hexdigest()
            (fixture / "checksum").write_text(digest + "  Hugging-Face-1.2.3.dmg\n")
            stub = root / "stub.py"
            stub.write_text(STUB)
            script = SOURCE.read_text()
            commands = ["/usr/bin/curl", "/usr/bin/hdiutil", "/usr/bin/codesign", "/usr/bin/sw_vers", "/usr/bin/open", "/usr/bin/osascript", "/bin/mv", "/bin/kill", "/bin/sleep"]
            for command in commands:
                replacement = f"{shlex.quote(sys.executable)} {shlex.quote(str(stub))} {Path(command).name}"
                script = script.replace(command, replacement)
            installer = root / "installer.sh"
            installer.write_text(script)
            result = subprocess.run(
                ["/bin/bash", str(installer), str(work), str(target), "99999999", "1.2.3", "https://fixture/image", "https://fixture/image.sha256"],
                env={**os.environ, "SCENARIO": scenario, "FIXTURE": str(fixture)},
                capture_output=True, text=True, timeout=30,
            )
            if scenario == "success":
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertTrue((target / "new").exists())
                self.assertFalse((target / "old").exists())
                self.assertTrue((fixture / "opened").exists())
            else:
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertTrue((target / "old").exists(), result.stdout + result.stderr)
                self.assertFalse((target / "new").exists())
            self.assertFalse(work.exists())
            self.assertEqual(list(applications.iterdir()), [target])

    def test_success_and_failures(self):
        for scenario in ["success", "download", "checksum", "mount", "identity", "version", "signature", "os", "timeout", "replace", "launch"]:
            with self.subTest(scenario=scenario):
                self.run_installer(scenario)


if __name__ == "__main__":
    unittest.main()
