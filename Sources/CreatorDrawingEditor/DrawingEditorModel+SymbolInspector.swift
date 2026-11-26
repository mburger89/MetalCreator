import CreatorDrawing
import CreatorGeometry

/// The inspector's setters for datum, frame and surface symbols (DR-4 R15): each is one named step, refuses in words, and
/// commits nothing when the value is the one the symbol already has.
extension DrawingEditorModel {
    static let datumLetterSentence = "A datum letter is one or two capitals from A to Z, without I, O or Q."
    static let toleranceValueSentence = "A tolerance is a number greater than 0, such as 0.05."
    static let projectedLengthSentence = "A projected zone's length is a length greater than 0."
    static let roughnessSentence = "A roughness value is a number greater than 0, such as 1.6."
    static let threeDatumsSentence = "A frame takes at most three datum references."
    static let compositeSentence = "Only position and profile frames can be composite."
    static let standingSentence = "A surface symbol stands only on a horizontal line, with the symbol above it."
    static let asmeCharacteristicSentence = "ASME Y14.5-2018 has no concentricity or symmetry symbol."
    static let mismatchedKindSentence =
        "A dimension keeps its kind of measure; delete it and dimension again to measure something else."
    static let symbolBlocksKindSentence =
        "A datum symbol hangs on this diameter, and a radius can't carry one; delete the datum symbol first."
    static let maximumDatums = 3
    private static let defaultRoughness = 3.2

    // MARK: Datum

    public func setDatumLetter(_ text: String, of id: AnnotationID) {
        guard case .datumFeature(var datum)? = sheet?.annotation(id)?.kind else { return }
        guard let letter = DatumLetters.normalized(text) else { return refuse(Self.datumLetterSentence) }
        datum.letter = letter
        store(.datumFeature(datum), of: id, as: DrawingStepName.changeDatumLetter)
    }

    // MARK: Frame

    public func setCharacteristic(_ characteristic: GeometricCharacteristic, of id: AnnotationID) {
        changeFrame(id) { frame in
            guard characteristic != frame.characteristic else { return nil }
            if !characteristic.isInASME, document.settings.standard == .asme { return Self.asmeCharacteristicSentence }
            frame.characteristic = characteristic
            if !characteristic.allowsComposite { frame.rows = Array(frame.rows.prefix(1)) }
            for index in frame.rows.indices {
                if !characteristic.takesDiameterZone { frame.rows[index].zone = .width }
                if !characteristic.takesMaterialCondition { frame.rows[index].material = nil }
                if !characteristic.takesTangentPlane { frame.rows[index].tangentPlane = false }
                if !characteristic.takesProjectedZone { frame.rows[index].projected = nil }
            }
            return nil
        }
    }

    public func setZone(_ zone: ToleranceZone, row: Int, of id: AnnotationID) {
        changeRow(row, of: id) { frame, index in
            if zone == .diameter, !frame.characteristic.takesDiameterZone {
                return "\(frame.characteristic.title) takes no diameter zone."
            }
            frame.rows[index].zone = zone
            return nil
        }
    }

    public func setToleranceValue(text: String, row: Int, of id: AnnotationID) {
        changeRow(row, of: id) { frame, index in
            guard let value = lengthValue(text), value > 0 else { return Self.toleranceValueSentence }
            frame.rows[index].value = value
            return nil
        }
    }

    public func setMaterialCondition(_ material: MaterialCondition?, row: Int, of id: AnnotationID) {
        changeRow(row, of: id) { frame, index in
            if material != nil, !frame.characteristic.takesMaterialCondition {
                return "\(frame.characteristic.title) takes no material condition."
            }
            frame.rows[index].material = material
            return nil
        }
    }

    public func setFreeState(_ isOn: Bool, row: Int, of id: AnnotationID) {
        changeRow(row, of: id) { frame, index in
            frame.rows[index].freeState = isOn
            return nil
        }
    }

    public func setTangentPlane(_ isOn: Bool, row: Int, of id: AnnotationID) {
        changeRow(row, of: id) { frame, index in
            if isOn, !frame.characteristic.takesTangentPlane { return "\(frame.characteristic.title) takes no tangent plane." }
            frame.rows[index].tangentPlane = isOn
            return nil
        }
    }

    /// Ⓟ on or off; an empty length states none.
    public func setProjectedZone(_ isOn: Bool, lengthText: String, row: Int, of id: AnnotationID) {
        changeRow(row, of: id) { frame, index in
            guard isOn else {
                frame.rows[index].projected = nil
                return nil
            }
            if !frame.characteristic.takesProjectedZone { return "\(frame.characteristic.title) takes no projected zone." }
            if lengthText.allSatisfy(\.isWhitespace) {
                frame.rows[index].projected = ProjectedZone(length: nil)
            } else if let length = lengthValue(lengthText), length > 0 {
                frame.rows[index].projected = ProjectedZone(length: length)
            } else {
                return Self.projectedLengthSentence
            }
            return nil
        }
    }

