import Foundation

/// A deflated 3MF made outside Swift, pinned as base64 so every platform reads the same bytes: one tetrahedron with fractional
/// coordinates (`0.1`, `10.37`, `3.3333333`, `-0.77`, ...) under a build item whose transform turns it about z (a 3-4-5 rotation)
/// and moves it. Python's `zipfile` with `ZIP_DEFLATED` at level 9 and 1980-01-01 dates made it from `_rels/.rels` (the usual one
/// relationship to `/3D/3dmodel.model`) and a `3dmodel.model` of one object with four `<vertex>` and four `<triangle>` elements and
/// `<item objectid="1" transform="0.8 0.6 0 -0.6 0.8 0 0 0 1 1.5 2.25 -3.125"/>`. Unlike `ThreeMFFixtures` (stored), reading it goes
/// through `Inflate`, the float parsing of fractions and the transform's arithmetic.
enum DeflatedThreeMF {
    static let package = Data(base64Encoded: [
        "UEsDBBQAAAAIAAAAIQCr9/5HrgAAAAIBAAALAAAAX3JlbHMvLnJlbHNlj8kKwjAQhl8lzN1Ma0FEmvYiglepDxCS6YLNQpKKvr1R",
        "ECxeBoaZ71/q9mFmdqcQJ2cFlLwARlY5PdlBwLU7bfbQNvWFZpnyRxwnH1lGbBQwpuQPiFGNZGTkzpPNl94FI1New4BeqpscCLdF",
        "scPwqwFrTdbJMFASgNURK22cppl/JrCzFpDZHKx7evqzNZMKLro+ceXMm5V26aVKS8gVsnNZYVF+NQGbGldlmhdQSwMEFAAAAAgA",
        "AAAhAFh9G9dEAQAAbwIAABAAAAAzRC8zZG1vZGVsLm1vZGVsbZHdcoMgEIXv+xQ73MtvjKaj5q5P0D6AQdLQEckAOkmfvqB2aiaV",
        "i108H7uHpTreTA+Tcl7boUYMUwRqkLbTw2eNPt7fshIdm5fK2E71MA461MjovtdGBeUQxNODr9ElhOsrIV5elGk9Nlo66+05YGkN",
        "EZ1ph/HcyjC6WJZI6xThlOWEctRUTnk7Oql8U9nTl5IBdBedIAj3q4rdUueIGeUvTRWdBj2zKVM3uNWI4gjfU+QIvlMUiGwBFv8U",
        "K0IZFzOVUVwUj5zAYvlm9oDLYp/v1pL5I7pbewpczECJ2SER5M9gcLodPvttChOLtRBMvEbR6yTSPcn/Olt08aSzh/PPOl90utHJ",
        "xgtZBkmWWcdkM//TqPuuqXRQBhb99ylcO/izdSaNogSK90Ahm0PazosBwzlwzHPIBGZ8nhhZS5L5GZsfUEsBAhQDFAAAAAgAAAAh",
        "AKv3/keuAAAAAgEAAAsAAAAAAAAAAAAAAIABAAAAAF9yZWxzLy5yZWxzUEsBAhQDFAAAAAgAAAAhAFh9G9dEAQAAbwIAABAAAAAA",
        "AAAAAAAAAIAB1wAAADNELzNkbW9kZWwubW9kZWxQSwUGAAAAAAIAAgB3AAAASQIAAAAA",
    ].joined()) ?? Data()
}
