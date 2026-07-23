import argparse as ap
from pathlib import Path

import graph_ml.python.io_schema as io
import graph_ml.python.features as feat
import graph_ml.python.clustering as cluster
import graph_ml.python.mining as mine

def plot_heatmap(features, feature_names, cluster_labels):
    #TODO: Implement a heat map for visual explanation
    #? Maybe shifted to Elixir
    pass

def subroutine():
    parser = ap.ArgumentParser()
    parser.add_argument("json", type=Path)
    args = parser.parse_args()
    
    metadata, graph = io.parse_model(args.json)
    
    #TODO: Start Machine Learning

if __name__ == "__subroutine__":
    subroutine()