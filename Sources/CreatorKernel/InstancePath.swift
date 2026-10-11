/// How a placed copy's position in its pattern is written in messages (patterns spec §2 and §6). Until the trees
/// land (sub-project 7a-trees) an instance is named by its flat index, `{3}`; its path then gains the tree's levels
/// (`{0;3}`) and this is the one place that writes it.
public enum InstancePath {
    public static func text(_ index: Int) -> String { "{\(index)}" }
}