    /// Datum reference `index` (0 to 2) of a row; empty text removes it and the ones after it.
    public func setDatum(_ index: Int, letterText: String, material: MaterialCondition?, row: Int, of id: AnnotationID) {
        changeRow(row, of: id) { frame, rowIndex in
            let count = frame.rows[rowIndex].datums.count
            guard index >= 0, index <= count else { return nil }
            if letterText.allSatisfy(\.isWhitespace) {
                if index < count { frame.rows[rowIndex].datums.removeSubrange(index...) }
                return nil
            }
            guard index < Self.maximumDatums else { return Self.threeDatumsSentence }
            guard let letter = DatumLetters.normalized(letterText) else { return Self.datumLetterSentence }
            let reference = DatumReference(letter: letter, material: material)
            if index < count {
                frame.rows[rowIndex].datums[index] = reference
            } else {
                frame.rows[rowIndex].datums.append(reference)
            }
            return nil
        }
    }

    /// A composite frame's second row starts as a copy of the first.
    public func setComposite(_ isOn: Bool, of id: AnnotationID) {
        changeFrame(id) { frame in
            if isOn {
                guard frame.characteristic.allowsComposite else { return Self.compositeSentence }
                if frame.rows.count == 1 { frame.rows.append(frame.rows[0]) }
            } else {
                frame.rows = Array(frame.rows.prefix(1))
            }
            return nil
        }
    }

    private func changeRow(
        _ row: Int, of id: AnnotationID, _ change: (inout FeatureControlFrame, Int) -> String?
    ) {
        changeFrame(id) { frame in
            guard frame.rows.indices.contains(row) else { return nil }
            return change(&frame, row)
        }
    }

    /// Applies `change` to a frame; a returned sentence refuses and commits nothing. An accepted change feeds the next new frame.
    private func changeFrame(_ id: AnnotationID, _ change: (inout FeatureControlFrame) -> String?) {
        guard case .featureControl(let current)? = sheet?.annotation(id)?.kind else { return }
        var frame = current
        if let sentence = change(&frame) { return refuse(sentence) }
        frameTemplate = frame
        store(.featureControl(frame), of: id, as: DrawingStepName.changeFeatureControlFrame)
    }

    // MARK: Surface

    public func setSurfaceProcess(_ process: SurfaceProcess, of id: AnnotationID) {
        changeSurface(id) { $0.requirement.process = process; return nil }
    }

    /// The parameter and its value, typed in µm (µin in an inch document); a parameter with no value keeps the previous or 3.2.
    public func setRoughness(parameter: RoughnessParameter?, valueText: String, of id: AnnotationID) {
        changeSurface(id) { texture in
            guard let parameter else {
                texture.requirement.parameter = nil
                texture.requirement.value = nil
                return nil
            }
            if valueText.allSatisfy(\.isWhitespace) {
                texture.requirement.value = texture.requirement.value ?? Self.defaultRoughness
            } else if let value = roughness(valueText) {
                texture.requirement.value = value
            } else {
                return Self.roughnessSentence
            }
            texture.requirement.parameter = parameter
            return nil
        }
    }

    public func setLay(_ lay: SurfaceLay?, of id: AnnotationID) {
        changeSurface(id) { $0.lay = lay; return nil }
    }

    /// Standing needs a line that is horizontal on the sheet (R6); leaving it puts the symbol on its default leader.
    public func setSurfaceStands(_ stands: Bool, of id: AnnotationID) {
        guard case .surfaceTexture(let current)? = sheet?.annotation(id)?.kind, (current.offset == nil) != stands else { return }
        changeSurface(id) { texture in
            if stands {
                guard isHorizontal(texture.feature, in: id) else { return Self.standingSentence }
                texture.offset = nil
            } else if let sheet {
                let style = SymbolStyle.of(document.settings.standard)
                texture.offset = style.defaultSurfaceOffset * DrawingStyle.of(document.settings.standard).notesHeight(for: sheet.size)
            }
            return nil
        }
    }

    private func changeSurface(_ id: AnnotationID, _ change: (inout SurfaceTexture) -> String?) {
        guard case .surfaceTexture(let current)? = sheet?.annotation(id)?.kind else { return }
        var texture = current
        if let sentence = change(&texture) { return refuse(sentence) }
        surfaceTemplate = texture
        store(.surfaceTexture(texture), of: id, as: DrawingStepName.changeSurfaceSymbol)
    }

    /// Whether the line a symbol stands on runs horizontally on the sheet.
    private func isHorizontal(_ end: LeaderEnd, in id: AnnotationID) -> Bool {
        guard let view = sheet?.annotation(id)?.view, case .success(let context) = pickContext(of: view),
            case .held(let geometry, _, _) = DrawingAnchorResolver.resolve(end.target, in: context.topology, frame: context.frame),
            case .success(let found) = SymbolFoot.of(geometry, hint: end.hint, frame: context.frame),
            found.along.length > 1e-12 else { return false }
        return Swift.abs(found.along.y) <= 1e-9 * found.along.length
    }

    /// A length from what was typed, in millimetres: the fields show the document's decimal sign, so a comma is a point.
    func lengthValue(_ text: String) -> Double? {
        units.parse(text.replacingOccurrences(of: ",", with: "."), quantity: .length)
    }

    /// Micrometres from what was typed: µm in a millimetre document, µin in an inch one; a comma is a point.
    func roughness(_ text: String) -> Double? {
        let typed = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(typed), value.isFinite, value > 0 else { return nil }
        return standardUnitsAreInches ? value * GDTNumber.micrometresPerMicroinch : value
    }

    private func store(_ kind: AnnotationKind, of id: AnnotationID, as name: String) {
        commitSheet(name) { sheet in
            guard var annotation = sheet.annotation(id) else { return }
            annotation.kind = kind
            sheet.setAnnotation(annotation)
        }
    }
}
