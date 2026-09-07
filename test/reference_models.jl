# Reference models written directly as IR. They are the source of the generated fixtures
# (scripts/regenerate_fixtures.jl) and the oracle for the cross-format tests.

using BayesianNetworkFormats

"""
    habitat_reference_ir() -> NetworkIR

The SPEC §45 reference ecological Bayesian network:
Climate → SoilMoisture ← Irrigation; SoilMoisture → Vegetation ← GrazingPressure;
Vegetation → HabitatQuality → Occupancy.
"""
function habitat_reference_ir()
    vars = IRVariable[]
    push!(vars,
          IRVariable(:Climate; title="Climate", states=["dry", "normal", "wet"],
                     table=[0.3, 0.5, 0.2], position=(100.0, 60.0),
                     comment="Regional climate regime."))
    push!(vars,
          IRVariable(:Irrigation; title="Irrigation", states=["low", "high"],
                     table=[0.6, 0.4], position=(300.0, 60.0)))
    # (Climate, Irrigation, SoilMoisture): one row per (climate, irrigation) pair
    sm = zeros(3, 2, 3)
    sm[1, 1, :] = [0.7, 0.25, 0.05]    # dry, low
    sm[1, 2, :] = [0.3, 0.5, 0.2]      # dry, high
    sm[2, 1, :] = [0.3, 0.5, 0.2]      # normal, low
    sm[2, 2, :] = [0.1, 0.4, 0.5]      # normal, high
    sm[3, 1, :] = [0.1, 0.4, 0.5]      # wet, low
    sm[3, 2, :] = [0.05, 0.25, 0.7]    # wet, high
    push!(vars,
          IRVariable(:SoilMoisture; title="Soil moisture", states=["low", "medium", "high"],
                     parents=[:Climate, :Irrigation], table=sm, position=(200.0, 150.0)))
    push!(vars,
          IRVariable(:GrazingPressure; title="Grazing pressure", states=["low", "high"],
                     table=[0.5, 0.5], position=(400.0, 150.0)))
    veg = zeros(3, 2, 3)               # (SoilMoisture, GrazingPressure, Vegetation)
    veg[1, 1, :] = [0.6, 0.3, 0.1]     # low moisture, low grazing
    veg[1, 2, :] = [0.8, 0.15, 0.05]   # low moisture, high grazing
    veg[2, 1, :] = [0.2, 0.5, 0.3]
    veg[2, 2, :] = [0.4, 0.45, 0.15]
    veg[3, 1, :] = [0.05, 0.3, 0.65]
    veg[3, 2, :] = [0.2, 0.5, 0.3]
    push!(vars,
          IRVariable(:Vegetation; title="Vegetation",
                     states=["sparse", "moderate", "dense"],
                     parents=[:SoilMoisture, :GrazingPressure], table=veg,
                     position=(300.0, 240.0)))
    push!(vars,
          IRVariable(:HabitatQuality; title="Habitat quality", states=["poor", "good"],
                     parents=[:Vegetation], table=[0.85 0.15; 0.4 0.6; 0.15 0.85],
                     position=(300.0, 330.0)))
    push!(vars,
          IRVariable(:Occupancy; title="Occupancy", states=["absent", "present"],
                     parents=[:HabitatQuality], table=[0.8 0.2; 0.25 0.75],
                     position=(300.0, 420.0)))
    return NetworkIR("habitat_reference", vars;
                     extras=Dict{Symbol,Any}(:comment => "SPEC section 45 reference ecological Bayesian network."))
end

const _VEG_BY_SCORE = Dict(-3 => [0.85, 0.12, 0.03], -2 => [0.7, 0.25, 0.05],
                           -1 => [0.5, 0.35, 0.15],
                           0 => [0.3, 0.4, 0.3], 1 => [0.15, 0.35, 0.5],
                           2 => [0.05, 0.25, 0.7],
                           3 => [0.03, 0.12, 0.85])

