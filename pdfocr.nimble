version       = "0.1.0"
author        = "Unknown"
description   = "High-throughput PDF OCR extractor"
license       = "MIT"
srcDir        = "src"
bin           = @["app"]

requires "nim >= 1.6.0"
requires "threading"
requires "mimalloc"

