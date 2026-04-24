#!/usr/bin/env python3
import sys
import tarfile
import io

# Read content from stdin
content = sys.stdin.read()

# Filename is passed as first argument
filename = sys.argv[1]

# Optional: additional arguments can be added later (e.g., mtime, permissions)

buffer = io.BytesIO()
with tarfile.open(fileobj=buffer, mode='w') as tar:
    info = tarfile.TarInfo(name=filename)
    info.size = len(content)
    info.mtime = 0          # Make output deterministic
    # info.mode = 0o644     # You can customize permissions if needed

    tar.addfile(info, io.BytesIO(content.encode('utf-8')))

# Output the raw tar bytes to stdout
sys.stdout.buffer.write(buffer.getvalue())
