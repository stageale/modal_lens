from collections import defaultdict, Counter
from itertools import combinations

import networkx as nx 

from graph_ml.features import _canonical_graphlet, _model_atoms

def pattern_occurrences(graph, size=3):
    atoms = _model_atoms(graph)
    occurrences = defaultdict(list)
    
    for worlds in combinations(graph.nodes, size):
        substructure = graph.subgraph(worlds)
        
        if nx.is_weakly_connected(substructure):
            pattern = ("graphlet", size, _canonical_graphlet(graph, worlds, atoms))
            occurrences[pattern].append(tuple(worlds))
    
    return dict(occurrences)

def graph_patterns(graph, size=3):
    return set(pattern_occurrences(graph, size))

def frequent_patterns(graphs, min_support=0.5, size=3):
    graphs = list(graphs)
    if graphs == []:
        return {}    
    pattern_counts = Counter()    
    for graph in graphs:
        pattern_counts.update(graph_patterns(graph, size))        
    return {pattern: count / len(graphs) for pattern, count in pattern_counts.items() if count / len(graphs) >= min_support}

def cluster_patterns(graphs, cluster_labels, min_support=0.5, min_contrast=0.2, size=3, occurrences_by_graph=None):
    graphs = list(graphs)
    cluster_labels = list(cluster_labels)
    
    if len(graphs) != len(cluster_labels):
        raise ValueError("Nummer of graphs and cluster labels must match.")
    
    if occurrences_by_graph is None:
        occurrences_by_graph = [pattern_occurrences(graph, size) for graph in graphs]
    else:
        occurrences_by_graph = list(occurrences_by_graph)
        if len(occurrences_by_graph) != len(graphs):
            raise ValueError("Number of graphs and graphlet occurrences must match.")
    
    patterns_by_graph = [set(occurrences) for occurrences in occurrences_by_graph]
    
    cluster_indices = defaultdict(list)
    
    for graph_index, cluster_label in enumerate(cluster_labels):
        cluster_indices[int(cluster_label)].append(graph_index)
        
    all_indices = set(range(len(graphs)))
    results = {}
    
    for cluster_label, inside_indices in cluster_indices.items():
        
        outside_indices = all_indices - set(inside_indices)
        candidate_patterns = set()
        
        for graph_index in inside_indices:
            candidate_patterns.update(patterns_by_graph[graph_index])
            
        patterns = []
        
        for pattern in candidate_patterns:
            
            inside_count = sum(pattern in patterns_by_graph[graph_index] for graph_index in inside_indices)
            cluster_support = inside_count / len(inside_indices)
            
            if cluster_support >= min_support:
                if outside_indices:
                    outside_count = sum(pattern in patterns_by_graph[graph_index] for graph_index in outside_indices)
                    outside_support = outside_count / len(outside_indices)
                else:
                    outside_support = 0.0
                    
                contrast = cluster_support - outside_support
                
                if contrast >= min_contrast:
                    occurrences = {graph_index: occurrences_by_graph[graph_index][pattern] 
                                   for graph_index in inside_indices if pattern in occurrences_by_graph[graph_index]}
                    patterns.append({
                        "pattern": pattern,
                        "cluster_support": cluster_support,
                        "outside_support": outside_support,
                        "contrast": contrast,
                        "occurrences": occurrences
                    })
                    
        patterns.sort(key=lambda item: (-item["cluster_support"], item["outside_support"], repr(item["pattern"])))
        
        results[cluster_label] = patterns
        
    return results
                    

def pattern_support(pattern, graphs, size=3):
    graphs = list(graphs)    
    if graphs == []:
        return 0.0
    else:
        containing_graphs = sum(pattern in graph_patterns(graph, size) for graph in graphs)    
        return containing_graphs / len(graphs)