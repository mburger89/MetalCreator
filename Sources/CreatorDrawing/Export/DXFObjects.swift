import CreatorGeometry

/// The OBJECTS section, with the links AutoCAD needs (plan R24).
enum DXFObjects {
    private static func dictionary(
        _ t: inout DXFText, type: String = "DICTIONARY", handle: String, owner: String, entries: [(String, String)],
        isRoot: Bool = false
    ) {
        t.add(0, type)
        t.add(5, handle)
        if !isRoot {
            t.add(102, "{ACAD_REACTORS")
            t.add(330, owner)
            t.add(102, "}")
        }
        t.add(330, owner)
        t.add(100, "AcDbDictionary")
        t.add(281, 1)
        for (name, target) in entries {
            t.add(3, name)
            t.add(350, target)
        }
    }

    static func objects(_ s: DXFHandleSet, extent: Rect2D) -> DXFText {
        var t = DXFText()
        t.add(0, "SECTION")
        t.add(2, "OBJECTS")
        dictionary(
            &t, handle: s.root, owner: "0",
            entries: [
                ("ACAD_GROUP", s.groupDictionary), ("ACAD_LAYOUT", s.layoutDictionary),
                ("ACAD_MLINESTYLE", s.mlineDictionary), ("ACAD_PLOTSETTINGS", s.plotSettingsDictionary),
                ("ACAD_PLOTSTYLENAME", s.plotStyleDictionary),
            ], isRoot: true)
        dictionary(&t, handle: s.groupDictionary, owner: s.root, entries: [])
        dictionary(
            &t, handle: s.layoutDictionary, owner: s.root,
            entries: [("Layout1", s.paperLayout), ("Model", s.modelLayout)])
        dictionary(&t, handle: s.mlineDictionary, owner: s.root, entries: [("Standard", s.mlineStyle)])
        dictionary(&t, handle: s.plotSettingsDictionary, owner: s.root, entries: [])
        dictionary(
            &t, type: "ACDBDICTIONARYWDFLT", handle: s.plotStyleDictionary, owner: s.root,
            entries: [("Normal", s.placeholder)])
        t.add(100, "AcDbDictionaryWithDefault")
        t.add(340, s.placeholder)

        styleObjects(&t, s)

        let model = Space(handle: s.modelLayout, name: "Model", order: 0, record: s.modelRecord)
        let paper = Space(handle: s.paperLayout, name: "Layout1", order: 1, record: s.paperRecord)
        layout(&t, model, owner: s.layoutDictionary, extent: extent)
        layout(&t, paper, owner: s.layoutDictionary, extent: extent)
        t.add(0, "ENDSEC")
        return t
    }

    private static func styleObjects(_ t: inout DXFText, _ s: DXFHandleSet) {
        t.add(0, "MLINESTYLE")
        t.add(5, s.mlineStyle)
        t.add(102, "{ACAD_REACTORS")
        t.add(330, s.mlineDictionary)
        t.add(102, "}")
        t.add(330, s.mlineDictionary)
        t.add(100, "AcDbMlineStyle")
        t.add(2, "Standard")
        t.add(70, 0)
        t.add(3, "")
        t.add(62, 256)
        t.add(51, 90.0)
        t.add(52, 90.0)
        t.add(71, 2)
        for offset in [0.5, -0.5] {
            t.add(49, offset)
            t.add(62, 256)
            t.add(6, "BYLAYER")
        }

        t.add(0, "ACDBPLACEHOLDER")
        t.add(5, s.placeholder)
        t.add(102, "{ACAD_REACTORS")
        t.add(330, s.plotStyleDictionary)
        t.add(102, "}")
        t.add(330, s.plotStyleDictionary)
    }

    private struct Space {
        var handle: String
        var name: String
        var order: Int
        var record: String
    }

    private static func plotSettings(_ t: inout DXFText, extent: Rect2D) {
        t.add(100, "AcDbPlotSettings")
        t.add(1, "")
        t.add(2, "none_device")
        t.add(4, "")
        t.add(6, "")
        for code in [40, 41, 42, 43] { t.add(code, 0.0) }
        t.add(44, extent.width)
        t.add(45, extent.height)
        for code in [46, 47, 48, 49] { t.add(code, 0.0) }
        t.add(140, 0.0)
        t.add(141, 0.0)
        t.add(142, 1.0)
        t.add(143, 1.0)
        t.add(70, 688)
        t.add(72, 1)
        t.add(73, 0)
        t.add(74, 5)
        t.add(7, "")
        t.add(75, 16)
        t.add(147, 1.0)
        t.add(148, 0.0)
        t.add(149, 0.0)
    }

    private static func layout(_ t: inout DXFText, _ space: Space, owner: String, extent: Rect2D) {
        t.add(0, "LAYOUT")
        t.add(5, space.handle)
        t.add(102, "{ACAD_REACTORS")
        t.add(330, owner)
        t.add(102, "}")
        t.add(330, owner)
        plotSettings(&t, extent: extent)
        t.add(100, "AcDbLayout")
        t.add(1, space.name)
        t.add(70, 1)
        t.add(71, space.order)
        t.add(10, extent.min.x)
        t.add(20, extent.min.y)
        t.add(11, extent.max.x)
        t.add(21, extent.max.y)
        for code in [12, 22, 32] { t.add(code, 0.0) }
        t.add(14, extent.min.x)
        t.add(24, extent.min.y)
        t.add(34, 0.0)
        t.add(15, extent.max.x)
        t.add(25, extent.max.y)
        t.add(35, 0.0)
        t.add(146, 0.0)
        for code in [13, 23, 33] { t.add(code, 0.0) }
        for (code, value) in [(16, 1.0), (26, 0.0), (36, 0.0), (17, 0.0), (27, 1.0), (37, 0.0)] { t.add(code, value) }
        t.add(76, 0)
        t.add(330, space.record)
    }
}
