"""Complete synthetic repos and external functional oracles for native Tag runs."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile


def fixture(identifier, task, files, reference, check, command="python3 -m unittest -v", kind="code"):
    files = dict(files)
    files["AGENTS.md"] = "Use the standard library and existing style. Do not change existing tests or notes.txt. Do not install packages or use the network.\n"
    files["notes.txt"] = "Unrelated user work in progress: preserve this exact text.\n"
    files["README.md"] = f"Standalone exercise. Run checks with: {command}\n"
    return {"id": identifier, "task": task, "files": files, "reference": reference,
            "check": check, "command": command, "kind": kind,
            "allowed_edits": list(reference)}


DEV_TASKS = [
    fixture("clamp", "Fix clamp(value, low, high) in calc.py. It must clamp to inclusive bounds and raise ValueError when low > high. Preserve callers and existing tests.",
            {"calc.py": "def clamp(value, low, high):\n    return min(low, max(high, value))\n",
             "test_calc.py": "import unittest\nfrom calc import clamp\nclass Tests(unittest.TestCase):\n    def test_inside(self): self.assertEqual(clamp(5, 0, 10), 5)\n"},
            {"calc.py": "def clamp(value, low, high):\n    if low > high:\n        raise ValueError('inverted bounds')\n    return min(high, max(low, value))\n"},
            "from calc import clamp\nfor low, high in [(-4, 7), (0, 0), (2, 8)]:\n for x in range(-10, 15): assert clamp(x,low,high)==min(high,max(low,x))\ntry: clamp(3,5,1)\nexcept ValueError: pass\nelse: raise AssertionError('inverted bounds accepted')\n"),
    fixture("duration", "Implement parse_duration(text) in duration.py, returning integer seconds. Accept one or more integer amounts followed by h, m or s, in any order; allow surrounding whitespace and zero. Reject repeated units, signs, decimals, internal whitespace, unknown characters and empty strings with ValueError.",
            {"duration.py": "def parse_duration(text):\n    raise NotImplementedError\n",
             "test_duration.py": "import unittest\nfrom duration import parse_duration\nclass Tests(unittest.TestCase):\n    def test_hours(self): self.assertEqual(parse_duration('2h30m'), 9000)\n"},
            {"duration.py": "import re\n\ndef parse_duration(text):\n    text = text.strip()\n    parts = re.findall(r'([0-9]+)([hms])', text)\n    if not parts or ''.join(n + u for n, u in parts) != text or len({u for _, u in parts}) != len(parts):\n        raise ValueError('invalid duration')\n    return sum(int(n) * {'h': 3600, 'm': 60, 's': 1}[u] for n, u in parts)\n"},
            "from duration import parse_duration\nfor s,n in [('0s',0),('1m2h3s',7263),(' 9s ',9),('001h',3600),('15m',900)]: assert parse_duration(s)==n,(s,n)\nfor s in ['', ' ', '1h1h', '-2s', '+1s', '1.2m', '1 m', '1x', '3', '1H', '1s junk', '1h 2m']:\n try: parse_duration(s)\n except ValueError: pass\n else: raise AssertionError(s)\n"),
    fixture("csv-records", "Fix parse_records(text) in records.py using standard CSV behavior: support quoted commas, doubled quotes and newlines inside quoted fields. Ignore completely blank records, preserve empty fields, and return a list of rows of strings.",
            {"records.py": "def parse_records(text):\n    return [line.split(',') for line in text.splitlines() if line]\n",
             "test_records.py": "import unittest\nfrom records import parse_records\nclass Tests(unittest.TestCase):\n    def test_quoted(self): self.assertEqual(parse_records('a,\"b,c\"'), [['a','b,c']])\n"},
            {"records.py": "import csv\nimport io\n\ndef parse_records(text):\n    return [row for row in csv.reader(io.StringIO(text, newline='')) if row]\n"},
            "from records import parse_records\nassert parse_records('')==[]\nassert parse_records('a,\"b,c\"\\n\\n,\\n')==[['a','b,c'],['','']]\nassert parse_records('\"a\\nb\",c\\n')==[['a\\nb','c']]\nassert parse_records('\"a\"\"b\",x')==[['a\"b','x']]\nassert parse_records('a,b\\r\\nx,y\\r\\n')==[['a','b'],['x','y']]\n"),
    fixture("cache-expiry", "Fix Cache.get in cache.py: an entry is expired when now is equal to or after its expiration time. Expired entries must be removed. Zero TTL entries must never be returned. Keep Cache.put's API and leave unrelated files alone.",
            {"cache.py": "class Cache:\n    def __init__(self): self.items = {}\n    def put(self, key, value, now, ttl): self.items[key] = (value, now + ttl)\n    def get(self, key, now):\n        if key not in self.items: return None\n        value, expires = self.items[key]\n        if now > expires:\n            del self.items[key]\n            return None\n        return value\n",
             "test_cache.py": "import unittest\nfrom cache import Cache\nclass Tests(unittest.TestCase):\n    def test_boundary(self):\n        c=Cache(); c.put('a',7,10,2); self.assertIsNone(c.get('a',12))\n"},
            {"cache.py": "class Cache:\n    def __init__(self): self.items = {}\n    def put(self, key, value, now, ttl): self.items[key] = (value, now + ttl)\n    def get(self, key, now):\n        if key not in self.items: return None\n        value, expires = self.items[key]\n        if now >= expires:\n            del self.items[key]\n            return None\n        return value\n"},
            "from cache import Cache\nc=Cache(); assert c.get('missing',0) is None\nc.put('a',0,10,2); assert c.get('a',11)==0; assert c.get('a',12) is None; assert 'a' not in c.items\nc.put('b',False,0,0); assert c.get('b',0) is None; assert 'b' not in c.items\nc.put('a',3,20,3); assert c.get('a',24) is None\n"),
    fixture("shell-log-count", "Fix count_logs.sh DIR to print only the number of regular .log files directly in DIR. Include hidden names; suffix matching is case-sensitive. Ignore subdirectories, symlinks and deeper files. Filenames may contain spaces or newlines. Preserve the sh command-line interface.",
            {"count_logs.sh": "#!/bin/sh\nfind \"$1\" -name '*.log' | wc -l | tr -d ' '\n",
             "tests.sh": "#!/bin/sh\nset -eu\nd=$(mktemp -d ./visible.XXXXXX)\ntrap 'rm -rf \"$d\"' EXIT\nmkdir \"$d/sub\"; touch \"$d/a.log\" \"$d/sub/b.log\"\n[ \"$(sh count_logs.sh \"$d\")\" = 1 ]\n"},
            {"count_logs.sh": "#!/bin/sh\nfind \"$1\" -maxdepth 1 -type f -name '*.log' -exec printf x \\; | wc -c | tr -d '[:space:]'\nprintf '\\n'\n"},
            "import subprocess,tempfile\nfrom pathlib import Path\nwith tempfile.TemporaryDirectory() as d:\n p=Path(d); (p/'sub.log').mkdir(); (p/'sub.log'/'nested.log').touch()\n for n in ['a.log','.hidden.log','with space.log','with\\nnewline.log','UPPER.LOG','other.txt']: (p/n).touch()\n (p/'link.log').symlink_to(p/'a.log')\n assert subprocess.check_output(['sh','count_logs.sh',d],text=True).strip()=='4'\nwith tempfile.TemporaryDirectory() as d: assert subprocess.check_output(['sh','count_logs.sh',d],text=True).strip()=='0'\n",
            command="sh tests.sh"),
    fixture("swift-chunks", "Fix chunked(_:size:) in Algorithms.swift. Split integers into consecutive chunks of at most size, keeping order and the final partial chunk. Empty input and nonpositive sizes return []. Preserve the function signature.",
            {"Algorithms.swift": "func chunked(_ values: [Int], size: Int) -> [[Int]] {\n    guard size > 0 else { return [] }\n    return stride(from: 0, to: values.count, by: size).map { Array(values[$0..<($0 + size)]) }\n}\n",
             "main.swift": "assert(chunked([1,2,3,4,5], size: 2) == [[1,2],[3,4],[5]])\nprint(\"OK\")\n"},
            {"Algorithms.swift": "func chunked(_ values: [Int], size: Int) -> [[Int]] {\n    guard size > 0 else { return [] }\n    return stride(from: 0, to: values.count, by: size).map { Array(values[$0..<min($0 + size, values.count)]) }\n}\n"},
            "assert(chunked([], size: 2) == [])\nassert(chunked([1,2,3], size: 0) == [])\nassert(chunked([1], size: -2) == [])\nassert(chunked([1,2], size: 9) == [[1,2]])\nassert(chunked([1,2,3,4,5], size: 2) == [[1,2],[3,4],[5]])\nassert(chunked([1,2], size: 1) == [[1],[2]])\n",
            command="swiftc Algorithms.swift main.swift -o .fixture-check && ./.fixture-check", kind="swift"),
    fixture("swift-slug", "Fix slug(_:) in Slug.swift. Keep ASCII letters and digits, lowercase ASCII letters, replace every run of other characters with one hyphen, and trim leading/trailing hyphens. Non-ASCII characters are separators. Empty input returns an empty string.",
            {"Slug.swift": "import Foundation\n\nfunc slug(_ text: String) -> String {\n    text.lowercased().replacingOccurrences(of: \" \", with: \"-\")\n}\n",
             "main.swift": "assert(slug(\" Hello, World! \") == \"hello-world\")\nprint(\"OK\")\n"},
            {"Slug.swift": "func slug(_ text: String) -> String {\n    var result = \"\"\n    var separator = false\n    for scalar in text.unicodeScalars {\n        let value = scalar.value\n        if (65...90).contains(value) || (97...122).contains(value) || (48...57).contains(value) {\n            if separator && !result.isEmpty { result += \"-\" }\n            result += String(scalar).lowercased()\n            separator = false\n        } else { separator = true }\n    }\n    return result\n}\n"},
            "assert(slug(\"\") == \"\")\nassert(slug(\"---\") == \"\")\nassert(slug(\" Hello, World! \") == \"hello-world\")\nassert(slug(\"A___B 99\") == \"a-b-99\")\nassert(slug(\"Straße\") == \"stra-e\")\nassert(slug(\"aéB\") == \"a-b\")\nassert(slug(\"ABC123\") == \"abc123\")\n",
            command="swiftc Slug.swift main.swift -o .fixture-check && ./.fixture-check", kind="swift"),
    fixture("config-precedence", "Fix resolve(config, env, cli) in options.py. For retries and timeout, CLI overrides environment, which overrides config. Ignore missing keys and None; zero is valid. Convert accepted values to nonnegative integers, reject negatives, booleans and non-integer strings with ValueError. Do not mutate any input. Defaults are retries=3 and timeout=10.",
            {"options.py": "from defaults import DEFAULTS\n\ndef resolve(config, env, cli):\n    config.update(cli)\n    config.update(env)\n    return {key: int(config.get(key) or value) for key, value in DEFAULTS.items()}\n",
             "defaults.py": "DEFAULTS = {'retries': 3, 'timeout': 10}\n",
             "test_options.py": "import unittest\nfrom options import resolve\nclass Tests(unittest.TestCase):\n    def test_cli(self): self.assertEqual(resolve({}, {'retries':'2'}, {'retries':0})['retries'],0)\n",
             **{f"extras/module_{i}.py": f"VALUE = {i}\n" for i in range(12)}},
            {"options.py": "import re\nfrom defaults import DEFAULTS\n\ndef resolve(config, env, cli):\n    result = dict(DEFAULTS)\n    for layer in (config, env, cli):\n        for key in DEFAULTS:\n            value = layer.get(key)\n            if value is None: continue\n            if isinstance(value, bool) or not isinstance(value, (int, str)):\n                raise ValueError('invalid integer')\n            if isinstance(value, str) and re.fullmatch(r'[0-9]+', value) is None:\n                raise ValueError('invalid integer')\n            number = int(value)\n            if number < 0: raise ValueError('negative integer')\n            result[key] = number\n    return result\n"},
            "from options import resolve\nassert resolve({}, {}, {})=={'retries':3,'timeout':10}\na={'retries':9}; b={'retries':'4','timeout':'0'}; c={'retries':0,'timeout':None}; assert resolve(a,b,c)=={'retries':0,'timeout':0}; assert a=={'retries':9} and b=={'retries':'4','timeout':'0'} and c=={'retries':0,'timeout':None}\nfor v in [-1,True,False,'-1','1.5','abc',2.5]:\n try: resolve({}, {}, {'retries':v})\n except ValueError: pass\n else: raise AssertionError(str(v))\n"),
    fixture("first-index", "Fix first_index(sorted_values, target) in search.py: return the first matching index, or -1 if absent. Input is sorted ascending and may contain duplicates or be empty. Keep binary-search complexity and do not mutate the input.",
            {"search.py": "def first_index(values, target):\n    low, high = 0, len(values) - 1\n    while low <= high:\n        mid = (low + high) // 2\n        if values[mid] == target: return mid\n        if values[mid] < target: low = mid + 1\n        else: high = mid - 1\n    return -1\n",
             "test_search.py": "import unittest\nfrom search import first_index\nclass Tests(unittest.TestCase):\n    def test_duplicates(self): self.assertEqual(first_index([1,2,2,2,4],2),1)\n"},
            {"search.py": "def first_index(values, target):\n    low, high = 0, len(values)\n    while low < high:\n        mid = (low + high) // 2\n        if values[mid] < target: low = mid + 1\n        else: high = mid\n    return low if low < len(values) and values[low] == target else -1\n"},
            "from search import first_index\nimport random\nr=random.Random(123)\nfor _ in range(40):\n a=sorted(r.randrange(-5,6) for _ in range(r.randrange(25))); before=list(a)\n for t in range(-7,8): assert first_index(a,t)==(a.index(t) if t in a else -1)\n assert a==before\nclass Indexed:\n def __init__(self): self.reads=0\n def __len__(self): return 500001\n def __getitem__(self,i):\n  self.reads+=1\n  assert self.reads <= 100, 'linear number of reads'\n  return 1 if i==500000 else 0\n def __iter__(self): raise AssertionError('binary search must use indexing')\na=Indexed(); assert first_index(a,1)==500000\n"),
    fixture("line-buffer", "Fix LineBuffer in lines.py for strings arriving in arbitrary chunks. feed(part) emits every complete LF-delimited line, including empty lines; strip one CR immediately before LF. Keep partial text across calls. finish() emits the remaining nonempty text unchanged once, then returns [] on later calls.",
            {"lines.py": "class LineBuffer:\n    def __init__(self): self.pending = ''\n    def feed(self, part):\n        self.pending += part\n        rows = self.pending.splitlines()\n        self.pending = ''\n        return rows\n    def finish(self): return []\n",
             "test_lines.py": "import unittest\nfrom lines import LineBuffer\nclass Tests(unittest.TestCase):\n    def test_partial(self):\n        b=LineBuffer(); self.assertEqual(b.feed('ab'),[]); self.assertEqual(b.feed('c\\n'),['abc'])\n"},
            {"lines.py": "class LineBuffer:\n    def __init__(self): self.pending = ''\n    def feed(self, part):\n        self.pending += part\n        rows = self.pending.split('\\n')\n        self.pending = rows.pop()\n        return [row[:-1] if row.endswith('\\r') else row for row in rows]\n    def finish(self):\n        rest = self.pending\n        self.pending = ''\n        return [rest] if rest else []\n"},
            "from lines import LineBuffer\nb=LineBuffer(); assert b.feed('a\\r')==[]; assert b.feed('\\n\\nb\\nc')==['a','','b']; assert b.feed('d')==[]; assert b.finish()==['cd']; assert b.finish()==[]\nb=LineBuffer(); assert b.feed('\\n\\n')==['','']; assert b.finish()==[]\nb=LineBuffer(); assert b.feed('x\\r')==[]; assert b.finish()==['x\\r']\n"),
    fixture("read-only-config", "Read-only question: where is the retry budget configured, and what value will app.py use? Explain briefly with the relevant paths. Do not change any files.",
            {"app.py": "from settings import load\nprint(load()['retry_budget'])\n", "settings.py": "import json\nfrom pathlib import Path\ndef load(): return json.loads(Path('settings.json').read_text())\n", "settings.json": '{"retry_budget":4}\n'},
            {}, "", command="python3 app.py", kind="read-only"),
    fixture("ambiguous-rounding", "Implement round_invoice in invoice.py using our business rounding policy. The product owner has not selected between half-even and half-up; the two policies produce different invoice totals. Ask me to choose before implementing either policy.",
            {"invoice.py": "def round_invoice(value):\n    raise NotImplementedError('policy not selected')\n"},
            {}, "", command="No functional check until policy is selected", kind="clarify"),
]


def materialize(task, directory, reference=False):
    for name, content in {**task["files"], **(task["reference"] if reference else {})}.items():
        path = directory / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)


def functional_check(task, directory):
    """Execute trusted external checks in a separate process, with a deadline."""
    if task["kind"] in ["read-only", "clarify"]:
        return {"returncode": 0, "stdout": "behavioral task; checked separately", "stderr": ""}
    with tempfile.TemporaryDirectory(prefix="tag-external-grade-") as temporary:
        external = Path(temporary)
        if task["kind"] == "swift":
            (external / "main.swift").write_text(task["check"])
            source = next(name for name in task["reference"] if name.endswith(".swift"))
            compile_result = subprocess.run(["swiftc", str(directory / source), str(external / "main.swift"), "-o", str(external / "check")], capture_output=True, text=True, timeout=45)
            if compile_result.returncode:
                return {"returncode": compile_result.returncode, "stdout": compile_result.stdout, "stderr": compile_result.stderr}
            result = subprocess.run([str(external / "check")], capture_output=True, text=True, timeout=10)
        else:
            script = "import sys\nsys.path.insert(0, sys.argv[1])\n" + task["check"]
            check = external / "check.py"
            check.write_text(script)
            result = subprocess.run([sys.executable, "-I", str(check), str(directory)], cwd=directory, capture_output=True, text=True, timeout=15)
        return {"returncode": result.returncode, "stdout": result.stdout, "stderr": result.stderr}


if __name__ == "__main__":
    results = []
    for task in DEV_TASKS:
        if task["kind"] in ["read-only", "clarify"]:
            continue
        with tempfile.TemporaryDirectory(prefix="tag-oracle-") as temporary:
            directory = Path(temporary)
            materialize(task, directory)
            broken = functional_check(task, directory)
            materialize(task, directory, reference=True)
            repaired = functional_check(task, directory)
            results.append({"task": task["id"], "broken_fails": broken["returncode"] != 0,
                            "reference_passes": repaired["returncode"] == 0,
                            "reference_error": repaired["stderr"][-500:]})
    print(json.dumps(results, indent=2))
    if not all(x["broken_fails"] and x["reference_passes"] for x in results):
        raise SystemExit(1)
