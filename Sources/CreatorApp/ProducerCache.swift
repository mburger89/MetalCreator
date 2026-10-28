import CreatorGraph
import CreatorKernel

/// `GraphContent.levelProducers` for one document content and level (`AppModel.levelProducers()`).
struct ProducerCache {
    var content: GraphContent
    var level: [NodeID]
    var producers: [NodeID: NodeID]
}
