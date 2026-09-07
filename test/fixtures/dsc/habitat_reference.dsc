belief network "habitat_reference"
node Climate {
  type : discrete [ 3 ] = { "dry", "normal", "wet" };
}
node Irrigation {
  type : discrete [ 2 ] = { "low", "high" };
}
node SoilMoisture {
  type : discrete [ 3 ] = { "low", "medium", "high" };
}
node GrazingPressure {
  type : discrete [ 2 ] = { "low", "high" };
}
node Vegetation {
  type : discrete [ 3 ] = { "sparse", "moderate", "dense" };
}
node HabitatQuality {
  type : discrete [ 2 ] = { "poor", "good" };
}
node Occupancy {
  type : discrete [ 2 ] = { "absent", "present" };
}
probability ( Climate ) {
   0.3, 0.5, 0.2;
}
probability ( Irrigation ) {
   0.6, 0.4;
}
probability ( SoilMoisture | Climate, Irrigation ) {
  (0, 0) : 0.7, 0.25, 0.05;
  (1, 0) : 0.3, 0.5, 0.2;
  (2, 0) : 0.1, 0.4, 0.5;
  (0, 1) : 0.3, 0.5, 0.2;
  (1, 1) : 0.1, 0.4, 0.5;
  (2, 1) : 0.05, 0.25, 0.7;
}
probability ( GrazingPressure ) {
   0.5, 0.5;
}
probability ( Vegetation | SoilMoisture, GrazingPressure ) {
  (0, 0) : 0.6, 0.3, 0.1;
  (1, 0) : 0.2, 0.5, 0.3;
  (2, 0) : 0.05, 0.3, 0.65;
  (0, 1) : 0.8, 0.15, 0.05;
  (1, 1) : 0.4, 0.45, 0.15;
  (2, 1) : 0.2, 0.5, 0.3;
}
probability ( HabitatQuality | Vegetation ) {
  (0) : 0.85, 0.15;
  (1) : 0.4, 0.6;
  (2) : 0.15, 0.85;
}
probability ( Occupancy | HabitatQuality ) {
  (0) : 0.8, 0.2;
  (1) : 0.25, 0.75;
}