"""
    grazing_reference_ir() -> NetworkIR

The SPEC §46 reference ecological influence diagram: decision `GrazingManagement` informed
by `ClimateForecast` and `CurrentVegetation`, uncertain implementation through
`GrazingPressure`, utilities `ConservationBenefit(Biodiversity)` and
`ManagementCost(GrazingManagement)` summed by the MAU node `TotalUtility`.
"""
function grazing_reference_ir()
    vars = IRVariable[]
    push!(vars,
          IRVariable(:Climate; title="Climate", states=["dry", "normal", "wet"],
                     table=[0.3, 0.5, 0.2], position=(100.0, 60.0)))
    push!(vars,
          IRVariable(:ClimateForecast; title="Climate forecast",
                     states=["dry", "normal", "wet"],
                     parents=[:Climate], table=[0.7 0.2 0.1; 0.15 0.7 0.15; 0.1 0.2 0.7],
                     position=(100.0, 150.0)))
    push!(vars,
          IRVariable(:SoilMoisture; title="Soil moisture", states=["low", "medium", "high"],
                     parents=[:Climate], table=[0.7 0.25 0.05; 0.3 0.5 0.2; 0.05 0.3 0.65],
                     position=(250.0, 150.0)))
    push!(vars,
          IRVariable(:CurrentVegetation; title="Current vegetation",
                     states=["sparse", "moderate", "dense"], table=[0.3, 0.4, 0.3],
                     position=(400.0, 60.0)))
    push!(vars,
          IRVariable(:GrazingManagement; title="Grazing management", kind=DecisionNode,
                     states=["exclude", "reduce", "maintain"],
                     parents=[:ClimateForecast, :CurrentVegetation],
                     position=(100.0, 240.0),
                     comment="Information arcs from the forecast and the current vegetation survey."))
    push!(vars,
          IRVariable(:GrazingPressure; title="Grazing pressure", states=["low", "high"],
                     parents=[:GrazingManagement], table=[0.95 0.05; 0.6 0.4; 0.15 0.85],
                     position=(250.0, 240.0),
                     comment="Uncertain implementation of the management decision."))
    veg = zeros(3, 2, 3, 3)            # (SoilMoisture, GrazingPressure, CurrentVegetation, Vegetation)
    for m in 1:3, g in 1:2, c in 1:3
        score = (m - 2) + (g == 1 ? 1 : -1) + (c - 2)
        veg[m, g, c, :] = _VEG_BY_SCORE[score]
    end
    push!(vars,
          IRVariable(:Vegetation; title="Vegetation",
                     states=["sparse", "moderate", "dense"],
                     parents=[:SoilMoisture, :GrazingPressure, :CurrentVegetation],
                     table=veg,
                     position=(400.0, 240.0)))
    push!(vars,
          IRVariable(:HabitatQuality; title="Habitat quality", states=["poor", "good"],
                     parents=[:Vegetation], table=[0.85 0.15; 0.4 0.6; 0.15 0.85],
                     position=(400.0, 330.0)))
    push!(vars,
          IRVariable(:Occupancy; title="Occupancy", states=["absent", "present"],
                     parents=[:HabitatQuality], table=[0.8 0.2; 0.25 0.75],
                     position=(400.0, 420.0)))
    push!(vars,
          IRVariable(:Biodiversity; title="Biodiversity", states=["low", "high"],
                     parents=[:Occupancy], table=[0.9 0.1; 0.3 0.7],
                     position=(400.0, 510.0)))
    push!(vars,
          IRVariable(:ConservationBenefit; title="Conservation benefit", kind=UtilityNode,
                     parents=[:Biodiversity], table=[0.0, 100.0], position=(400.0, 600.0)))
    push!(vars,
          IRVariable(:ManagementCost; title="Management cost", kind=UtilityNode,
                     parents=[:GrazingManagement], table=[-40.0, -15.0, 0.0],
                     position=(100.0, 600.0)))
    return NetworkIR("grazing_reference_id", vars;
                     mau=[MAUNode(:TotalUtility, [:ConservationBenefit, :ManagementCost],
                                  [1.0, 1.0])],
                     extras=Dict{Symbol,Any}(:comment => "SPEC section 46 reference ecological influence diagram."))
end

"""
    umbrella_ir() -> NetworkIR

Shachter's umbrella problem: `Weather` (sunny 0.7 / rainy 0.3), `Forecast` given weather,
decision `Umbrella` informed by the forecast, utility `U(Weather, Umbrella)`.
"""
function umbrella_ir()
    vars = IRVariable[]
    push!(vars,
          IRVariable(:Weather; title="Weather", states=["sunny", "rainy"], table=[0.7, 0.3],
                     position=(100.0, 60.0)))
    push!(vars,
          IRVariable(:Forecast; title="Forecast", states=["sunny", "cloudy", "rainy"],
                     parents=[:Weather], table=[0.7 0.2 0.1; 0.15 0.25 0.6],
                     position=(100.0, 180.0)))
    push!(vars,
          IRVariable(:Umbrella; title="Take umbrella?", kind=DecisionNode,
                     states=["take", "leave"],
                     parents=[:Forecast], position=(300.0, 180.0)))
    push!(vars,
          IRVariable(:U; title="Satisfaction", kind=UtilityNode,
                     parents=[:Weather, :Umbrella],
                     table=[20.0 100.0; 70.0 0.0], position=(300.0, 60.0)))
    return NetworkIR("umbrella", vars)
end

"""
    sprinkler_ir() -> NetworkIR

The small network behind `bif/sprinkler_table.bif` (hand-written in pgmpy table form).
"""
function sprinkler_ir()
    grass = zeros(2, 2, 2)             # (Sprinkler, Rain, Grass)
    grass[1, 1, :] = [0.99, 0.01]      # on, yes
    grass[1, 2, :] = [0.9, 0.1]        # on, no
    grass[2, 1, :] = [0.8, 0.2]        # off, yes
    grass[2, 2, :] = [0.0, 1.0]        # off, no
    return NetworkIR("sprinkler",
                     [IRVariable(:Rain; states=["yes", "no"], table=[0.2, 0.8],
                                 position=(100.0, 50.0),
                                 extras=Dict{Symbol,Any}(:properties => ["weight = 0.5"])),
                      IRVariable(:Sprinkler; states=["on", "off"], parents=[:Rain],
                                 table=[0.01 0.99; 0.4 0.6]),
                      IRVariable(:Grass; states=["wet", "dry"], parents=[:Sprinkler, :Rain],
                                 table=grass)])
end
