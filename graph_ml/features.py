import networkx as nx
from collections import Counter
from itertools import combinations, permutations

import networkx as nx

#==================== WL Features ===================#

def wl_features(graphs, iterations=2):
    labels = [
        {
            node: _initial_node_label(attributes)
            for node, attributes in graph.nodes(data=True)
        } for graph in graphs
    ]
    
    features = [
        Counter(
            ("wl", 0, label)
            for label in graph_labels.values()
        )
        for graph_labels in labels
    ]
    
    for i in range(1, iterations + 1):
        refined_labels = []
        
        for graph, graph_labels in zip(graphs, labels):
            refined = {}
            
            for node in graph.nodes:
                outgoing = tuple(sorted((_edge_label(graph, node, succ), graph_labels[succ]) for succ in graph.successors(node)))
                
                ingoing = tuple(sorted((_edge_label(graph, predec, node), graph_labels[predec]) for predec in graph.predecessors(node)))
                
                refined[node] = (graph_labels[node], outgoing, ingoing)
            
            refined_labels.append(refined)
        
        labels = refined_labels
        
        for graph_features, graph_labels in zip(features, labels):
            graph_features.update(("wl", i, label) for label in graph_labels.values())
    
    return [dict(graph_features) for graph_features in features]

def _initial_node_label(attributes):
    valuations = tuple(sorted((name, value) for name, value in attributes.items() if name != "designated" and isinstance(value, bool)))
    return attributes.get("designated", False), valuations

def _edge_label(graph, source, target):
    return graph.edges[source, target].get("label", graph.graph.get("relation", "R"))

#================= Graphlet Features ================#


def graphlet_features(graphs, size=3):
    features = []
    
    for graph in graphs:
        graphlet_counts = Counter()
        
        for nodes in combinations(graph.nodes, size):
            subgraph = graph.subgraph(nodes)
            
            if not nx.is_weakly_connected(subgraph):
                continue
            
            graphlet = _canonical_graphlet(graph, nodes)
            
            graphlet_counts[("graphlet", size, graphlet)] += 1
        
        features.append(dict(graphlet_counts))
    
    return features

def _canonical_graphlet(graph, nodes):
    representations = []
    
    for ordering in permutations(nodes):
        node_labels = tuple(_initial_node_label(graph.nodes[node]) for node in ordering)
        
        edges = tuple((1, str(_edge_label(graph, source, target))) if graph.has_edge(source, target) else (0, "") for source in ordering
                                                                                                                  for target in ordering)
        
        representations.append((node_labels, edges))
        
    return min(representations)

#=================== Raw Features ===================#

def raw_features(graphs, modal_depth=3):
    features = []
    for graph in graphs:
        designated = next(node for node, data in graph.nodes(data=True) if data["designated"])
        
        features.append({
            "designated_successors": graph.out_degree(designated),
            "reachable_worlds": len(nx.descendants(graph, designated)),
            "k_step_reachable": len(_reachable_within(graph, designated, modal_depth)),
            "worlds": graph.number_of_nodes()
        })
        
    return features
        
def _reachable_within(graph, source, depth):
    reachable = {source}
    frontier = {source}
    
    for _ in range(depth):
        frontier = {successor for node in frontier for successor in graph.successors(node)}
        
        reachable |= frontier
    
    return reachable - {source}

def feature_matrix(graphs, method="wl"):
    #TODO: Generate the feature_matrix
    pass