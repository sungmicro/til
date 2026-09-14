"""검증 탭 배포물이 원본과 어긋나지 않는지 검사한다.

verify.html 을 고치고 build-installer.py 를 다시 돌리는 것을 잊으면,
설치 스크립트가 옛 파일을 배포하게 된다. 이 테스트가 그것을 잡는다.
"""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(__file__)
ROOT = os.path.abspath(os.path.join(HERE, ".."))
BIOPLUG = os.path.join(ROOT, "bioplug")
SOURCES = ["verify.html", "verify-stats.js", "verify-app.js"]
BUILT = ["install-verify.sh", "verify-standalone.html"]

BASH = shutil.which("bash")
NODE = shutil.which("node")


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


class TestGeneratedArtifactsAreCurrent(unittest.TestCase):
    def test_regenerating_changes_nothing(self):
        """지금 원본으로 다시 만들어도 결과가 같아야 한다."""
        before = {n: read(os.path.join(BIOPLUG, n)) for n in BUILT}
        proc = subprocess.run([sys.executable, "build-installer.py"],
                              cwd=BIOPLUG, capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        for n in BUILT:
            self.assertEqual(before[n], read(os.path.join(BIOPLUG, n)),
                             f"{n} 이 원본과 어긋납니다. build-installer.py 를 다시 실행하세요.")

    def test_standalone_embeds_both_scripts(self):
        html = read(os.path.join(BIOPLUG, "verify-standalone.html"))
        for js in ["verify-stats.js", "verify-app.js"]:
            self.assertIn(read(os.path.join(BIOPLUG, js)).strip(), html, js)
        self.assertNotIn('<script src="verify-stats.js">', html)
        self.assertNotIn('<script src="verify-app.js">', html)


@unittest.skipUnless(BASH, "bash 미설치 환경")
class TestInstaller(unittest.TestCase):
    def test_script_is_syntactically_valid(self):
        proc = subprocess.run([BASH, "-n", os.path.join(BIOPLUG, "install-verify.sh")],
                              capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_installs_byte_identical_files(self):
        dest = tempfile.mkdtemp()
        os.makedirs(os.path.join(dest, "public"))
        proc = subprocess.run([BASH, os.path.join(BIOPLUG, "install-verify.sh"), dest],
                              capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        for n in SOURCES:
            self.assertEqual(read(os.path.join(BIOPLUG, n)),
                             read(os.path.join(dest, "public", n)), n)

    def test_backs_up_existing_files(self):
        dest = tempfile.mkdtemp()
        pub = os.path.join(dest, "public")
        os.makedirs(pub)
        with open(os.path.join(pub, "verify.html"), "w", encoding="utf-8") as fh:
            fh.write("기존 내용")
        subprocess.run([BASH, os.path.join(BIOPLUG, "install-verify.sh"), dest],
                       capture_output=True, text=True, check=True)
        backups = [f for f in os.listdir(pub) if f.startswith("verify.html.bak.")]
        self.assertEqual(len(backups), 1)
        self.assertEqual(read(os.path.join(pub, backups[0])), "기존 내용")

    def test_leaves_other_files_alone(self):
        dest = tempfile.mkdtemp()
        pub = os.path.join(dest, "public")
        os.makedirs(pub)
        with open(os.path.join(pub, "index.html"), "w", encoding="utf-8") as fh:
            fh.write("기존 페이지")
        subprocess.run([BASH, os.path.join(BIOPLUG, "install-verify.sh"), dest],
                       capture_output=True, text=True, check=True)
        self.assertEqual(read(os.path.join(pub, "index.html")), "기존 페이지")

    def test_warns_when_build_wipes_public(self):
        dest = tempfile.mkdtemp()
        os.makedirs(os.path.join(dest, "public"))
        with open(os.path.join(dest, "build.mjs"), "w", encoding="utf-8") as fh:
            fh.write("rmSync('public', { recursive: true, force: true });\n")
        proc = subprocess.run([BASH, os.path.join(BIOPLUG, "install-verify.sh"), dest],
                              capture_output=True, text=True, check=True)
        self.assertIn("public 을 지웁니다", proc.stdout)
        self.assertIn("postbuild", proc.stdout)

    def test_keeps_reinstall_copy(self):
        dest = tempfile.mkdtemp()
        os.makedirs(os.path.join(dest, "public"))
        subprocess.run([BASH, os.path.join(BIOPLUG, "install-verify.sh"), dest],
                       capture_output=True, text=True, check=True)
        self.assertTrue(os.path.exists(os.path.join(dest, "tools", "install-verify.sh")))

    def test_rejects_missing_project_folder(self):
        proc = subprocess.run(
            [BASH, os.path.join(BIOPLUG, "install-verify.sh"), "/nonexistent/bioplug"],
            capture_output=True, text=True)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("없습니다", proc.stderr)


@unittest.skipUnless(NODE, "Node 미설치 환경")
class TestStandaloneRuns(unittest.TestCase):
    def test_embedded_scripts_parse(self):
        """단일 파일에 심은 JS 가 문법적으로 온전해야 한다."""
        html = read(os.path.join(BIOPLUG, "verify-standalone.html"))
        blocks = html.split("<script>")[1:]
        self.assertEqual(len(blocks), 2)
        for i, block in enumerate(blocks):
            code = block.split("</script>")[0]
            path = os.path.join(tempfile.mkdtemp(), f"b{i}.js")
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(code)
            proc = subprocess.run([NODE, "--check", path], capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, proc.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
