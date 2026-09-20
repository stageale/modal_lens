from collections import Counter
from itertools import combinations, permutations

import networkx as nx
from scipy.sparse import csr_matrix

def feature_matrix(feature_vectors):
    feature_vectors = list(feature_vectors)
    
    feature_names = sorted(
        {
            feature
            for vector in feature_vectors
            for feature in vector
        },
        key=repr
    )
    
    feature_indices = {
        feature: index 
        for index, feature in enumerate(feature_names)
    }
    
    rows = []
    columns = []
    values = []
    
    for row_index, vector in enumerate(feature_vectors):
        for feature, value in vector.items():
            rows.append(row_index)
            columns.append(feature_indices[feature])
            values.append(value)
            
    matrix = csr_matrix((values, (rows, columns)), shape=(len(feature_vectors), len(feature_names)), dtype=float)
    
    return matrix

def feature_vector(graph, method="wl", graphlet_size=3, graphlet_occurrences=None):
    if method == "wl":
        return wl_feature_vector(graph)
    
    if method == "graphlet":
        return graphlet_feature_vector(graph, size=graphlet_size, occurrences=graphlet_occurrences)
    
    if method == "raw":
        return raw_feature_vector(graph)
    
    if method == "combined":
        return {
            **raw_feature_vector(graph),
            **wl_feature_vector(graph),
            **graphlet_feature_vector(
                graph,
                size=graphlet_size,
                occurrences=graphlet_occurrences
            )
        }
        
    raise ValueError(f"Unknown feature method: {method}")

def _model_atoms(graph):
    atoms = graph.graph.get("atoms")
    
    if atoms is not None:
        return tuple(sorted(atoms))
    
    return tuple(sorted({
        atom
        for _, attributes in graph.nodes(data=True)
        for atom, value in attributes.items()
        if atom != "designated" and isinstance(value, bool)
    }))

#==================== WL Features ===================#


def wl_features(graphs, iterations=2):
    return [wl_feature_vector(graph, iterations) for graph in graphs]

def wl_feature_vector(graph, iterations=2):
    atoms = _model_atoms(graph)
    
    world_labels = {world: _world_valuation(attributes, atoms) for world, attributes in graph.nodes(data=True)}
    
    features = Counter(("wl", 0, label) for label in world_labels.values())
    
    for iteration in range(1, iterations + 1):
        world_labels = _refine_world_labels(graph, world_labels)
        
        features.update(("wl", iteration, label) for label in world_labels.values())
        
    return dict(features)


def _refine_world_labels(graph, world_labels):
    refined_labels = {}
    for world in graph.nodes:
        refined_labels[world] = (
            world_labels[world],
            _outgoing_context(graph, world, world_labels),
            _incoming_context(graph, world, world_labels)
        )
    return refined_labels
    
def _outgoing_context(graph, world, world_labels):
    context = [(_edge_label(graph, world, succ), world_labels[succ]) for succ in graph.successors(world)]
    return tuple(sorted(context))

def _incoming_context(graph, world, world_labels):
    context = [(_edge_label(graph, pred, world), world_labels[pred]) for pred in graph.predecessors(world)]
    return tuple(sorted(context))

def _edge_label(graph, source, target):
    return graph.edges[source, target].get("label", graph.graph.get("relation", "R"))

#================= Graphlet Features ================#


def graphlet_features(graphs, size=3):
    features = []
    
    for graph in graphs:
        graphlet_counts = Counter()
        atoms = _model_atoms(graph)
        for graphlet_size in range(2, size + 1):
            for nodes in combinations(graph.nodes, graphlet_size):
                subgraph = graph.subgraph(nodes)

                if not nx.is_weakly_connected(subgraph):
                    continue
                
                graphlet = _canonical_graphlet(graph, nodes, atoms)

                graphlet_counts[("graphlet", graphlet_size, graphlet)] += 1
        
        features.append(dict(graphlet_counts))
    
    return features

def graphlet_feature_vector(graph, size=3, occurrences=None):

    if occurrences is not None:
        return {pattern: len(worlds) for pattern, worlds in occurrences.items()}
    
    return graphlet_features([graph], size)[0]

def _world_valuation(attributes, atoms):
    return tuple(atom for atom in atoms if attributes.get(atom, False))

def _canonical_edge_label(label):
    if isinstance(label, (tuple, list)):
        return tuple(sorted(str(item) for item in label))

    return str(label)


def _canonical_graphlet(graph, nodes, atoms):
    representations = []
    
    for ordering in permutations(nodes):
        node_labels = tuple(_world_valuation(graph.nodes[world], atoms) for world in ordering)
        
        edges = tuple(
            (1, _canonical_edge_label(_edge_label(graph, source, target)))
            if graph.has_edge(source, target)
            else (0, None)
            for source in ordering
            for target in ordering
        )
        
        representations.append((node_labels, edges))
        
    return min(representations)

#=================== Raw Features ===================#

def raw_features(graphs, modal_depth=3):
    return [raw_feature_vector(graph, modal_depth) for graph in graphs]

def raw_feature_vector(graph, modal_depth=3):
    designated = next(node for node, data in graph.nodes(data=True) if data["designated"])
        
    return {
        "designated_successors": graph.out_degree(designated),
        "reachable_worlds": len(nx.descendants(graph, designated)),
        "k_step_reachable": len(_reachable_within(graph, designated, modal_depth)),
        "worlds": graph.number_of_nodes(),
        "relations": graph.number_of_edges(),
        "density": nx.density(graph)
    }        
    
    
        
def _reachable_within(graph, source, depth):
    reachable = {source}
    frontier = {source}
    
    for _ in range(depth):
        frontier = {successor for node in frontier for successor in graph.successors(node) if successor not in reachable}
        
        reachable |= frontier
        
        if not frontier:
            break
    
    return reachable - {source}
