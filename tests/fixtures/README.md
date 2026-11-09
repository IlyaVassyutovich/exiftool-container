# Test fixtures

Inputs for `tests/smoke.sh`. Both files are original work, released under the repository license.

- `pixel.jpg`: an 8x8 white JPEG with no metadata. Generated on Windows with .NET
  `System.Drawing.Bitmap` (cleared to white, saved with `ImageFormat::Jpeg`).
- `sample.docx`: a minimal OOXML zip holding only `[Content_Types].xml` (declaring the
  `core-properties` override for `/docProps/core.xml`) and `docProps/core.xml` with
  `<dc:creator>smoke-fixture</dc:creator>`. Zipped with PowerShell `Compress-Archive -LiteralPath`
  (`[` is a wildcard for `-Path`), then renamed from `.zip`.
