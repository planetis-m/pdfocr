version       = "0.2.3"
author        = "planetis"
description   = "High-throughput PDF OCR extractor"
license       = "MIT"
srcDir        = "src"
bin           = @["app"]

requires "nim >= 2.2.8"
requires "https://github.com/planetis-m/mimalloc_nim"
requires "https://github.com/planetis-m/jsonx"
requires "https://github.com/planetis-m/relay"
requires "https://github.com/planetis-m/openai"
