import Foundation

/// Documents as released versions of MetalCreator wrote them, kept as text so that a change to what is stored fails a test
/// instead of quietly dropping a person's picks. Each is the file the program wrote (re-spaced to fit the page; JSON ignores
/// white space), never one built by today's code.
enum LegacyDocuments {
    /// A Hole Pattern over a 3 x 2 Points to Placements on a plate and an Edges by Tag holding the pick of the rim of the hole at
    /// item 4, as master 9e5d2d5 (7a-2) wrote it: the copy's tag node is `NodeID.instanceScoped([holes, holes])`,
    /// 88C22DFA-1AF1-8F98-8C92-541F49C0DE7D.
    static let holePatternPickFormat6 = #"""
{"definitions":[],"formatVersion":6,"graph":{"links":[{"from":{"node":"415EDAF6-913F-4E5E-A0F0-9D01183EFBAC",
"socket":"profile"},"to":{"node":"0CFA9C58-3F4E-4946-A38A-387D63D646DB","socket":"profile"}},
{"from":{"node":"84748AB1-D3A6-41A6-B925-8E0C43329DDD","socket":"points"},"to":{"node":"340DB830-7B81-4839-9275-144B38A02EF0",
"socket":"points"}},{"from":{"node":"0CFA9C58-3F4E-4946-A38A-387D63D646DB","socket":"solid"},
"to":{"node":"BE74F986-C0CD-4693-B050-9DC2D4FB844C","socket":"part"}},{"from":{"node":"340DB830-7B81-4839-9275-144B38A02EF0",
"socket":"placements"},"to":{"node":"BE74F986-C0CD-4693-B050-9DC2D4FB844C","socket":"placements"}},
{"from":{"node":"BE74F986-C0CD-4693-B050-9DC2D4FB844C","socket":"solid"},"to":{"node":"458D6B94-4615-4BD7-9003-B35050F3E24D",
"socket":"solid"}}],"nodes":[{"id":"0CFA9C58-3F4E-4946-A38A-387D63D646DB","inputValues":{"distance":{"type":"number",
"value":6}},"isOutput":false,"name":"Extrude","position":{"x":0,"y":0},"typeID":"creator.extrude",
"typeVersion":1},{"id":"340DB830-7B81-4839-9275-144B38A02EF0","inputValues":{},
"isOutput":false,"name":"Points to Placements","position":{"x":0,"y":0},"typeID":"creator.pointsToPlacements",
"typeVersion":1},{"id":"415EDAF6-913F-4E5E-A0F0-9D01183EFBAC","inputValues":{"height":{"type":"number",
"value":40},"plane":{"type":"plane","value":{"normal":{"x":0,"y":0,"z":1},"origin":{"x":0,
"y":0,"z":-6},"xAxis":{"x":1,"y":0,"z":0}}},"width":{"type":"number","value":60}},
"isOutput":false,"name":"Rectangle","position":{"x":0,"y":0},"typeID":"creator.rectangle",
"typeVersion":1},{"id":"458D6B94-4615-4BD7-9003-B35050F3E24D","inputValues":{"picks":{"type":"edgePicks",
"value":[{"key":{"first":[{"item":0,"node":"0CFA9C58-3F4E-4946-A38A-387D63D646DB",
"role":{"role":"endCap"}}],"second":[{"item":4,"node":"88C22DFA-1AF1-8F98-8C92-541F49C0DE7D",
"role":{"role":"side","segment":1}}]},"matchCount":1}]}},"isOutput":false,"name":"Edges by Tag",
"position":{"x":0,"y":0},"typeID":"creator.edgesByTag","typeVersion":1},{"id":"84748AB1-D3A6-41A6-B925-8E0C43329DDD",
"inputValues":{"countX":{"type":"integer","value":3},"countY":{"type":"integer",
"value":2},"spacingX":{"type":"number","value":15},"spacingY":{"type":"number",
"value":15}},"isOutput":false,"name":"Grid Points","position":{"x":0,"y":0},"typeID":"creator.gridPoints",
"typeVersion":1},{"id":"BE74F986-C0CD-4693-B050-9DC2D4FB844C","inputValues":{"depth":{"type":"number",
"value":6},"diameter":{"type":"number","value":5}},"isOutput":false,"name":"Hole Pattern",
"position":{"x":0,"y":0},"typeID":"creator.holePattern","typeVersion":1}],"parameters":[]},
"viewState":{"canvasOffset":{"x":0,"y":0},"canvasZoom":1,"dock":"left","showsLibrary":true}}
"""#
}
