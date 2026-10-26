from pathlib import Path
import os
import subprocess
import sys

root = Path(__file__).resolve().parent
env = os.environ.copy()
env['CLANG_MODULE_CACHE_PATH'] = str(root / '.build/ModuleCache')
env['SWIFTPM_MODULECACHE_OVERRIDE'] = str(root / '.build/ModuleCache')
action = sys.argv[1] if len(sys.argv) > 1 else 'build'
cmd = ['swift', action, '--disable-sandbox', '--cache-path', str(root / '.build/cache'), '--scratch-path', str(root / '.build')]
if '--release' in sys.argv:
    cmd += ['-c', 'release']
result = subprocess.run(cmd, cwd=root, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
log = root / '.build' / (action + '.log')
log.parent.mkdir(exist_ok=True)
log.write_text(result.stdout)
lines = result.stdout.splitlines()
interesting = [line for line in lines if any(s in line for s in ['error:', 'warning:', 'Build complete', 'Test Suite', 'Executed ', 'passed', 'failed', 'Build failed', 'Build succeeded'])]
print('\n'.join(interesting[-80:] or lines[-15:]))
print('完整日志：' + str(log))
sys.exit(result.returncode)
