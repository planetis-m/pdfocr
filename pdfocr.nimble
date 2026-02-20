version       = "0.1.8"
author        = "planetis"
description   = "High-throughput PDF OCR extractor"
license       = "MIT"
srcDir        = "src"
bin           = @["app"]

requires "nim >= 2.2.6"
requires "mimalloc"
requires "https://github.com/planetis-m/jsonx"
requires "sync"
