from graphviz import Digraph

dot = Digraph("PathTracer", format="png")
dot.attr(rankdir="LR", fontsize="12")

# CPU
dot.node("CPU", "CPU\nScene & Camera\nCmdDispatchRays")

# GPU Pipeline
dot.node("RayGen", "RayGen Shader\nshader.hlsl\nPrimary Rays & Path Loop")
dot.node("Trace", "TraceRay\nHardware Ray Tracing")
dot.node("Miss", "Miss Shader\nEnvironment Sampling")
dot.node("CH", "Closest Hit Shader\nSurface Interaction")

# Shading Modules
with dot.subgraph(name="cluster_shading") as c:
    c.attr(label="Modular Shading System (HLSL)", style="dashed")
    c.node("Common", "common.hlsl\nBuffers & Bindings")
    c.node("RNG", "rng.hlsl\nRandom Sampling")
    c.node("BRDF", "brdf.hlsl\nMaterial Evaluation")
    c.node("Sampling", "sampling.hlsl\nImportance Sampling")
    c.node("LightSampling", "light_sampling.hlsl\nLight Sampling")
    c.node("Shadow", "shadow.hlsl\nShadow Rays")
    c.node("Direct", "direct_lighting.hlsl\nNEE + MIS")

# Output
dot.node("Accum", "Accumulation & Output\nTone Mapping")

# Edges
dot.edge("CPU", "RayGen")
dot.edge("RayGen", "Trace")
dot.edge("Trace", "CH", label="Hit")
dot.edge("Trace", "Miss", label="Miss")

dot.edge("Miss", "Accum")
dot.edge("CH", "Direct")
dot.edge("Direct", "Shadow")
dot.edge("Direct", "BRDF")
dot.edge("BRDF", "Sampling")
dot.edge("Sampling", "RNG")

dot.edge("LightSampling", "Direct")
dot.edge("Common", "BRDF")
dot.edge("Common", "Direct")

dot.edge("CH", "RayGen")
dot.edge("RayGen", "Accum")

dot.render("path_tracer_pipeline_diagram", view=True)