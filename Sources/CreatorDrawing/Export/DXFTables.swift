import CreatorGeometry

/// An ASCII DXF under construction: group code and value lines, LF line ends, numbers written by `PDFNumber` (plan R24).
struct DXFText {
    private(set) var text = ""

    mutating func add(_ code: Int, _ value: String) {
        let digits = String(code)
        text += String(repeating: " ", count: Swift.max(0, 3 - digits.count)) + digits + "\n" + value + "\n"
    }

    mutating func add(_ code: Int, _ value: Int) { add(code, String(value)) }

    mutating func add(_ code: Int, _ value: Double, decimals: Int = 6) {
        add(code, PDFNumber.format(value, decimals: decimals))
    }

    mutating func add(_ other: DXFText) { text += other.text }
}

/// Hands out handles in order from 0x20 (plan R24).
struct DXFHandles {
    private var next = 0x20

    mutating func make() -> String {
        defer { next += 1 }
        return String(next, radix: 16, uppercase: true)
    }

    /// One past the largest handle made, for `$HANDSEED`.
    var seed: String { String(next, radix: 16, uppercase: true) }
}

/// Every handle of the fixed parts of a file: its tables, the two spaces, and the objects.
struct DXFHandleSet {
    var vportTable, ltypeTable, layerTable, styleTable, viewTable, ucsTable, appidTable, dimstyleTable, blockRecordTable: String
    var activeViewport, styleStandard, appidACAD, dimstyleStandard: String
    var lineTypes: [String]
    var layers: [String]
    var modelRecord, paperRecord, modelBlock, modelEnd, paperBlock, paperEnd: String
    var root, groupDictionary, layoutDictionary, mlineDictionary, plotSettingsDictionary, plotStyleDictionary: String
    var mlineStyle, placeholder, modelLayout, paperLayout: String

    init(_ h: inout DXFHandles) {
        vportTable = h.make()
        ltypeTable = h.make()
        layerTable = h.make()
        styleTable = h.make()
        viewTable = h.make()
        ucsTable = h.make()
        appidTable = h.make()
        dimstyleTable = h.make()
        blockRecordTable = h.make()
        activeViewport = h.make()
        lineTypes = (0..<DXFTables.lineTypes.count).map { _ in h.make() }
        layers = (0..<DXFTables.layerNames.count).map { _ in h.make() }
        styleStandard = h.make()
        appidACAD = h.make()
        dimstyleStandard = h.make()
        modelRecord = h.make()
        paperRecord = h.make()
        modelBlock = h.make()
        modelEnd = h.make()
        paperBlock = h.make()
        paperEnd = h.make()
        root = h.make()
        groupDictionary = h.make()
        layoutDictionary = h.make()
        mlineDictionary = h.make()
        plotSettingsDictionary = h.make()
        plotStyleDictionary = h.make()
        mlineStyle = h.make()
        placeholder = h.make()
        modelLayout = h.make()
        paperLayout = h.make()
    }
}

/// The fixed sections of a DXF (plan R24): header, tables, blocks and objects.
enum DXFTables {
    struct LineType {
        var name: String
        var description: String
        var elements: [Double]
    }

    static let layerNames = ["0"] + DrawingLayer.allCases.map(\.rawValue)

    /// The lineweights AutoCAD allows, in 1/100 mm.
    private static let allowedWeights = [
        0, 5, 9, 13, 15, 18, 20, 25, 30, 35, 40, 50, 53, 60, 70, 80, 90, 100, 106, 120, 140, 158, 200, 211,
    ]

    /// The nearest lineweight AutoCAD allows to `width` millimetres.
    static func lineweight(_ width: Double) -> Int {
        guard width.isFinite else { return 25 }
        let hundredths = (width * 100).rounded()
        return allowedWeights.min { abs(Double($0) - hundredths) < abs(Double($1) - hundredths) } ?? 25
    }

    static func lineTypeName(of layer: String) -> String {
        switch layer {
        case DrawingLayer.hidden.rawValue: "DASHED"
        case DrawingLayer.center.rawValue: "CENTER"
        default: "Continuous"
        }
    }

    static func layerWeight(_ name: String, style: DrawingStyle) -> Int {
        switch name {
        case DrawingLayer.visible.rawValue: lineweight(style.thick)
        case DrawingLayer.frame.rawValue: lineweight(style.frame)
        default: lineweight(style.thin)
        }
    }

    static var lineTypes: [LineType] { lineTypes(style: .iso) }

    static func lineTypes(style: DrawingStyle) -> [LineType] {
        [
            LineType(name: "ByBlock", description: "", elements: []),
            LineType(name: "ByLayer", description: "", elements: []),
            LineType(name: "Continuous", description: "Solid line", elements: []),
            LineType(name: "DASHED", description: "Dashed", elements: [style.hiddenDash, -style.hiddenGap]),
            LineType(name: "CENTER", description: "Center", elements: [6, -0.75, 0, -0.75]),
        ]
    }

