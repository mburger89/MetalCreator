import Foundation

/// A sheet's reusable beginnings (DR-5 R10): the paper, the standard and the title block's owner, drawn by, material and density,
/// and a logo's bytes. Kept in the person's own folder, never in a `.mcgraph`.
public struct DrawingTemplate: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var size: SheetSize
    public var orientation: SheetOrientation
    public var standard: DrawingStandard
    public var titleBlock: TitleBlock
    public var logo: Data?

    public init(
        id: String, name: String, size: SheetSize, orientation: SheetOrientation, standard: DrawingStandard,
        titleBlock: TitleBlock = TitleBlock(), logo: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.size = size
        self.orientation = orientation
        self.standard = standard
        self.titleBlock = Self.defaults(of: titleBlock)
        self.logo = logo
    }

    /// The template of `sheet`: its size and orientation, the drawing's `standard`, and only the owner, drawn by, material and
    /// density of its title block (the title, number, revision, date and the logo's hash are cleared; the bytes are `logo`).
    public static func made(from sheet: DrawingSheet, standard: DrawingStandard, logo: Data?, name: String, id: String) -> DrawingTemplate {
        DrawingTemplate(
            id: id, name: name, size: sheet.size, orientation: sheet.orientation, standard: standard,
            titleBlock: sheet.titleBlock, logo: logo)
    }

    static func defaults(of block: TitleBlock) -> TitleBlock {
        TitleBlock(owner: block.owner, material: block.material, drawnBy: block.drawnBy, density: block.density)
    }
}
