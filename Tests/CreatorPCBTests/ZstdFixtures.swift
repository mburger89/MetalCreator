/// Frames made by `zstd` 1.5.7 (Homebrew); write each input to a file (`ZstdFixtureInputs`), then
///   tiny        zstd -19 tiny.bin                         (the 11 bytes of `ZstdFixtureInputs.tiny`)
///   repetitive  zstd -3 repetitive.bin                    (`ZstdFixtureInputs.repetitive`)
///   text1       zstd -1 text.bin                          (`text(seed: 1, size: 20_000)`)
///   nocheck     zstd --no-check -9 text.bin               (the same text, no content checksum)
///   fast        zstd --fast=3 text.bin                    (the same text, a negative level)
///   same        zstd -3 same.bin                          (`same(0x41, count: 200_000)`, run-length blocks)
///   samestdin   cat same.bin | zstd -c -3                 (the same bytes, content size not stated)
///   empty       zstd -c empty.bin                         (no bytes at all)
///   small       zstd -19 small.bin                        (`text(seed: 9, size: 3_000)`, the mutation tests' frame)
///   onestream   zstd -1 in.bin                            (`mixed(seed: 0, size: 160)`: Huffman literals in one stream)
///   fourstream  zstd -1 in.bin                            (`mixed(seed: 0, size: 400)`: four streams)
///   rleoffsets  zstd -1 in.bin                            (`text(seed: 28, size: 300)`: a run-length offsets table)
///   repeatmix   zstd -19 in.bin                           (`mixed(seed: 0, size: 1_200)`)
///   direct      zstd -1 direct.bin                        (`directPlain`: the Huffman weights stored directly)
///   mixed300    zstd -19 mixed300.bin                     (`mixed(seed: 2, size: 300_000)`, in its own file)
///   mixed120    zstd --ultra -22 --long=27 mixed120.bin   (`mixed(seed: 3, size: 120_000)`, in its own file)
/// Each is stored as base64 (`base64 -i frame.zst`).
enum ZstdFixtures {}