    // MARK: Header

    static func header(seed: String, extent: Rect2D) -> DXFText {
        var t = DXFText()
        t.add(0, "SECTION")
        t.add(2, "HEADER")
        t.add(9, "$ACADVER")
        t.add(1, "AC1015")
        t.add(9, "$HANDSEED")
        t.add(5, seed)
        t.add(9, "$DWGCODEPAGE")
        t.add(3, "ANSI_1252")
        t.add(9, "$INSUNITS")
        t.add(70, 4)
        t.add(9, "$MEASUREMENT")
        t.add(70, 1)
        t.add(9, "$LTSCALE")
        t.add(40, 1.0)
        t.add(9, "$EXTMIN")
        point(&t, extent.min)
        t.add(9, "$EXTMAX")
        point(&t, extent.max)
        t.add(9, "$LIMMIN")
        t.add(10, extent.min.x)
        t.add(20, extent.min.y)
        t.add(9, "$LIMMAX")
        t.add(10, extent.max.x)
        t.add(20, extent.max.y)
        t.add(0, "ENDSEC")
        return t
    }

    static var classes: DXFText {
        var t = DXFText()
        t.add(0, "SECTION")
        t.add(2, "CLASSES")
        t.add(0, "ENDSEC")
        return t
    }

    private static func point(_ t: inout DXFText, _ p: Vector2) {
        t.add(10, p.x)
        t.add(20, p.y)
        t.add(30, 0.0)
    }

    // MARK: Tables

    private static func tableStart(_ t: inout DXFText, _ name: String, handle: String, count: Int) {
        t.add(0, "TABLE")
        t.add(2, name)
        t.add(5, handle)
        t.add(330, "0")
        t.add(100, "AcDbSymbolTable")
        t.add(70, count)
    }

    private static func record(_ t: inout DXFText, _ type: String, handle: String, owner: String, marker: String) {
        t.add(0, type)
        t.add(5, handle)
        t.add(330, owner)
        t.add(100, "AcDbSymbolTableRecord")
        t.add(100, marker)
    }

    static func tables(_ s: DXFHandleSet, style: DrawingStyle, extent: Rect2D) -> DXFText {
        var t = DXFText()
        t.add(0, "SECTION")
        t.add(2, "TABLES")
        viewport(&t, s, extent: extent)
        lineTypeTable(&t, s, style: style)
        layerTable(&t, s, style: style)
        styleTable(&t, s)
        smallTables(&t, s)
        dimStyleTable(&t, s)
        blockRecords(&t, s)
        t.add(0, "ENDSEC")
        return t
    }

    private static func viewport(_ t: inout DXFText, _ s: DXFHandleSet, extent: Rect2D) {
tableStart(&t, "VPORT", handle: s.vportTable, count: 1)
        record(&t, "VPORT", handle: s.activeViewport, owner: s.vportTable, marker: "AcDbViewportTableRecord")
        t.add(2, "*Active")
        t.add(70, 0)
        for (code, value) in [(10, 0.0), (20, 0.0), (11, 1.0), (21, 1.0)] { t.add(code, value) }
        t.add(12, extent.center.x)
        t.add(22, extent.center.y)
        for (code, value) in [(13, 0.0), (23, 0.0), (14, 10.0), (24, 10.0), (15, 0.0), (25, 0.0), (16, 0.0), (26, 0.0), (36, 1.0)] {
            t.add(code, value)
        }
        for (code, value) in [(17, 0.0), (27, 0.0), (37, 0.0)] { t.add(code, value) }
        t.add(40, Swift.max(extent.height, 1))
        t.add(41, 1.5)
        t.add(42, 50.0)
        t.add(43, 0.0)
        t.add(44, 0.0)
        t.add(50, 0.0)
        t.add(51, 0.0)
        for (code, value) in [(71, 0), (72, 100), (73, 1), (74, 3), (75, 0), (76, 0), (77, 0), (78, 0)] { t.add(code, value) }
        t.add(0, "ENDTAB")
    }

    private static func lineTypeTable(_ t: inout DXFText, _ s: DXFHandleSet, style: DrawingStyle) {
let types = lineTypes(style: style)
        tableStart(&t, "LTYPE", handle: s.ltypeTable, count: types.count)
        for (index, type) in types.enumerated() {
            record(&t, "LTYPE", handle: s.lineTypes[index], owner: s.ltypeTable, marker: "AcDbLinetypeTableRecord")
            t.add(2, type.name)
            t.add(70, 0)
            t.add(3, type.description)
            t.add(72, 65)
            t.add(73, type.elements.count)
            t.add(40, type.elements.reduce(0) { $0 + abs($1) })
            for element in type.elements {
                t.add(49, element)
                t.add(74, 0)
            }
        }
        t.add(0, "ENDTAB")
    }

