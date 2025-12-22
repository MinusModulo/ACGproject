// ============================================================================
// RNG.hlsl - 随机数生成模块
// ============================================================================

#ifndef RNG_HLSL
#define RNG_HLSL

// We need rand variables for Monte Carlo integration
// I leverage a simple Wang Hash + Xorshift RNG combo here
uint wang_hash(uint seed) {
  seed = (seed ^ 61) ^ (seed >> 16);
  seed *= 9;
  seed = seed ^ (seed >> 4);
  seed *= 0x27d4eb2;
  seed = seed ^ (seed >> 15);
  return seed;
}

uint rand_xorshift(inout uint rng_state) {
  rng_state ^= rng_state << 13;
  rng_state ^= rng_state >> 17;
  rng_state ^= rng_state << 5;
  return rng_state;
}

float rand(inout uint rng_state) {
  return float(rand_xorshift(rng_state)) * (1.0 / 4294967296.0);
} //rand will change rng_state

#endif // RNG_HLSL

