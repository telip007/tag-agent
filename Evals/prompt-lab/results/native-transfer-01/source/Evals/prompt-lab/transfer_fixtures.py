"""Reserved multi-file transfer tasks, authored before final prompt selection."""

import json
from pathlib import Path
import tempfile
from textwrap import dedent

from trajectory_fixtures import fixture, functional_check, materialize


def source(text):
    return dedent(text).lstrip("\n")


TRANSFER_TASKS = [
    fixture(
        "inventory-import",
        "Repair the inventory CSV import API and CLI. inventory.importer.apply_rows(connection, text) must require the exact header item_id,qty, ignore completely blank records, strip surrounding whitespace from nonempty item IDs, and accept quantities containing ASCII digits only (zero is valid). Reject malformed rows or quantities with ValueError. Each valid data record adds its quantity to that item's existing quantity, including repeated IDs in one import; return the number of imported data records. Validate the whole input before writing and apply all writes in one transaction: validation or SQLite write failure must preserve existing quantities and propagate the exception. The connection has no pending transaction on entry. Keep the existing schema and APIs. python3 -m inventory.cli DB CSV must print imported N rows and return 0 on success; validation, SQLite and file I/O errors must return 2 with a concise stderr message and no success output or traceback. Update both layers as needed; preserve existing tests and unrelated files.",
        {
            "inventory/__init__.py": "",
            "inventory/db.py": source(r'''
                import sqlite3

                def open_db(path):
                    connection = sqlite3.connect(path)
                    connection.execute('CREATE TABLE IF NOT EXISTS items (item_id TEXT PRIMARY KEY, qty INTEGER NOT NULL CHECK(qty >= 0))')
                    connection.commit()
                    return connection
            '''),
            "inventory/importer.py": source(r'''
                def apply_rows(connection, text):
                    rows = text.splitlines()[1:]
                    for row in rows:
                        item_id, qty = row.split(',')
                        connection.execute('INSERT OR REPLACE INTO items VALUES (?, ?)', (item_id, int(qty)))
                        connection.commit()
                    return len(rows)
            '''),
            "inventory/cli.py": source(r'''
                import sys
                from inventory.db import open_db
                from inventory.importer import apply_rows

                def main(argv=None):
                    argv = sys.argv[1:] if argv is None else argv
                    with open_db(argv[0]) as connection:
                        text = open(argv[1], encoding='utf-8').read()
                        count = apply_rows(connection, text)
                    print('done', count)
                    return 0

                if __name__ == '__main__':
                    raise SystemExit(main())
            '''),
            "tests/test_import.py": source(r'''
                import unittest
                from inventory.db import open_db
                from inventory.importer import apply_rows

                class Tests(unittest.TestCase):
                    def test_adds_existing_quantity(self):
                        with open_db(':memory:') as connection:
                            apply_rows(connection, 'item_id,qty\na,2\n')
                            apply_rows(connection, 'item_id,qty\na,3\n')
                            self.assertEqual(connection.execute('SELECT qty FROM items').fetchone()[0], 5)
            '''),
        },
        {
            "inventory/importer.py": source(r'''
                import csv
                import io
                import re

                def apply_rows(connection, text):
                    try:
                        rows = csv.reader(io.StringIO(text, newline=''), strict=True)
                        if next(rows, None) != ['item_id', 'qty']:
                            raise ValueError('expected item_id,qty header')
                        parsed = []
                        for row in rows:
                            if not row:
                                continue
                            if len(row) != 2 or not row[0].strip() or re.fullmatch(r'[0-9]+', row[1]) is None:
                                raise ValueError('invalid inventory row')
                            parsed.append((row[0].strip(), int(row[1])))
                    except csv.Error as error:
                        raise ValueError('invalid CSV') from error
                    with connection:
                        for item_id, qty in parsed:
                            connection.execute('INSERT INTO items VALUES (?, ?) ON CONFLICT(item_id) DO UPDATE SET qty = items.qty + excluded.qty', (item_id, qty))
                    return len(parsed)
            '''),
            "inventory/cli.py": source(r'''
                import sqlite3
                import sys
                from pathlib import Path
                from inventory.db import open_db
                from inventory.importer import apply_rows

                def main(argv=None):
                    argv = sys.argv[1:] if argv is None else argv
                    if len(argv) != 2:
                        print('usage: inventory DB CSV', file=sys.stderr)
                        return 2
                    connection = None
                    try:
                        text = Path(argv[1]).read_text(encoding='utf-8')
                        connection = open_db(argv[0])
                        count = apply_rows(connection, text)
                    except (ValueError, sqlite3.Error, OSError) as error:
                        print('import failed: ' + str(error), file=sys.stderr)
                        return 2
                    finally:
                        if connection is not None:
                            connection.close()
                    print('imported ' + str(count) + ' rows')
                    return 0

                if __name__ == '__main__':
                    raise SystemExit(main())
            '''),
        },
        source(r'''
            import sqlite3, subprocess, tempfile
            from pathlib import Path
            from inventory.db import open_db
            from inventory.importer import apply_rows
            connection = open_db(':memory:')
            assert apply_rows(connection, 'item_id,qty\n a ,2\na,3\n"b,c",0\n\n') == 3
            assert connection.execute('SELECT * FROM items ORDER BY item_id').fetchall() == [('a',5),('b,c',0)]
            before = connection.execute('SELECT * FROM items ORDER BY item_id').fetchall()
            for text in ['wrong,qty\na,1\n', 'item_id,qty\nx,1\ny,-2\n', 'item_id,qty\nx,1.5\n', 'item_id,qty\n,1\n', 'item_id,qty\na,1,2\n', 'item_id,qty\na, 2\n', 'item_id,qty\na,٢\n']:
                try: apply_rows(connection, text)
                except ValueError: pass
                else: raise AssertionError('invalid CSV accepted')
                assert connection.execute('SELECT * FROM items ORDER BY item_id').fetchall() == before
            connection.execute("CREATE TRIGGER blocked BEFORE INSERT ON items WHEN NEW.item_id='bad' BEGIN SELECT RAISE(ABORT, 'blocked'); END")
            connection.commit()
            try: apply_rows(connection, 'item_id,qty\na,9\nbad,1\n')
            except sqlite3.Error: pass
            else: raise AssertionError('SQLite failure swallowed')
            assert connection.execute('SELECT * FROM items ORDER BY item_id').fetchall() == before
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary); db = root/'items.db'; csv = root/'input.csv'
                csv.write_text('item_id,qty\na,2\na,3\n')
                command = [sys.executable, '-m', 'inventory.cli', str(db), str(csv)]
                result = subprocess.run(command, text=True, capture_output=True)
                assert result.returncode == 0 and result.stdout.strip() == 'imported 2 rows', (result.returncode,result.stdout,result.stderr)
                csv.write_text('item_id,qty\na,9\nb,invalid\n')
                result = subprocess.run(command, text=True, capture_output=True)
                assert result.returncode == 2 and not result.stdout.strip() and result.stderr and 'Traceback' not in result.stderr
                with sqlite3.connect(db) as saved: assert saved.execute('SELECT * FROM items').fetchall() == [('a',5)]
                csv.unlink(); result = subprocess.run(command, text=True, capture_output=True)
                assert result.returncode == 2 and not result.stdout.strip() and 'Traceback' not in result.stderr
        '''),
        command="python3 -m unittest discover -s tests -v",
    ),
    fixture(
        "framed-client",
        "Repair framing.Decoder and client.decode_messages(chunks, max_size=65536). Frames have a four-byte unsigned big-endian byte length followed by that many payload bytes. feed(bytes) returns all complete payloads, keeping partial headers/bodies across calls and handling multiple or empty frames. A length above max_size raises ValueError immediately after its header; subsequent feed and finish calls must raise ValueError until reset() clears all state. finish() returns None on a complete stream and raises ValueError on a partial header/body without discarding it; callers may feed more after this truncation error. max_size is a nonnegative integer supplied by callers. decode_messages consumes a single-pass iterable of arbitrary byte chunks through one decoder, returns UTF-8 strings, validates the final stream with finish(), and propagates malformed UTF-8 as UnicodeDecodeError. Preserve both APIs and existing tests.",
        {
            "framing.py": source(r'''
                class Decoder:
                    def __init__(self, max_size=65536):
                        self.max_size = max_size
                    def feed(self, data):
                        if not data:
                            return []
                        size = int.from_bytes(data[:4], 'big')
                        return [data[4:4+size]]
                    def finish(self):
                        return None
                    def reset(self):
                        pass
            '''),
            "client.py": source(r'''
                from framing import Decoder

                def decode_messages(chunks, max_size=65536):
                    result = []
                    for chunk in chunks:
                        result.extend(payload.decode('utf-8', errors='replace') for payload in Decoder(max_size).feed(chunk))
                    return result
            '''),
            "tests/test_client.py": source(r'''
                import unittest
                from client import decode_messages

                class Tests(unittest.TestCase):
                    def test_split_header(self):
                        frame = (2).to_bytes(4, 'big') + b'ok'
                        self.assertEqual(decode_messages([frame[:2], frame[2:]]), ['ok'])
            '''),
        },
        {
            "framing.py": source(r'''
                class Decoder:
                    def __init__(self, max_size=65536):
                        self.max_size = max_size
                        self.reset()
                    def reset(self):
                        self.buffer = bytearray()
                        self.expected = None
                        self.failed = False
                    def feed(self, data):
                        if self.failed:
                            raise ValueError('reset required')
                        self.buffer.extend(data)
                        output = []
                        while True:
                            if self.expected is None:
                                if len(self.buffer) < 4:
                                    break
                                self.expected = int.from_bytes(self.buffer[:4], 'big')
                                del self.buffer[:4]
                                if self.expected > self.max_size:
                                    self.failed = True
                                    raise ValueError('frame too large')
                            if len(self.buffer) < self.expected:
                                break
                            output.append(bytes(self.buffer[:self.expected]))
                            del self.buffer[:self.expected]
                            self.expected = None
                        return output
                    def finish(self):
                        if self.failed or self.buffer or self.expected is not None:
                            raise ValueError('incomplete or failed stream')
                        return None
            '''),
            "client.py": source(r'''
                from framing import Decoder

                def decode_messages(chunks, max_size=65536):
                    decoder = Decoder(max_size)
                    result = []
                    for chunk in chunks:
                        result.extend(payload.decode('utf-8') for payload in decoder.feed(chunk))
                    decoder.finish()
                    return result
            '''),
        },
        source(r'''
            from framing import Decoder
            from client import decode_messages
            def frame(payload): return len(payload).to_bytes(4, 'big') + payload
            wire = frame(b'') + frame('hé🙂'.encode()) + frame(b'ok') + frame(b'')
            for cut in range(len(wire)+1):
                assert decode_messages(iter([wire[:cut], wire[cut:]])) == ['', 'hé🙂', 'ok', '']
            assert decode_messages(bytes([byte]) for byte in wire) == ['', 'hé🙂', 'ok', '']
            assert decode_messages([]) == []
            decoder = Decoder(0); assert decoder.feed(frame(b'')) == [b'']; assert decoder.finish() is None
            decoder = Decoder(2); assert decoder.feed(frame(b'ok')) == [b'ok']; assert decoder.finish() is None
            for partial in [frame(b'ok')[:2], frame(b'ok')[:5]]:
                decoder = Decoder(); assert decoder.feed(partial) == []
                try: decoder.finish()
                except ValueError: pass
                else: raise AssertionError('truncation accepted')
                assert decoder.feed(frame(b'ok')[len(partial):]) == [b'ok']; decoder.finish()
            decoder = Decoder(2)
            try: decoder.feed((3).to_bytes(4, 'big'))
            except ValueError: pass
            else: raise AssertionError('oversize header accepted')
            for operation in [lambda: decoder.feed(frame(b'a')), decoder.finish]:
                try: operation()
                except ValueError: pass
                else: raise AssertionError('failed stream reused without reset')
            decoder.reset(); assert decoder.feed(frame(b'a')) == [b'a']; decoder.finish()
            for chunks in [[b'\x00'], [frame(b'ok')[:-1]]]:
                try: decode_messages(chunks)
                except ValueError: pass
                else: raise AssertionError('client skipped finish validation')
            try: decode_messages([frame(b'\xff')])
            except UnicodeDecodeError: pass
            else: raise AssertionError('invalid UTF-8 replaced')
        '''),
        command="python3 -m unittest discover -s tests -v",
    ),
    fixture(
        "tree-report-cli",
        "Repair scanner.scan(root) and the report.py CLI. scan returns {'entries': [...], 'totals': {'files': N, 'bytes': B, 'lines': L}} for all regular UTF-8 text files recursively, including hidden names. Skip every symlink, files containing NUL bytes, and files that cannot decode as UTF-8. Each entry has path (root-relative POSIX string), bytes (raw byte length), and lines (number of LF bytes plus one if nonempty and not LF-terminated). CRLF counts once per LF; lone CR is ordinary content. Sort entries lexicographically by path, and sum totals from included entries. The root itself must be a real directory, not a symlink; otherwise raise ValueError. Do not follow directory symlinks. Do not modify scanned files. python3 report.py ROOT must emit exactly one JSON object with this data and exit 0; invalid roots or I/O errors must exit 2 with a concise stderr message and no stdout JSON or traceback. Preserve the existing scan(root) API, CLI argument shape, tests and unrelated files.",
        {
            "scanner.py": source(r'''
                from pathlib import Path

                def scan(root):
                    entries = []
                    for path in Path(root).iterdir():
                        if path.is_file():
                            text = path.read_text()
                            entries.append({'path': path.name, 'bytes': len(text), 'lines': len(text.splitlines())})
                    return {'entries': entries, 'totals': {'files': len(entries), 'bytes': sum(row['bytes'] for row in entries), 'lines': sum(row['lines'] for row in entries)}}
            '''),
            "report.py": source(r'''
                import sys
                from scanner import scan

                def main(argv=None):
                    argv = sys.argv[1:] if argv is None else argv
                    print(scan(argv[0]))
                    return 0

                if __name__ == '__main__':
                    raise SystemExit(main())
            '''),
            "tests/test_scan.py": source(r'''
                import tempfile
                import unittest
                from pathlib import Path
                from scanner import scan

                class Tests(unittest.TestCase):
                    def test_recursive_bytes(self):
                        with tempfile.TemporaryDirectory() as temporary:
                            root = Path(temporary); (root/'nested').mkdir()
                            (root/'nested'/'text').write_text('é')
                            self.assertEqual(scan(root)['totals'], {'files': 1, 'bytes': 2, 'lines': 1})
            '''),
        },
        {
            "scanner.py": source(r'''
                from pathlib import Path

                def scan(root):
                    root = Path(root)
                    if root.is_symlink() or not root.is_dir():
                        raise ValueError('root must be a real directory')
                    entries = []
                    for path in root.rglob('*'):
                        if path.is_symlink() or not path.is_file():
                            continue
                        data = path.read_bytes()
                        if b'\x00' in data:
                            continue
                        try:
                            data.decode('utf-8')
                        except UnicodeDecodeError:
                            continue
                        lines = data.count(b'\n') + int(bool(data) and not data.endswith(b'\n'))
                        entries.append({'path': path.relative_to(root).as_posix(), 'bytes': len(data), 'lines': lines})
                    entries.sort(key=lambda row: row['path'])
                    return {'entries': entries, 'totals': {'files': len(entries), 'bytes': sum(row['bytes'] for row in entries), 'lines': sum(row['lines'] for row in entries)}}
            '''),
            "report.py": source(r'''
                import json
                import sys
                from scanner import scan

                def main(argv=None):
                    argv = sys.argv[1:] if argv is None else argv
                    if len(argv) != 1:
                        print('usage: report.py ROOT', file=sys.stderr)
                        return 2
                    try:
                        result = scan(argv[0])
                    except (ValueError, OSError) as error:
                        print('scan failed: ' + str(error), file=sys.stderr)
                        return 2
                    print(json.dumps(result))
                    return 0

                if __name__ == '__main__':
                    raise SystemExit(main())
            '''),
        },
        source(r'''
            import json, subprocess, tempfile
            from pathlib import Path
            from scanner import scan
            with tempfile.TemporaryDirectory() as temporary:
                parent = Path(temporary); root = parent/'tree'; root.mkdir(); (root/'sub').mkdir()
                files = {'z': b'a\r\nb', '.hidden': b'\n', 'sub/é.txt': 'é\n🙂'.encode(), 'empty': b'', 'space\nname': b'\r', 'binary': b'a\x00b', 'invalid': b'\xff'}
                for name, data in files.items(): (root/name).write_bytes(data)
                (root/'link').symlink_to(root/'z'); outside = parent/'outside'; outside.mkdir(); (outside/'secret').write_text('skip')
                (root/'dir-link').symlink_to(outside, target_is_directory=True)
                expected = []
                for name in sorted(set(files) - {'binary','invalid'}):
                    data = files[name]; expected.append({'path':name,'bytes':len(data),'lines':data.count(b'\n')+int(bool(data) and not data.endswith(b'\n'))})
                result = scan(root); assert result['entries'] == expected, result
                assert result['totals'] == {'files':len(expected),'bytes':sum(x['bytes'] for x in expected),'lines':sum(x['lines'] for x in expected)}
                assert all((root/name).read_bytes() == data for name,data in files.items())
                cli = subprocess.run([sys.executable,'report.py',str(root)],text=True,capture_output=True)
                assert cli.returncode == 0 and json.loads(cli.stdout) == result, (cli.returncode,cli.stdout,cli.stderr)
                (parent/'root-link').symlink_to(root, target_is_directory=True)
                for invalid in [parent/'missing', root/'z', parent/'root-link']:
                    try: scan(invalid)
                    except ValueError: pass
                    else: raise AssertionError('invalid root accepted')
                    cli = subprocess.run([sys.executable,'report.py',str(invalid)],text=True,capture_output=True)
                    assert cli.returncode == 2 and not cli.stdout.strip() and cli.stderr and 'Traceback' not in cli.stderr
        '''),
        command="python3 -m unittest discover -s tests -v",
    ),
]


if __name__ == "__main__":
    report = []
    for task in TRANSFER_TASKS:
        with tempfile.TemporaryDirectory(prefix="tag-transfer-oracle-") as temporary:
            directory = Path(temporary)
            materialize(task, directory)
            original = functional_check(task, directory)
            materialize(task, directory, reference=True)
            repaired = functional_check(task, directory)
            report.append({"task": task["id"], "broken_fails": original["returncode"] != 0,
                           "reference_passes": repaired["returncode"] == 0,
                           "reference_error": repaired["stderr"][-700:]})
    print(json.dumps(report, indent=2))
    if not all(row["broken_fails"] and row["reference_passes"] for row in report):
        raise SystemExit(1)