    private static func layerTable(_ t: inout DXFText, _ s: DXFHandleSet, style: DrawingStyle) {
tableStart(&t, "LAYER", handle: s.layerTable, count: layerNames.count)
        for (index, name) in layerNames.enumerated() {
            record(&t, "LAYER", handle: s.layers[index], owner: s.layerTable, marker: "AcDbLayerTableRecord")
            t.add(2, name)
            t.add(70, 0)
            t.add(62, 7)
            t.add(6, lineTypeName(of: name))
            t.add(370, layerWeight(name, style: style))
            t.add(390, s.placeholder)
        }
        t.add(0, "ENDTAB")
    }

    private static func styleTable(_ t: inout DXFText, _ s: DXFHandleSet) {
tableStart(&t, "STYLE", handle: s.styleTable, count: 1)
        record(&t, "STYLE", handle: s.styleStandard, owner: s.styleTable, marker: "AcDbTextStyleTableRecord")
        t.add(2, "Standard")
        t.add(70, 0)
        t.add(40, 0.0)
        t.add(41, 1.0)
        t.add(50, 0.0)
        t.add(71, 0)
        t.add(42, 2.5)
        t.add(3, "txt")
        t.add(4, "")
        t.add(0, "ENDTAB")
    }

    private static func smallTables(_ t: inout DXFText, _ s: DXFHandleSet) {
tableStart(&t, "VIEW", handle: s.viewTable, count: 0)
        t.add(0, "ENDTAB")
        tableStart(&t, "UCS", handle: s.ucsTable, count: 0)
        t.add(0, "ENDTAB")

        tableStart(&t, "APPID", handle: s.appidTable, count: 1)
        record(&t, "APPID", handle: s.appidACAD, owner: s.appidTable, marker: "AcDbRegAppTableRecord")
        t.add(2, "ACAD")
        t.add(70, 0)
        t.add(0, "ENDTAB")
    }

    private static func dimStyleTable(_ t: inout DXFText, _ s: DXFHandleSet) {
tableStart(&t, "DIMSTYLE", handle: s.dimstyleTable, count: 1)
        t.add(100, "AcDbDimStyleTable")
        t.add(71, 1)
        t.add(0, "DIMSTYLE")
        t.add(105, s.dimstyleStandard)
        t.add(330, s.dimstyleTable)
        t.add(100, "AcDbSymbolTableRecord")
        t.add(100, "AcDbDimStyleTableRecord")
        t.add(2, "Standard")
        t.add(70, 0)
        for (code, value) in [(40, 1.0), (41, 2.5), (42, 0.625), (43, 3.75), (44, 1.25), (140, 2.5), (141, 2.5), (147, 0.625)] {
            t.add(code, value)
        }
        for (code, value) in [(77, 1), (78, 8), (171, 3), (172, 1), (271, 2), (272, 2), (278, 44), (279, 0), (280, 0)] {
            t.add(code, value)
        }
        t.add(340, s.styleStandard)
        t.add(0, "ENDTAB")
    }

    private static func blockRecords(_ t: inout DXFText, _ s: DXFHandleSet) {
tableStart(&t, "BLOCK_RECORD", handle: s.blockRecordTable, count: 2)
        record(&t, "BLOCK_RECORD", handle: s.modelRecord, owner: s.blockRecordTable, marker: "AcDbBlockTableRecord")
        t.add(2, "*Model_Space")
        t.add(340, s.modelLayout)
        record(&t, "BLOCK_RECORD", handle: s.paperRecord, owner: s.blockRecordTable, marker: "AcDbBlockTableRecord")
        t.add(2, "*Paper_Space")
        t.add(340, s.paperLayout)
        t.add(0, "ENDTAB")
    }

    // MARK: Blocks

    static func blocks(_ s: DXFHandleSet) -> DXFText {
        var t = DXFText()
        t.add(0, "SECTION")
        t.add(2, "BLOCKS")
        for (name, record, begin, end, paper) in [
            ("*Model_Space", s.modelRecord, s.modelBlock, s.modelEnd, false),
            ("*Paper_Space", s.paperRecord, s.paperBlock, s.paperEnd, true),
        ] {
            t.add(0, "BLOCK")
            t.add(5, begin)
            t.add(330, record)
            if paper { t.add(67, 1) }
            t.add(100, "AcDbEntity")
            t.add(8, "0")
            t.add(100, "AcDbBlockBegin")
            t.add(2, name)
            t.add(70, 0)
            t.add(10, 0.0)
            t.add(20, 0.0)
            t.add(30, 0.0)
            t.add(3, name)
            t.add(1, "")
            t.add(0, "ENDBLK")
            t.add(5, end)
            t.add(330, record)
            if paper { t.add(67, 1) }
            t.add(100, "AcDbEntity")
            t.add(8, "0")
            t.add(100, "AcDbBlockEnd")
        }
        t.add(0, "ENDSEC")
        return t
    }
}
