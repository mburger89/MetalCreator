import CreatorDrawing
import MetalUI

/// The inspector for one feature control frame (DR-4 R15): the characteristic, then per row only what that characteristic takes
/// (R7), the datum references, Composite where allowed, the rule warnings, a lost reason and Delete.
struct FrameInspector: Component {
    let model: DrawingEditorModel
    let id: AnnotationID
    let frame: FeatureControlFrame
    let report: AnnotationReport?
    let colors: DrawingColors

    static let materialOptions = ["None", "Maximum (M)", "Least (L)"]
    static let zoneOptions = ["Width", "Ø"]
    static let offOn = ["No", "Yes"]

    /// The characteristics the menu lists: all, except concentricity and symmetry under ASME unless the frame already has it.
    static func characteristicOptions(current: GeometricCharacteristic, standard: DrawingStandard) -> [GeometricCharacteristic] {
        GeometricCharacteristic.allCases.filter { standard != .asme || $0.isInASME || $0 == current }
    }

    static func materialIndex(_ material: MaterialCondition?) -> Int {
        switch material {
        case nil: 0
        case .maximum?: 1
        case .least?: 2
        }
    }

    static func material(at index: Int) -> MaterialCondition? {
        switch index {
        case 1: .maximum
        case 2: .least
        default: nil
        }
    }

    var content: some ElementGroup {
        let options = Self.characteristicOptions(current: frame.characteristic, standard: model.document.settings.standard)
        VStack(alignment: .leading, spacing: Pixels(8)) {
            Text("Tolerance frame").font(.headline).foregroundStyle(colors.primary.color)
            DrawingRow("Characteristic", colors: colors) {
                DrawingMenu(options: options.map(\.title), selected: options.firstIndex(of: frame.characteristic)) {
                    model.setCharacteristic(options[$0], of: id)
                }
            }
            ForEach(frame.rows.indices, id: \.self) { index in
                FrameRowControls(model: model, id: id, frame: frame, index: index, colors: colors)
            }
            if frame.characteristic.allowsComposite {
                DrawingRow("Composite", colors: colors) {
                    DrawingSegments(options: Self.offOn, selected: frame.isComposite ? 1 : 0) {
                        model.setComposite($0 == 1, of: id)
                    }
                }
            }
            SymbolPageTail(model: model, attachment: frame.attachment, report: report, colors: colors)
        }
        .frame(width: drawingInspectorWidth.px)
    }
}

/// One row of a frame: the zone, the value, the modifiers its characteristic takes and its datum references.
struct FrameRowControls: Component {
    let model: DrawingEditorModel
    let id: AnnotationID
    let frame: FeatureControlFrame
    let index: Int
    let colors: DrawingColors

    private var row: ToleranceRow { frame.rows[index] }
    private var characteristic: GeometricCharacteristic { frame.characteristic }
    private var format: NumberFormat { NumberFormat(units: model.units, settings: model.document.settings) }

    /// The datum rows shown: a form tolerance takes none, unless it holds some to remove.
    private var datumRows: Int {
        if characteristic.family == .form, row.datums.isEmpty { return 0 }
        return Swift.min(row.datums.count + 1, FrameInspector.maximumDatums)
    }

    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: Pixels(8)) {
            if frame.isComposite {
                Text(index == 0 ? "UPPER ROW" : "LOWER ROW").font(.caption2).foregroundStyle(colors.secondary.color)
            }
            if characteristic.takesDiameterZone {
                DrawingRow("Zone", colors: colors) {
                    DrawingSegments(options: FrameInspector.zoneOptions, selected: row.zone == .diameter ? 1 : 0) {
                        model.setZone($0 == 1 ? .diameter : .width, row: index, of: id)
                    }
                }
            }
            DrawingRow("Tolerance", colors: colors) {
                DrawingField(model: model, text: GDTNumber.tolerance(row.value, format: format), width: 90) {
                    model.setToleranceValue(text: $0, row: index, of: id)
                }
            }
            if characteristic.takesMaterialCondition {
                DrawingRow("Material", colors: colors) {
                    DrawingMenu(options: FrameInspector.materialOptions, selected: FrameInspector.materialIndex(row.material)) {
                        model.setMaterialCondition(FrameInspector.material(at: $0), row: index, of: id)
                    }
                }
            }
            DrawingRow("Free state", colors: colors) {
                DrawingSegments(options: FrameInspector.offOn, selected: row.freeState ? 1 : 0) {
                    model.setFreeState($0 == 1, row: index, of: id)
                }
            }
            if characteristic.takesTangentPlane {
                DrawingRow("Tangent plane", colors: colors) {
                    DrawingSegments(options: FrameInspector.offOn, selected: row.tangentPlane ? 1 : 0) {
                        model.setTangentPlane($0 == 1, row: index, of: id)
                    }
                }
            }
            if characteristic.takesProjectedZone { projected }
            ForEach(0..<datumRows, id: \.self) { slot in datumRow(slot) }
        }
    }

    @ElementBuilder
    private var projected: some ElementGroup {
        let length = row.projected?.length.map { GDTNumber.tolerance($0, format: format) } ?? ""
        DrawingRow("Projected", colors: colors) {
            DrawingSegments(options: FrameInspector.offOn, selected: row.projected == nil ? 0 : 1) {
                model.setProjectedZone($0 == 1, lengthText: length, row: index, of: id)
            }
        }
        if row.projected != nil {
            DrawingRow("Length", colors: colors) {
                DrawingField(model: model, text: length, width: 90) {
                    model.setProjectedZone(true, lengthText: $0, row: index, of: id)
                }
            }
        }
    }

    private func datumRow(_ slot: Int) -> some ElementGroup {
        let reference = slot < row.datums.count ? row.datums[slot] : nil
        return DrawingRow("Datum \(slot + 1)", colors: colors) {
            HStack(spacing: Pixels(6)) {
                DrawingField(model: model, text: reference?.letter ?? "", width: 60) {
                    model.setDatum(slot, letterText: $0, material: reference?.material, row: index, of: id)
                }
                if let reference {
                    DrawingMenu(options: FrameInspector.materialOptions, selected: FrameInspector.materialIndex(reference.material)) {
                        model.setDatum(
                            slot, letterText: reference.letter, material: FrameInspector.material(at: $0), row: index, of: id)
                    }
                }
            }
        }
    }
}

extension FrameInspector {
    /// A frame takes at most three datum references.
    static let maximumDatums = 3
}
