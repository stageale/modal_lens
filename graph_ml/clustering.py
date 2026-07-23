import numpy as np
from sklearn.cluster import AgglomerativeClustering
from sklearn.metrics import silhouette_score
from sklearn.metrics.pairwise import cosine_similarity

def similarity_matrix(features):
    return cosine_similarity(features)

def hierarchical_cluster(features, n_clusters=None):
    number_of_models = features.shape[0]
    
    if number_of_models == 0:
        return np.array([], dtype=int)
    
    if number_of_models == 1:
        return np.array([0], dtype=int)
    
    distances = _distance_matrix(features)
    
    if n_clusters is None:
        n_clusters = _cluster_count(distances)
        
    clustering = AgglomerativeClustering(n_clusters=n_clusters, metric="precomputed", linkage="average")
    
    return clustering.fit_predict(distances)

def _cluster_count(distances):
    number_of_models = len(distances)
    
    if number_of_models < 3:
        return 1
    
    maximum_clusters = min(7, number_of_models)
    
    best_clusters = 2
    best_score = -1
    
    for n_clusters in range(2, maximum_clusters):
        clustering = AgglomerativeClustering(n_clusters=n_clusters, metric="precomputed", linkage="average")
        
        labels = clustering.fit_predict(distances)
        
        score = silhouette_score(distances, labels, metric="precomputed")
        
        if score > best_score:
            best_score = score
            best_clusters = n_clusters
            
    return best_clusters

def _distance_matrix(features):
    distances = 1 - similarity_matrix(features)
    
    # Numeric error handling
    distances = np.clip(distances, 0, 1)
    np.fill_diagonal(distances, 0)
    
    return distances

def _cluster_medoid(indices, distances):
    cluster_distances = distances[
        np.ix_(indices, indices)
    ]
    
    distance_sums = cluster_distances.sum(axis=1)
    medoid_position = distance_sums.argmin()
    
    return indices[medoid_position]

def cluster_models(graphs, features, n_clusters=None):
    graphs = list(graphs)
    
    if len(graphs) != features.shape[0]:
        raise ValueError("Number ofg raphs and feature rows must match.")
    pass

    labels = hierarchical_cluster(features, n_clusters=n_clusters)
    
    distances = _distance_matrix(features)
    clusters = []
    
    for cluster_label in sorted(set(labels)):
        indices = np.where(labels == cluster_label)[0]
        
        medoid_index = _cluster_medoid(indices, distances)
        
        clusters.append({
            "cluster": int(cluster_label),
            "indices": indices.tolist(),
            "models": [graphs[index] for index in indices],
            "medoid_index": int(medoid_index),
            "medoid": graphs[medoid_index]
        })
    
    return clusters
